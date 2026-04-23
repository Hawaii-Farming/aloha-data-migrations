-- Split grow_harvest_weight.grow_seed_batch_id into two nullable FK columns —
-- one per seed-batch table — because cuke seeding moved out of grow_seed_batch
-- (now grow_lettuce_seed_batch) into the new grow_cuke_seed_batch. A harvest
-- row references exactly one of the two via the CHECK below.

ALTER TABLE grow_harvest_weight
    ADD COLUMN grow_lettuce_seed_batch_id UUID REFERENCES grow_lettuce_seed_batch(id),
    ADD COLUMN grow_cuke_seed_batch_id    UUID REFERENCES grow_cuke_seed_batch(id);

-- Migrate existing FKs: lettuce rows keep their batch id in the lettuce
-- column; cuke rows get their batch id moved into the cuke column. The
-- grow_cuke_seed_batch table is populated by 20260417000001_cuke_plantmap.py
-- using the same UUIDs that currently live on grow_harvest_weight, so the
-- UPDATE below resolves cleanly when run after that script.
UPDATE grow_harvest_weight
SET grow_lettuce_seed_batch_id = grow_seed_batch_id
WHERE farm_id = 'lettuce';

UPDATE grow_harvest_weight
SET grow_cuke_seed_batch_id = grow_seed_batch_id
WHERE farm_id = 'cuke';

-- Drop the legacy FK column.
ALTER TABLE grow_harvest_weight DROP COLUMN grow_seed_batch_id;

-- Enforce exactly one of the two new columns is populated.
ALTER TABLE grow_harvest_weight
    ADD CONSTRAINT chk_grow_harvest_weight_batch_exactly_one
        CHECK (
            (grow_lettuce_seed_batch_id IS NOT NULL AND grow_cuke_seed_batch_id IS NULL)
            OR
            (grow_lettuce_seed_batch_id IS NULL AND grow_cuke_seed_batch_id IS NOT NULL)
        );

COMMENT ON COLUMN grow_harvest_weight.grow_lettuce_seed_batch_id IS 'The lettuce seeding batch being harvested. Populated when farm_id = lettuce; null for cuke';
COMMENT ON COLUMN grow_harvest_weight.grow_cuke_seed_batch_id    IS 'The cuke seeding batch being harvested. Populated when farm_id = cuke; null for lettuce';

DROP INDEX IF EXISTS idx_grow_harvest_weight_seed_batch;
CREATE INDEX idx_grow_harvest_weight_lettuce_batch ON grow_harvest_weight (grow_lettuce_seed_batch_id);
CREATE INDEX idx_grow_harvest_weight_cuke_batch    ON grow_harvest_weight (grow_cuke_seed_batch_id);
