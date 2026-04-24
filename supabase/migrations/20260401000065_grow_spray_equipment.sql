CREATE TABLE IF NOT EXISTS grow_spray_equipment (
    org_id              TEXT NOT NULL REFERENCES org(id),
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    ops_task_tracker_id    UUID NOT NULL REFERENCES ops_task_tracker(id),
    equipment_name        TEXT NOT NULL REFERENCES org_equipment(name),
    water_uom           TEXT NOT NULL REFERENCES sys_uom(code),
    water_quantity      NUMERIC NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_spray_equipment UNIQUE (ops_task_tracker_id, equipment_name)
);

COMMENT ON TABLE grow_spray_equipment IS 'Equipment used during a spraying event with the water quantity per piece of equipment.';

COMMENT ON COLUMN grow_spray_equipment.equipment_name IS 'Filtered to org_equipment where type IN (fogger, bag_pack_sprayer)';


CREATE INDEX idx_grow_spray_equipment_spraying ON grow_spray_equipment (ops_task_tracker_id);
CREATE INDEX idx_grow_spray_equipment_equip ON grow_spray_equipment (equipment_name);
