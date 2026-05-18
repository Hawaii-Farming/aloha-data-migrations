-- Add INSERT/UPDATE/DELETE policies + grants for the new pack_session_*
-- tables, mirroring the pattern used in 20260401000200_sys_rls_policies.sql
-- for pack_lot, pack_lot_item, pack_productivity_hour, etc.
--
-- Without these the user-scoped Supabase client (authenticated role)
-- silently fails on INSERT — which is why the workflow loader could not
-- auto-create today's pack_session.

-- pack_session
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

GRANT INSERT, UPDATE, DELETE ON public.pack_session TO authenticated;

-- pack_session_product_run
CREATE POLICY "pack_session_product_run_insert" ON public.pack_session_product_run
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_product_run_update" ON public.pack_session_product_run
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_product_run_delete" ON public.pack_session_product_run
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_session_product_run TO authenticated;

-- pack_session_leftover
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

GRANT INSERT, UPDATE, DELETE ON public.pack_session_leftover TO authenticated;

-- pack_session_product_hour
CREATE POLICY "pack_session_product_hour_insert" ON public.pack_session_product_hour
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_product_hour_update" ON public.pack_session_product_hour
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_session_product_hour_delete" ON public.pack_session_product_hour
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_session_product_hour TO authenticated;
