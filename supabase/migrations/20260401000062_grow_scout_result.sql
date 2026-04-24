CREATE TABLE IF NOT EXISTS grow_scout_result (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT NOT NULL REFERENCES org_farm(name),
    ops_task_tracker_id        UUID NOT NULL REFERENCES ops_task_tracker(id),
    site_id                 TEXT REFERENCES org_site(id),
    observation_type        TEXT NOT NULL CHECK (observation_type IN ('pest', 'disease')),
    grow_pest_id            TEXT REFERENCES grow_pest(name),
    grow_disease_id         TEXT REFERENCES grow_disease(name),
    disease_infection_stage TEXT CHECK (disease_infection_stage IN ('early', 'mid', 'late', 'advanced')),
    severity_level          TEXT NOT NULL CHECK (severity_level IN ('low', 'moderate', 'high', 'severe')),
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT chk_grow_scout_result_type CHECK (
        (observation_type = 'pest' AND grow_pest_id IS NOT NULL AND grow_disease_id IS NULL)
        OR (observation_type = 'disease' AND grow_disease_id IS NOT NULL AND grow_pest_id IS NULL)
    )
);

COMMENT ON TABLE grow_scout_result IS 'Individual pest or disease finding within a scouting event. Either a pest or disease, enforced by CHECK constraint.';

COMMENT ON COLUMN grow_scout_result.site_id IS 'The specific growing row (org_site where category = row); one observation per row per pest/disease';
COMMENT ON COLUMN grow_scout_result.observation_type IS 'pest, disease';
COMMENT ON COLUMN grow_scout_result.grow_pest_id IS 'Shown when observation_type is pest; null when disease';
COMMENT ON COLUMN grow_scout_result.grow_disease_id IS 'Shown when observation_type is disease; null when pest';
COMMENT ON COLUMN grow_scout_result.disease_infection_stage IS 'early, mid, late, advanced; shown when observation_type is disease; null when pest';
COMMENT ON COLUMN grow_scout_result.severity_level IS 'low, moderate, high, severe';

CREATE INDEX idx_grow_scout_result_scouting ON grow_scout_result (ops_task_tracker_id);
