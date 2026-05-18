-- RECOVERED FROM PROD via pull-prod-drift workflow.
-- Original prod migration: version=20260516014059, name='add_anon_read_for_cuke_harvest_sources'.
-- Review the SQL below, rename this file, and edit before
-- treating as authoritative.


CREATE POLICY grow_harvest_weight_read_anon ON public.grow_harvest_weight
  FOR SELECT TO anon USING (true);

CREATE POLICY grow_cuke_seed_batch_read_anon ON public.grow_cuke_seed_batch
  FOR SELECT TO anon USING (true);

CREATE POLICY invnt_item_read_anon ON public.invnt_item
  FOR SELECT TO anon USING (true);

