CREATE TABLE IF NOT EXISTS fsafe_pest_result (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_name                 TEXT NOT NULL REFERENCES org_farm(name),
    ops_task_tracker_id     UUID NOT NULL REFERENCES ops_task_tracker(id),
    site_id                 TEXT NOT NULL REFERENCES org_site(id),
    pest_type               TEXT CHECK (pest_type IN ('mouse', 'rat')),
    photo_url               TEXT,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE fsafe_pest_result IS 'Per-station pest trap inspection result. One row per trap station per inspection event. The ops_task_tracker acts as the inspection header with date, farm, and verification.';

COMMENT ON COLUMN fsafe_pest_result.site_id IS 'The specific trap station (org_site where category = pest_trap); distinct from ops_task_tracker.site_id which is the parent building';
COMMENT ON COLUMN fsafe_pest_result.pest_type IS 'mouse, rat; null means no activity at this station';

CREATE INDEX idx_fsafe_pest_result_tracker ON fsafe_pest_result (ops_task_tracker_id);
CREATE INDEX idx_fsafe_pest_result_site ON fsafe_pest_result (site_id);
