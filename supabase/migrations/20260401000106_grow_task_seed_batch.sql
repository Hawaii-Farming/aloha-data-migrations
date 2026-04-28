CREATE TABLE IF NOT EXISTS grow_task_seed_batch (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_id                     TEXT NOT NULL REFERENCES org_farm(id),
    ops_task_tracker_id         UUID NOT NULL REFERENCES ops_task_tracker(id),
    grow_lettuce_seed_batch_id  UUID REFERENCES grow_lettuce_seed_batch(id),
    grow_cuke_seed_batch_id     UUID REFERENCES grow_cuke_seed_batch(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT chk_grow_task_seed_batch_exactly_one CHECK (
        (grow_lettuce_seed_batch_id IS NOT NULL AND grow_cuke_seed_batch_id IS NULL)
        OR
        (grow_lettuce_seed_batch_id IS NULL AND grow_cuke_seed_batch_id IS NOT NULL)
    )
);

COMMENT ON TABLE grow_task_seed_batch IS 'Unified join table linking any grow activity (scouting, spraying, fertigation, monitoring) to the seeding batches involved. Exactly one of grow_lettuce_seed_batch_id / grow_cuke_seed_batch_id is set, determined by the farm. Activity type is derived from ops_task_tracker -> ops_task_id.';

COMMENT ON COLUMN grow_task_seed_batch.grow_lettuce_seed_batch_id IS 'The lettuce seeding batch covered by this activity. Populated when farm_id = Lettuce; null for Cuke';
COMMENT ON COLUMN grow_task_seed_batch.grow_cuke_seed_batch_id IS 'The cuke seeding batch covered by this activity. Populated when farm_id = Cuke; null for Lettuce';

CREATE INDEX idx_grow_task_seed_batch_tracker ON grow_task_seed_batch (ops_task_tracker_id);

-- One link per (tracker, seed batch). Partial indexes so the uniqueness is
-- scoped to whichever crop column is populated on the row.
CREATE UNIQUE INDEX uq_grow_task_seed_batch_lettuce
    ON grow_task_seed_batch (ops_task_tracker_id, grow_lettuce_seed_batch_id)
    WHERE grow_lettuce_seed_batch_id IS NOT NULL;

CREATE UNIQUE INDEX uq_grow_task_seed_batch_cuke
    ON grow_task_seed_batch (ops_task_tracker_id, grow_cuke_seed_batch_id)
    WHERE grow_cuke_seed_batch_id IS NOT NULL;
