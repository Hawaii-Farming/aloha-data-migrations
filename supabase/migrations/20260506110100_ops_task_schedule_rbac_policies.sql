-- ops_task_schedule — RBAC-scoped RLS policies
-- ============================================
-- Replaces the org-only SELECT/INSERT/UPDATE/DELETE policies shipped
-- in 20260401000200_sys_rls_policies.sql with RBAC-scoped versions
-- so direct PostgREST queries against ops_task_schedule (used by
-- the Scheduler sub-module's detail / create / edit routes) honour
-- the same row-scope as the ops_task_weekly_schedule view.
--
-- Visibility matrix:
--   Owner / Admin                : all org rows
--   Manager / Team Lead          : self + direct reports (hr_employee.team_lead_id = self)
--   Employee                     : no rows
--
-- Reuses public.auth_employee_id(TEXT) / public.auth_access_level(TEXT)
-- SECURITY DEFINER STABLE helpers from 20260501120000_hr_payroll_rbac_helpers.sql.

-- Drop existing org-only policies
DROP POLICY IF EXISTS "ops_task_schedule_read"   ON public.ops_task_schedule;
DROP POLICY IF EXISTS "ops_task_schedule_insert" ON public.ops_task_schedule;
DROP POLICY IF EXISTS "ops_task_schedule_update" ON public.ops_task_schedule;
DROP POLICY IF EXISTS "ops_task_schedule_delete" ON public.ops_task_schedule;

-- Reusable predicate (inline-expanded in each policy below for clarity).
-- Note we keep the existing org-isolation check — RLS predicates AND
-- together, so a row must satisfy BOTH the org check AND the RBAC
-- check.

CREATE POLICY "ops_task_schedule_read" ON public.ops_task_schedule
  FOR SELECT TO authenticated
  USING (
    org_id IN (SELECT public.get_user_org_ids())
    AND (
      public.auth_access_level(org_id) IN ('Owner', 'Admin')
      OR (
        public.auth_access_level(org_id) IN ('Manager', 'Team Lead')
        AND (
          hr_employee_id = public.auth_employee_id(org_id)
          OR EXISTS (
            SELECT 1 FROM public.hr_employee e
            WHERE e.id = ops_task_schedule.hr_employee_id
              AND e.org_id = ops_task_schedule.org_id
              AND e.team_lead_id = public.auth_employee_id(org_id)
              AND e.is_deleted = false
          )
        )
      )
    )
  );

CREATE POLICY "ops_task_schedule_insert" ON public.ops_task_schedule
  FOR INSERT TO authenticated
  WITH CHECK (
    org_id IN (SELECT public.get_user_org_ids())
    AND (
      public.auth_access_level(org_id) IN ('Owner', 'Admin')
      OR (
        public.auth_access_level(org_id) IN ('Manager', 'Team Lead')
        AND (
          hr_employee_id = public.auth_employee_id(org_id)
          OR EXISTS (
            SELECT 1 FROM public.hr_employee e
            WHERE e.id = ops_task_schedule.hr_employee_id
              AND e.org_id = ops_task_schedule.org_id
              AND e.team_lead_id = public.auth_employee_id(org_id)
              AND e.is_deleted = false
          )
        )
      )
    )
  );

CREATE POLICY "ops_task_schedule_update" ON public.ops_task_schedule
  FOR UPDATE TO authenticated
  USING (
    org_id IN (SELECT public.get_user_org_ids())
    AND (
      public.auth_access_level(org_id) IN ('Owner', 'Admin')
      OR (
        public.auth_access_level(org_id) IN ('Manager', 'Team Lead')
        AND (
          hr_employee_id = public.auth_employee_id(org_id)
          OR EXISTS (
            SELECT 1 FROM public.hr_employee e
            WHERE e.id = ops_task_schedule.hr_employee_id
              AND e.org_id = ops_task_schedule.org_id
              AND e.team_lead_id = public.auth_employee_id(org_id)
              AND e.is_deleted = false
          )
        )
      )
    )
  )
  WITH CHECK (
    org_id IN (SELECT public.get_user_org_ids())
    AND (
      public.auth_access_level(org_id) IN ('Owner', 'Admin')
      OR (
        public.auth_access_level(org_id) IN ('Manager', 'Team Lead')
        AND (
          hr_employee_id = public.auth_employee_id(org_id)
          OR EXISTS (
            SELECT 1 FROM public.hr_employee e
            WHERE e.id = ops_task_schedule.hr_employee_id
              AND e.org_id = ops_task_schedule.org_id
              AND e.team_lead_id = public.auth_employee_id(org_id)
              AND e.is_deleted = false
          )
        )
      )
    )
  );

CREATE POLICY "ops_task_schedule_delete" ON public.ops_task_schedule
  FOR DELETE TO authenticated
  USING (
    org_id IN (SELECT public.get_user_org_ids())
    AND (
      public.auth_access_level(org_id) IN ('Owner', 'Admin')
      OR (
        public.auth_access_level(org_id) IN ('Manager', 'Team Lead')
        AND (
          hr_employee_id = public.auth_employee_id(org_id)
          OR EXISTS (
            SELECT 1 FROM public.hr_employee e
            WHERE e.id = ops_task_schedule.hr_employee_id
              AND e.org_id = ops_task_schedule.org_id
              AND e.team_lead_id = public.auth_employee_id(org_id)
              AND e.is_deleted = false
          )
        )
      )
    )
  );
