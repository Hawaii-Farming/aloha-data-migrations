CREATE TABLE IF NOT EXISTS grow_harvest_container (
    id       TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL REFERENCES org_farm(id),
    grow_variety_id TEXT REFERENCES grow_variety(id),
    grow_grade_id   TEXT REFERENCES grow_grade(id),
    weight_uom      TEXT NOT NULL REFERENCES sys_uom(id),
    -- Tare is either a fixed weight (is_tare_calculated=false, tare_weight set)
    -- or derived from a formula applied to the gross weight at weigh-in time
    -- (is_tare_calculated=true, tare_formula set). The cuke pallets use the
    -- formula variant so per-container tare tracks gross-weight-dependent
    -- packaging (e.g. ice added proportionally to the fruit mass).
    tare_weight            NUMERIC,
    is_tare_calculated     BOOLEAN NOT NULL DEFAULT false,
    tare_formula           TEXT,
    tare_formula_inputs    JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_harvest_container UNIQUE (org_id, farm_id, id, grow_variety_id, grow_grade_id)
);

COMMENT ON TABLE grow_harvest_container IS 'Harvest container definitions with tare weight per container type, optionally specific to variety and grade. Used to auto-calculate tare during weigh-ins.';

COMMENT ON COLUMN grow_harvest_container.grow_variety_id IS 'Tare weight can vary by variety; null means any variety';
COMMENT ON COLUMN grow_harvest_container.grow_grade_id IS 'Tare weight can vary by grade; null means any grade';
COMMENT ON COLUMN grow_harvest_container.tare_weight IS 'Fixed weight of one empty container; multiplied by number_of_containers in grow_harvest_weight. Null when is_tare_calculated is true.';
COMMENT ON COLUMN grow_harvest_container.is_tare_calculated IS 'When true, tare is computed per weigh-in via tare_formula; when false the static tare_weight applies.';
COMMENT ON COLUMN grow_harvest_container.tare_formula IS 'SQL-style formula evaluated against the gross_weight at weigh-in (e.g. "ROUND(0.031 * gross_weight - 0.83) * 3 + 48")';
COMMENT ON COLUMN grow_harvest_container.tare_formula_inputs IS 'Optional JSONB metadata for extra formula inputs (e.g. variety-specific coefficients)';

