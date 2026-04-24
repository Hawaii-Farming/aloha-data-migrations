CREATE TABLE IF NOT EXISTS grow_spray_input (
    org_id                      TEXT NOT NULL REFERENCES org(id),
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                     TEXT NOT NULL REFERENCES org_farm(name),
    ops_task_tracker_id            UUID NOT NULL REFERENCES ops_task_tracker(id),
    grow_spray_compliance_id    UUID NOT NULL REFERENCES grow_spray_compliance(id),
    invnt_item_id               TEXT NOT NULL REFERENCES invnt_item(id),
    invnt_lot_id                TEXT REFERENCES invnt_lot(id),
    target_pest_disease         JSONB NOT NULL DEFAULT '[]',
    application_uom             TEXT NOT NULL REFERENCES sys_uom(code),
    application_quantity        NUMERIC NOT NULL,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_spray_input IS 'Individual chemical or fertilizer applied during a spraying event. One row per input product. The compliance record is the source of truth — only compliant products can be sprayed, and the app enforces label rate limits via maximum_quantity_per_acre.';

COMMENT ON COLUMN grow_spray_input.invnt_item_id IS 'Pre-filled from grow_spray_compliance.invnt_item_id';
COMMENT ON COLUMN grow_spray_input.target_pest_disease IS 'Pre-filled from grow_spray_compliance.target_pest_disease; editable';
COMMENT ON COLUMN grow_spray_input.application_uom IS 'Pre-filled from grow_spray_compliance.application_uom; editable';
COMMENT ON COLUMN grow_spray_input.invnt_lot_id IS 'Sourced from invnt_lot filtered by the selected invnt_item_id';

CREATE INDEX idx_grow_spray_input_spraying ON grow_spray_input (ops_task_tracker_id);
CREATE INDEX idx_grow_spray_input_compliance ON grow_spray_input (grow_spray_compliance_id);
