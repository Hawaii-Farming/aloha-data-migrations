CREATE TABLE IF NOT EXISTS grow_task_photo (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL REFERENCES org_farm(id),
    ops_task_tracker_id UUID NOT NULL REFERENCES ops_task_tracker(id),
    photo_url           TEXT NOT NULL,
    caption             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_task_photo IS 'Unified photo table for any grow activity (scouting, monitoring, etc.). One row per photo with optional caption. Activity type is derived from ops_task_tracker → ops_task_id.';

CREATE INDEX idx_grow_task_photo_tracker ON grow_task_photo (ops_task_tracker_id);
