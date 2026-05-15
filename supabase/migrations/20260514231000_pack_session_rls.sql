-- RLS for the new pack_session* tables. Mirror the existing pattern: SELECT-only,
-- gated on org_id IN (SELECT public.get_user_org_ids()). Writes go through service-role.

-- pack_variety
ALTER TABLE public.pack_variety ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_variety_read" ON public.pack_variety
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_variety TO authenticated;

-- pack_session
ALTER TABLE public.pack_session ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_read" ON public.pack_session
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_session TO authenticated;

-- pack_session_product_run
ALTER TABLE public.pack_session_product_run ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_product_run_read" ON public.pack_session_product_run
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_session_product_run TO authenticated;

-- pack_session_leftover
ALTER TABLE public.pack_session_leftover ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_leftover_read" ON public.pack_session_leftover
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_session_leftover TO authenticated;

-- pack_session_product_hour
ALTER TABLE public.pack_session_product_hour ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_session_product_hour_read" ON public.pack_session_product_hour
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_session_product_hour TO authenticated;
