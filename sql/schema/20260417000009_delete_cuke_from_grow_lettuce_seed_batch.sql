-- After the FK splits in 20260417000007 and 20260417000008 drop the legacy
-- grow_seed_batch_id columns, the 660 cuke rows in grow_lettuce_seed_batch
-- have no inbound FK references. Remove them so grow_lettuce_seed_batch is
-- truly lettuce-only. Must run AFTER 20260417000001_cuke_plantmap.py has
-- copied those rows into grow_cuke_seed_batch.

DELETE FROM grow_lettuce_seed_batch WHERE farm_id = 'cuke';
