CREATE TABLE IF NOT EXISTS pack_shelf_life_metric (
    id       TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT,
    description     TEXT,

    -- Response configuration
    response_type   TEXT NOT NULL CHECK (response_type IN ('Boolean', 'Numeric', 'Enum')),
    enum_options    JSONB,

    -- Fail criteria (triggers trial termination when matched)
    fail_boolean        BOOLEAN,
    fail_enum_values    JSONB,
    fail_minimum_value        NUMERIC,
    fail_maximum_value        NUMERIC,

    display_order   INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT pack_shelf_life_metric_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE pack_shelf_life_metric IS 'Defines what gets checked during a shelf life observation (e.g. color, texture, moisture). Each metric specifies a response type and optional fail criteria that trigger trial termination.';

CREATE INDEX idx_pack_shelf_life_metric_org_id ON pack_shelf_life_metric (org_id);

-- Partial unique indexes handle NULL farm_id correctly
CREATE UNIQUE INDEX uq_pack_shelf_life_metric_org_level  ON pack_shelf_life_metric (org_id, id) WHERE farm_id IS NULL;
CREATE UNIQUE INDEX uq_pack_shelf_life_metric_farm_level ON pack_shelf_life_metric (org_id, farm_id, id) WHERE farm_id IS NOT NULL;

COMMENT ON COLUMN pack_shelf_life_metric.response_type IS 'boolean, numeric, enum';
COMMENT ON COLUMN pack_shelf_life_metric.enum_options IS 'JSON array of allowed observation values when response_type is enum (e.g. ["Green", "Yellow", "Brown"])';
COMMENT ON COLUMN pack_shelf_life_metric.fail_boolean IS 'Boolean value that triggers trial termination when matched; null if response_type is not boolean';
COMMENT ON COLUMN pack_shelf_life_metric.fail_enum_values IS 'JSON array of enum values that trigger trial termination; null if response_type is not enum';
COMMENT ON COLUMN pack_shelf_life_metric.fail_minimum_value IS 'Reading below this value triggers termination; use alone, with max for a range, or null if not numeric';
COMMENT ON COLUMN pack_shelf_life_metric.fail_maximum_value IS 'Reading above this value triggers termination; use alone, with min for a range, or null if not numeric';
