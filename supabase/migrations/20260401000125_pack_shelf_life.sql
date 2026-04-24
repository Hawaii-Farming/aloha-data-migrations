CREATE TABLE IF NOT EXISTS pack_shelf_life (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_name                     TEXT REFERENCES org_farm(name),
    pack_lot_id                 UUID REFERENCES pack_lot(id),
    sales_product_id            TEXT REFERENCES sales_product(code),
    invnt_item_id               TEXT REFERENCES invnt_item(id),

    trial_number                INTEGER,
    trial_purpose               TEXT,
    target_shelf_life_days      INTEGER,
    site_id                     TEXT REFERENCES org_site(id),
    notes                       TEXT,

    is_terminated               BOOLEAN NOT NULL DEFAULT false,
    termination_reason          TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                   BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pack_shelf_life IS 'Shelf life trial header. One row per trial. Tracks the product, lot, packaging type, target shelf life, and trial outcome.';

COMMENT ON COLUMN pack_shelf_life.target_shelf_life_days IS 'Pre-filled from sales_product.shelf_life_days; editable';
COMMENT ON COLUMN pack_shelf_life.site_id IS 'Filtered to org_site where category = storage; the storage location for this trial';
COMMENT ON COLUMN pack_shelf_life.invnt_item_id IS 'Pre-filled from sales_product.invnt_item_id; filtered to packaging items in inventory';

CREATE INDEX idx_pack_shelf_life_org_id   ON pack_shelf_life (org_id);
CREATE INDEX idx_pack_shelf_life_lot      ON pack_shelf_life (pack_lot_id);
CREATE INDEX idx_pack_shelf_life_product  ON pack_shelf_life (sales_product_id);

