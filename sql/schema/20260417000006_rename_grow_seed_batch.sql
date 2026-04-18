-- Rename grow_seed_batch -> grow_lettuce_seed_batch.
-- Cuke rows are being moved out to grow_cuke_seed_batch; after this rename,
-- the table holds lettuce rows only. Related indexes and constraints are
-- renamed to keep the idx_<table>_ and uq_<table>_ naming consistent.

ALTER TABLE grow_seed_batch RENAME TO grow_lettuce_seed_batch;

ALTER INDEX idx_grow_seed_batch_org          RENAME TO idx_grow_lettuce_seed_batch_org;
ALTER INDEX idx_grow_seed_batch_tracker      RENAME TO idx_grow_lettuce_seed_batch_tracker;
ALTER INDEX idx_grow_seed_batch_item         RENAME TO idx_grow_lettuce_seed_batch_item;
ALTER INDEX idx_grow_seed_batch_mix          RENAME TO idx_grow_lettuce_seed_batch_mix;

ALTER TABLE grow_lettuce_seed_batch RENAME CONSTRAINT uq_grow_seed_batch TO uq_grow_lettuce_seed_batch;
ALTER TABLE grow_lettuce_seed_batch RENAME CONSTRAINT chk_grow_seed_batch_source TO chk_grow_lettuce_seed_batch_source;

COMMENT ON TABLE grow_lettuce_seed_batch IS 'Lettuce seeding batch linked to an ops activity. Either a single seed item or a seed mix, never both. Cuke seeding moved to grow_cuke_seed_batch.';
