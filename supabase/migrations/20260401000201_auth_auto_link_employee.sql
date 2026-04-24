-- Auto-Link Auth User to HR Employee
-- ====================================
-- When a user signs in for the first time (via Google OAuth or email/password),
-- Supabase creates a row in auth.users. This trigger automatically links that
-- new auth.users row to an existing hr_employee record by matching the email
-- to hr_employee.company_email.
--
-- Security Gate: email_confirmed_at
-- ----------------------------------
-- The trigger only executes the link when NEW.email_confirmed_at IS NOT NULL.
-- This prevents unverified email addresses from being auto-linked to employee
-- records. For OAuth providers (e.g., Google), email_confirmed_at is set at
-- INSERT time, so the AFTER INSERT trigger handles it. For email/password
-- signups, email_confirmed_at is set on confirmation (UPDATE), so a second
-- trigger (on_auth_user_confirmed) handles that flow.
--
-- Audit Log: auth_link_log
-- -------------------------
-- Every successful link event is recorded in public.auth_link_log for
-- auditing. This table is only accessible by service_role/postgres.
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
--   3. Trigger fires AFTER INSERT (or AFTER UPDATE of email_confirmed_at)
--   4. Guard: skips if email_confirmed_at IS NULL
--   5. Matches auth.users.email -> hr_employee.company_email
--   6. Sets hr_employee.user_id = NEW.id for ALL matching rows (multi-org)
--   7. Logs link events to auth_link_log
--   8. User now has org access via RLS policies that check auth.uid()

-- ============================================================
-- Audit table: auth_link_log
-- ============================================================
-- Internal audit table — no SELECT grant to authenticated.
-- Readable only by service_role/postgres.

CREATE TABLE IF NOT EXISTS public.auth_link_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL,
  employee_id TEXT NOT NULL,
  linked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- Trigger function: handle_new_auth_user
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Gate: only link verified email addresses
  IF NEW.email_confirmed_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Link employee records and log each link event
  WITH linked AS (
    UPDATE public.hr_employee
    SET user_id = NEW.id
    WHERE company_email = NEW.email
      AND user_id IS NULL
    RETURNING id AS employee_id
  )
  INSERT INTO public.auth_link_log (auth_user_id, employee_id)
  SELECT NEW.id, linked.employee_id FROM linked;

  RETURN NEW;
END;
$$;

-- ============================================================
-- Triggers on auth.users
-- ============================================================

-- Fires on first-time sign-in (OAuth providers set email_confirmed_at at insert)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

-- Fires on email confirmation (email/password flow)
DROP TRIGGER IF EXISTS on_auth_user_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_confirmed
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  WHEN (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
  EXECUTE FUNCTION public.handle_new_auth_user();

-- ============================================================
-- Grants
-- ============================================================

GRANT EXECUTE ON FUNCTION public.handle_new_auth_user() TO service_role;
GRANT INSERT ON public.auth_link_log TO service_role;

-- ============================================================
-- Backfill (commented out — run manually if needed)
-- ============================================================
-- Link existing confirmed auth users to employees who have not
-- yet been linked. Respects the email_confirmed_at gate.
--
-- UPDATE public.hr_employee e
-- SET user_id = u.id
-- FROM auth.users u
-- WHERE u.email = e.company_email
--   AND u.email_confirmed_at IS NOT NULL
--   AND e.user_id IS NULL;
