-- Auto-Link Auth User to HR Employee
-- ====================================
-- When a user signs in for the first time (via Google OAuth or email/password),
-- Supabase creates a row in auth.users. This trigger automatically links that
-- new auth.users row to an existing hr_employee record by matching the email
-- to hr_employee.company_email.
--
-- Business Rule:
--   Only employees with a company_email in hr_employee can sign in.
--   On first login, auth.users.id is written to hr_employee.user_id.
--   If no matching hr_employee.company_email exists, the user can authenticate
--   but will have no org membership — the app will show "no access."
--
-- Flow:
--   1. User clicks "Sign in with Google" (or email/password)
--   2. Supabase Auth creates auth.users row (enable_signup = true)
--   3. This trigger fires AFTER INSERT on auth.users
--   4. Matches auth.users.email → hr_employee.company_email
--   5. Sets hr_employee.user_id = NEW.id for ALL matching rows (multi-org)
--   6. User now has org access via RLS policies that check auth.uid()

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.hr_employee
  SET user_id = NEW.id
  WHERE company_email = NEW.email
    AND user_id IS NULL;

  RETURN NEW;
END;
$$;

-- Trigger fires after every new auth.users insert (i.e., first-time sign-in)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

-- Grant execute to authenticated and service_role
GRANT EXECUTE ON FUNCTION public.handle_new_auth_user() TO service_role;

-- Backfill: link any existing auth.users to hr_employee rows.
-- Idempotent — only updates rows where user_id is currently NULL.
UPDATE public.hr_employee e
SET user_id = u.id
FROM auth.users u
WHERE e.company_email = u.email
  AND e.user_id IS NULL;
