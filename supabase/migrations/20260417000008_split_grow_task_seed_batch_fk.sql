-- Same FK-split as 20260417000007 applied to grow_task_seed_batch.
-- The table links any grow activity (scouting, spraying, fertigation,
-- monitoring) to the seed batch it covers. Cuke links move to a new column
-- that FKs to grow_cuke_seed_batch; lettuce links stay on a renamed column.

ALTER TABLE grow_task_seed_batch
    ADD COLUMN grow_lettuce_seed_batch_id UUID REFERENCES grow_lettuce_seed_batch(id),
    ADD COLUMN grow_cuke_seed_batch_id    UUID REFERENCES grow_cuke_seed_batch(id);

-- Migrate existing FKs. Must run after 20260417000001_cuke_plantmap.py has
-- populated grow_cuke_seed_batch with the same UUIDs that currently live on
-- grow_task_seed_batch.
UPDATE grow_task_seed_batch
SET grow_lettuce_seed_batch_id = grow_seed_batch_id
WHERE farm_id = 'lettuce';

UPDATE grow_task_seed_batch
SET grow_cuke_seed_batch_id = grow_seed_batch_id
WHERE farm_id = 'cuke';

-- Drop the legacy column and rebuild the unique constraint against the new columns.
ALTER TABLE grow_task_seed_batch DROP CONSTRAINT IF EXISTS grow_task_seed_batch_ops_task_tracker_id_grow_seed_batch_i_key;
ALTER TABLE grow_task_seed_batch DROP COLUMN grow_seed_batch_id;

ALTER TABLE grow_task_seed_batch
    ADD CONSTRAINT chk_grow_task_seed_batch_exactly_one
        CHECK (
            (grow_lettuce_seed_batch_id IS NOT NULL AND grow_cuke_seed_batch_id IS NULL)
            OR
            (grow_lettuce_seed_batch_id IS NULL AND grow_cuke_seed_batch_id IS NOT NULL)
        );

CREATE UNIQUE INDEX uq_grow_task_seed_batch_lettuce
    ON grow_task_seed_batch (ops_task_tracker_id, grow_lettuce_seed_batch_id)
    WHERE grow_lettuce_seed_batch_id IS NOT NULL;

CREATE UNIQUE INDEX uq_grow_task_seed_batch_cuke
    ON grow_task_seed_batch (ops_task_tracker_id, grow_cuke_seed_batch_id)
    WHERE grow_cuke_seed_batch_id IS NOT NULL;

COMMENT ON COLUMN grow_task_seed_batch.grow_lettuce_seed_batch_id IS 'The lettuce seeding batch covered by this activity. Populated when farm_id = lettuce; null for cuke';
COMMENT ON COLUMN grow_task_seed_batch.grow_cuke_seed_batch_id    IS 'The cuke seeding batch covered by this activity. Populated when farm_id = cuke; null for lettuce';
