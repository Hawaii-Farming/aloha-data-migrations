CREATE TABLE IF NOT EXISTS pack_shelf_life_result (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_id                     TEXT REFERENCES org_farm(name),
    pack_shelf_life_id    UUID NOT NULL REFERENCES pack_shelf_life(id),
    pack_shelf_life_metric_id    TEXT NOT NULL REFERENCES pack_shelf_life_metric(name),

    observation_date            DATE NOT NULL,
    shelf_life_day              INTEGER NOT NULL,

    response_boolean            BOOLEAN,
    response_numeric            NUMERIC,
    response_enum               TEXT,
    response_text               TEXT,

    notes                       TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                   BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_pack_shelf_life_result UNIQUE (pack_shelf_life_id, pack_shelf_life_metric_id, observation_date)
);

COMMENT ON TABLE pack_shelf_life_result IS 'Individual observation responses for a shelf life trial. One row per check per observation date per trial.';

COMMENT ON COLUMN pack_shelf_life_result.response_boolean IS 'Used when pack_shelf_life_metric.response_type is boolean';
COMMENT ON COLUMN pack_shelf_life_result.response_numeric IS 'Used when pack_shelf_life_metric.response_type is numeric';
COMMENT ON COLUMN pack_shelf_life_result.response_enum IS 'Used when pack_shelf_life_metric.response_type is enum; value from metric enum_options';
COMMENT ON COLUMN pack_shelf_life_result.shelf_life_day IS 'Auto-calculated: observation_date minus pack_lot.pack_date';

CREATE INDEX idx_pack_shelf_life_result_org_id ON pack_shelf_life_result (org_id);
CREATE INDEX idx_pack_shelf_life_result_trial  ON pack_shelf_life_result (pack_shelf_life_id);
CREATE INDEX idx_pack_shelf_life_result_check  ON pack_shelf_life_result (pack_shelf_life_metric_id);
