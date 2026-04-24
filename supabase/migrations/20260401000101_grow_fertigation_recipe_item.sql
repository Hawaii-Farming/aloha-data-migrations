CREATE TABLE IF NOT EXISTS grow_fertigation_recipe_item (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_id                     TEXT NOT NULL REFERENCES org_farm(id),
    grow_fertigation_recipe_id  TEXT NOT NULL REFERENCES grow_fertigation_recipe(id),
    -- Water-only add-on recipes have no tank; equipment_id is null for those.
    equipment_id                TEXT REFERENCES org_equipment(id),
    invnt_item_id               TEXT REFERENCES invnt_item(id),
    item_name                   TEXT NOT NULL,
    application_uom             TEXT NOT NULL REFERENCES sys_uom(code),
    application_quantity                    NUMERIC NOT NULL,
    burn_uom                    TEXT REFERENCES sys_uom(code),
    application_per_burn   NUMERIC,
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_fertigation_recipe_item IS 'Individual fertilizer items within a recipe. invnt_item_id is nullable for products not stored in-house; item_name is always set for display.';

COMMENT ON COLUMN grow_fertigation_recipe_item.item_name IS 'Pre-filled from invnt_item.name when invnt_item_id is set; editable';
COMMENT ON COLUMN grow_fertigation_recipe_item.burn_uom IS 'Pre-filled from grow_spray_compliance.burn_uom when a compliance record exists; editable';
COMMENT ON COLUMN grow_fertigation_recipe_item.application_per_burn IS 'Pre-filled from grow_spray_compliance.application_per_burn when a compliance record exists; editable';

CREATE INDEX idx_grow_fertigation_recipe_item_recipe ON grow_fertigation_recipe_item (grow_fertigation_recipe_id);
