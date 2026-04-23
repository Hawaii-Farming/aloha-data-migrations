CREATE TABLE IF NOT EXISTS grow_task_seed_batch (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_id                     TEXT NOT NULL REFERENCES org_farm(id),
    ops_task_tracker_id         UUID NOT NULL REFERENCES ops_task_tracker(id),
    grow_seed_batch_id          UUID NOT NULL REFERENCES grow_seed_batch(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_task_seed_batch UNIQUE (ops_task_tracker_id, grow_seed_batch_id)
);

COMMENT ON TABLE grow_task_seed_batch IS 'Unified join table linking any grow activity (scouting, spraying, fertigation, monitoring) to the seeding batches involved. Activity type is derived from ops_task_tracker → ops_task_id.';

CREATE INDEX idx_grow_task_seed_batch_tracker ON grow_task_seed_batch (ops_task_tracker_id);
CREATE INDEX idx_grow_task_seed_batch_seed ON grow_task_seed_batch (grow_seed_batch_id);
