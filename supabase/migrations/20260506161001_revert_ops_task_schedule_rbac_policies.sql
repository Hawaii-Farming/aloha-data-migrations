-- Revert: ops_task_schedule RBAC RLS policies
-- ============================================
-- Drops RBAC-scoped SELECT/INSERT/UPDATE/DELETE policies and restores
-- the original org-only policies from 20260401000200_sys_rls_policies.sql.

DROP POLICY IF EXISTS "ops_task_schedule_read"   ON public.ops_task_schedule;
DROP POLICY IF EXISTS "ops_task_schedule_insert" ON public.ops_task_schedule;
DROP POLICY IF EXISTS "ops_task_schedule_update" ON public.ops_task_schedule;
DROP POLICY IF EXISTS "ops_task_schedule_delete" ON public.ops_task_schedule;

CREATE POLICY "ops_task_schedule_read" ON public.ops_task_schedule
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_schedule_insert" ON public.ops_task_schedule
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_schedule_update" ON public.ops_task_schedule
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_schedule_delete" ON public.ops_task_schedule
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));
