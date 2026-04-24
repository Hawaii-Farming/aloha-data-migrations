CREATE TABLE IF NOT EXISTS grow_fertigation (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    ops_task_tracker_id         UUID NOT NULL REFERENCES ops_task_tracker(id),
    grow_fertigation_recipe_id  TEXT NOT NULL REFERENCES grow_fertigation_recipe(id),
    equipment_id                TEXT NOT NULL REFERENCES org_equipment(id),
    volume_uom          TEXT NOT NULL REFERENCES sys_uom(code),
    volume_applied      NUMERIC NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_fertigation UNIQUE (ops_task_tracker_id, equipment_id)
);

COMMENT ON TABLE grow_fertigation IS 'Tanks used during a fertigation event with the volume applied per tank.';

COMMENT ON COLUMN grow_fertigation.grow_fertigation_recipe_id IS 'Pre-filled from grow_fertigation_recipe_site based on selected sites; editable';
COMMENT ON COLUMN grow_fertigation.equipment_id IS 'Filtered to org_equipment where type = tank; pre-filled from grow_fertigation_recipe_item.equipment_id; editable';

CREATE INDEX idx_grow_fertigation_tracker ON grow_fertigation (ops_task_tracker_id);
