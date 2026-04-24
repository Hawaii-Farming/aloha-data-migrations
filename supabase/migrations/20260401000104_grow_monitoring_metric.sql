CREATE TABLE IF NOT EXISTS grow_monitoring_metric (
    org_id          TEXT NOT NULL REFERENCES org(id),
    id              TEXT PRIMARY KEY,
    farm_name         TEXT NOT NULL REFERENCES org_farm(name),
    site_category   TEXT NOT NULL,
    name            TEXT NOT NULL,
    description     TEXT,

    -- Response configuration
    response_type       TEXT NOT NULL DEFAULT 'numeric' CHECK (response_type IN ('boolean', 'numeric', 'enum')),
    reading_uom         TEXT REFERENCES sys_uom(code),
    minimum_value       NUMERIC,
    maximum_value       NUMERIC,
    enum_options        JSONB,
    enum_pass_options   JSONB,

    -- Calculation
    is_calculated       BOOLEAN NOT NULL DEFAULT false,
    formula             TEXT,
    input_point_ids     JSONB,

    is_required         BOOLEAN NOT NULL DEFAULT true,

    -- Corrective Actions
    corrective_actions  JSONB NOT NULL DEFAULT '[]',

    display_order   INTEGER NOT NULL DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_monitoring_metric UNIQUE (org_id, farm_name, site_category, name)
);

COMMENT ON TABLE grow_monitoring_metric IS 'Defines what to measure per farm and site category. Direct points are entered manually; calculated points are derived from other points using a formula.';

COMMENT ON COLUMN grow_monitoring_metric.site_category IS 'Matches org_site.category to scope which metrics apply (e.g. greenhouse, nursery, pond)';
COMMENT ON COLUMN grow_monitoring_metric.response_type IS 'boolean, numeric, enum';
COMMENT ON COLUMN grow_monitoring_metric.minimum_value IS 'Reading below this value auto-sets grow_monitoring_result.is_out_of_range to true; null if not numeric';
COMMENT ON COLUMN grow_monitoring_metric.maximum_value IS 'Reading above this value auto-sets grow_monitoring_result.is_out_of_range to true; null if not numeric';
COMMENT ON COLUMN grow_monitoring_metric.enum_options IS 'JSON array of allowed values when response_type is enum; null if not enum';
COMMENT ON COLUMN grow_monitoring_metric.enum_pass_options IS 'Subset of enum_options that are acceptable; values outside this set auto-set is_out_of_range to true';
COMMENT ON COLUMN grow_monitoring_metric.formula IS 'Expression for calculated points (e.g. (drain_ml / (drip_ml * drippers)) * 100); null when is_calculated = false';
COMMENT ON COLUMN grow_monitoring_metric.input_point_ids IS 'JSON array of grow_monitoring_metric IDs that feed into this calculation; null when is_calculated = false';
COMMENT ON COLUMN grow_monitoring_metric.is_required IS 'When true, an out-of-range reading triggers corrective action creation; when false, the metric is informational only';
COMMENT ON COLUMN grow_monitoring_metric.corrective_actions IS 'JSON array of corrective action options shown when reading is out of range; selected value stored in grow_monitoring_result.corrective_action';

CREATE INDEX idx_grow_monitoring_metric_farm ON grow_monitoring_metric (org_id, farm_name, site_category);
