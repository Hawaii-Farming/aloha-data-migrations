-- Pack restructure step 16/17: RLS + write policies for renamed/restructured tables.
-- Mirror the prior pattern: SELECT/INSERT/UPDATE/DELETE for authenticated users scoped by
-- get_user_org_ids().
--
-- Postgres preserves policies when a table is renamed (they stay attached to the same OID),
-- but the policy *names* still reflect the old table name. We drop those legacy-named
-- policies first, then create canonical policy names matching the new table names.

-- ────────────── pack_session (formerly pack_session_product_run)
DROP POLICY IF EXISTS "pack_session_product_run_read"   ON public.pack_session;
DROP POLICY IF EXISTS "pack_session_product_run_insert" ON public.pack_session;
DROP POLICY IF EXISTS "pack_session_product_run_update" ON public.pack_session;
DROP POLICY IF EXISTS "pack_session_product_run_delete" ON public.pack_session;

ALTER TABLE public.pack_session ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_read" ON public.pack_session
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_insert" ON public.pack_session
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_update" ON public.pack_session
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_delete" ON public.pack_session
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pack_session TO authenticated;

-- ────────────── pack_session_labor_hour (formerly pack_productivity_hour)
DROP POLICY IF EXISTS "pack_productivity_hour_read"   ON public.pack_session_labor_hour;
DROP POLICY IF EXISTS "pack_productivity_hour_insert" ON public.pack_session_labor_hour;
DROP POLICY IF EXISTS "pack_productivity_hour_update" ON public.pack_session_labor_hour;
DROP POLICY IF EXISTS "pack_productivity_hour_delete" ON public.pack_session_labor_hour;

ALTER TABLE public.pack_session_labor_hour ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_labor_hour_read" ON public.pack_session_labor_hour
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_labor_hour_insert" ON public.pack_session_labor_hour
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_labor_hour_update" ON public.pack_session_labor_hour
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_labor_hour_delete" ON public.pack_session_labor_hour
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pack_session_labor_hour TO authenticated;

-- ────────────── pack_session_cases (formerly pack_session_product_hour)
DROP POLICY IF EXISTS "pack_session_product_hour_read"   ON public.pack_session_cases;
DROP POLICY IF EXISTS "pack_session_product_hour_insert" ON public.pack_session_cases;
DROP POLICY IF EXISTS "pack_session_product_hour_update" ON public.pack_session_cases;
DROP POLICY IF EXISTS "pack_session_product_hour_delete" ON public.pack_session_cases;

ALTER TABLE public.pack_session_cases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_cases_read" ON public.pack_session_cases
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_cases_insert" ON public.pack_session_cases
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_cases_update" ON public.pack_session_cases
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_cases_delete" ON public.pack_session_cases
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pack_session_cases TO authenticated;

-- ────────────── pack_session_leftover (table kept its name; columns changed)
-- Existing policies still apply; ENABLE is idempotent.
ALTER TABLE public.pack_session_leftover ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (idempotent recreate to ensure they match the post-restructure shape).
DROP POLICY IF EXISTS "pack_session_leftover_read"   ON public.pack_session_leftover;
DROP POLICY IF EXISTS "pack_session_leftover_insert" ON public.pack_session_leftover;
DROP POLICY IF EXISTS "pack_session_leftover_update" ON public.pack_session_leftover;
DROP POLICY IF EXISTS "pack_session_leftover_delete" ON public.pack_session_leftover;

CREATE POLICY "pack_session_leftover_read" ON public.pack_session_leftover
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_leftover_insert" ON public.pack_session_leftover
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_leftover_update" ON public.pack_session_leftover
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_leftover_delete" ON public.pack_session_leftover
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pack_session_leftover TO authenticated;

-- ────────────── pack_session_fails (formerly pack_productivity_hour_fail)
DROP POLICY IF EXISTS "pack_productivity_hour_fail_read"   ON public.pack_session_fails;
DROP POLICY IF EXISTS "pack_productivity_hour_fail_insert" ON public.pack_session_fails;
DROP POLICY IF EXISTS "pack_productivity_hour_fail_update" ON public.pack_session_fails;
DROP POLICY IF EXISTS "pack_productivity_hour_fail_delete" ON public.pack_session_fails;

ALTER TABLE public.pack_session_fails ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_fails_read" ON public.pack_session_fails
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_fails_insert" ON public.pack_session_fails
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_fails_update" ON public.pack_session_fails
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_fails_delete" ON public.pack_session_fails
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pack_session_fails TO authenticated;

-- ────────────── pack_moisture (formerly pack_dryer_result)
-- The old pack_dryer_result policies (defined in 20260401000200_sys_rls_policies.sql) survive
-- the table rename. No re-grant needed; this comment notes the carry-over for clarity.

-- ────────────── pack_fail_category (formerly pack_productivity_fail_category)
-- Same as pack_moisture — policies carry over with the rename.
