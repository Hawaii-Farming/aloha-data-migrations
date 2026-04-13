CREATE TABLE IF NOT EXISTS grow_harvest_container (
    id              TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL REFERENCES org_farm(id),
    name            TEXT NOT NULL,
    grow_variety_id TEXT REFERENCES grow_variety(id),
    grow_grade_id   TEXT REFERENCES grow_grade(id),
    weight_uom      TEXT NOT NULL REFERENCES sys_uom(code),
    tare_weight     NUMERIC,
    is_tare_calculated  BOOLEAN NOT NULL DEFAULT false,
    tare_formula        TEXT,
    tare_formula_inputs JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_harvest_container UNIQUE (org_id, farm_id, name, grow_variety_id, grow_grade_id)
);

COMMENT ON TABLE grow_harvest_container IS 'Harvest container definitions with tare weight per container type, optionally specific to variety and grade. Used to auto-calculate tare during weigh-ins.';

COMMENT ON COLUMN grow_harvest_container.grow_variety_id IS 'Tare weight can vary by variety; null means any variety';
COMMENT ON COLUMN grow_harvest_container.grow_grade_id IS 'Tare weight can vary by grade; null means any grade';
COMMENT ON COLUMN grow_harvest_container.tare_weight IS 'Fixed tare weight of one empty container; used when is_tare_calculated = false. Multiplied by number_of_containers in grow_harvest_weight';
COMMENT ON COLUMN grow_harvest_container.is_tare_calculated IS 'When true, tare is computed from tare_formula instead of using the fixed tare_weight value';
COMMENT ON COLUMN grow_harvest_container.tare_formula IS 'Text expression evaluated by the app layer to compute tare from gross_weight (e.g. ROUND(0.0316 * gross_weight + -0.835) * 3 + 48). Same pattern as grow_monitoring_metric.formula';
COMMENT ON COLUMN grow_harvest_container.tare_formula_inputs IS 'JSON metadata for the formula inputs, following the grow_monitoring_metric.input_point_ids pattern';
