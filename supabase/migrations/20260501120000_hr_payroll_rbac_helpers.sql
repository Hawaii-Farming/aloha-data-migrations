-- hr_payroll_rbac_helpers
-- =======================
-- Two SECURITY DEFINER + STABLE SQL helpers used by the payroll views to:
--   (a) decide row scope per access level (Owner / Admin / Manager / Team
--       Lead / Employee), and
--   (b) decide whether to NULL-mask the dollar columns (Team Lead).
--
-- Modeled on get_user_org_ids() in 20260401000200_sys_rls_policies.sql:
-- SECURITY DEFINER bypasses RLS on hr_employee safely (we only ever look
-- up the caller's own row); STABLE lets the planner fold repeated calls
-- inside a single statement so the per-column CASE expressions don't
-- re-execute the helper for every row.
--
-- Both helpers take the org as TEXT because hr_payroll.org_id and
-- hr_employee.org_id are TEXT, not UUID.

-- auth_employee_id(target_org)
-- Returns the current user's hr_employee.id within the given org, or NULL
-- if the user has no employee record there.
CREATE OR REPLACE FUNCTION public.auth_employee_id(target_org TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND org_id = target_org
    AND is_deleted = false
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.auth_employee_id(TEXT) TO authenticated;

COMMENT ON FUNCTION public.auth_employee_id(TEXT) IS
  'Returns the current auth.uid()''s hr_employee.id within the supplied org_id. SECURITY DEFINER + STABLE so it can be called inline from views without re-evaluating per row and without tripping RLS on hr_employee.';

-- auth_access_level(target_org)
-- Returns the current user's sys_access_level_id within the given org
-- (one of 'Owner', 'Admin', 'Manager', 'Team Lead', 'Employee'), or NULL
-- if the user has no employee record there.
CREATE OR REPLACE FUNCTION public.auth_access_level(target_org TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT sys_access_level_id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND org_id = target_org
    AND is_deleted = false
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.auth_access_level(TEXT) TO authenticated;

COMMENT ON FUNCTION public.auth_access_level(TEXT) IS
  'Returns the current auth.uid()''s sys_access_level_id within the supplied org_id. SECURITY DEFINER + STABLE for safe inline use in views (e.g. CASE WHEN auth_access_level(org_id) = ''Team Lead'' THEN NULL ELSE col END).';
