CREATE TABLE IF NOT EXISTS grow_harvest_container (
    id              TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL REFERENCES org_farm(id),
    name            TEXT NOT NULL,
    grow_variety_id TEXT REFERENCES grow_variety(id),
    grow_grade_id   TEXT REFERENCES grow_grade(id),
    weight_uom      TEXT NOT NULL REFERENCES sys_uom(code),
    tare_weight     NUMERIC NOT NULL,
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
COMMENT ON COLUMN grow_harvest_container.tare_weight IS 'Weight of one empty container; multiplied by number_of_containers in grow_harvest_weight';

