-- Break the TRUNCATE CASCADE chain that was wiping grow_cuke_seed_batch
-- every nightly run.
--
-- grow_cuke_seed_batch is a static/forward-planned table with no nightly
-- repopulator. Nightly _clear_transactional.py TRUNCATEs ops_task_tracker
-- and invnt_lot, which CASCADEd through these two FKs and truncated
-- grow_cuke_seed_batch — leaving the plant-map dashboard empty and
-- breaking migration 025's cycle-code -> batch-uuid lookup.
--
-- Both columns stay (they're nullable) but no longer carry FK enforcement.
-- No cuke data populates either column today; the FK was inherited from
-- the pre-split grow_seed_batch schema where lettuce cycles do use them.

alter table public.grow_cuke_seed_batch
  drop constraint if exists grow_cuke_seed_batch_ops_task_tracker_id_fkey;

alter table public.grow_cuke_seed_batch
  drop constraint if exists grow_cuke_seed_batch_invnt_lot_id_fkey;
