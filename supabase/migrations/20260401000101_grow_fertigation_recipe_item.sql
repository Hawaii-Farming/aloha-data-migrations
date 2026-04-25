CREATE TABLE IF NOT EXISTS grow_fertigation_recipe_item (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_name                     TEXT NOT NULL REFERENCES org_farm(name),
    grow_fertigation_recipe_name  TEXT NOT NULL REFERENCES grow_fertigation_recipe(name),
    -- Water-only add-on recipes have no tank; equipment_name is null for those.
    equipment_name                TEXT REFERENCES org_equipment(name),
    invnt_item_name               TEXT REFERENCES invnt_item(name),
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

COMMENT ON TABLE grow_fertigation_recipe_item IS 'Individual fertilizer items within a recipe. invnt_item_name is nullable for products not stored in-house; item_name is always set for display.';

COMMENT ON COLUMN grow_fertigation_recipe_item.item_name IS 'Pre-filled from invnt_item.name when invnt_item_name is set; editable';
COMMENT ON COLUMN grow_fertigation_recipe_item.burn_uom IS 'Pre-filled from grow_spray_compliance.burn_uom when a compliance record exists; editable';
COMMENT ON COLUMN grow_fertigation_recipe_item.application_per_burn IS 'Pre-filled from grow_spray_compliance.application_per_burn when a compliance record exists; editable';

CREATE INDEX idx_grow_fertigation_recipe_item_recipe ON grow_fertigation_recipe_item (grow_fertigation_recipe_name);
