CREATE TABLE IF NOT EXISTS invnt_item (
    org_id                   TEXT NOT NULL REFERENCES org(id),
    id                       TEXT PRIMARY KEY,
    farm_name                  TEXT REFERENCES org_farm(name),
    invnt_category_id        TEXT REFERENCES invnt_category(id),
    invnt_subcategory_id     TEXT REFERENCES invnt_category(id),
    name                     TEXT NOT NULL,
    qb_account            TEXT,
    description              TEXT,

    -- Three-unit system
    burn_uom                 TEXT REFERENCES sys_uom(code),
    onhand_uom               TEXT REFERENCES sys_uom(code),
    order_uom                TEXT REFERENCES sys_uom(code),
    burn_per_onhand     NUMERIC NOT NULL DEFAULT 0,
    burn_per_order      NUMERIC NOT NULL DEFAULT 0,

    -- Logistics
    is_palletized            BOOLEAN NOT NULL DEFAULT false,
    order_per_pallet    NUMERIC NOT NULL DEFAULT 0,
    pallet_per_truckload NUMERIC NOT NULL DEFAULT 0,

    -- Burn rates & forecasting
    is_frequently_used       BOOLEAN NOT NULL DEFAULT false,
    burn_per_week            NUMERIC NOT NULL DEFAULT 0,
    cushion_weeks            NUMERIC NOT NULL DEFAULT 0,

    -- Reorder settings
    is_auto_reorder          BOOLEAN NOT NULL DEFAULT false,
    reorder_point_in_burn       NUMERIC NOT NULL DEFAULT 0,
    reorder_quantity_in_burn    NUMERIC NOT NULL DEFAULT 0,

    -- Tracking flags
    requires_lot_tracking    BOOLEAN NOT NULL DEFAULT false,
    requires_expiry_date     BOOLEAN NOT NULL DEFAULT false,

    -- Site references
    site_id              TEXT REFERENCES org_site(id),
    equipment_id   TEXT REFERENCES org_equipment(id),

    -- Item details
    invnt_vendor_id          TEXT REFERENCES invnt_vendor(id),
    manufacturer             TEXT,
    grow_variety_id          TEXT REFERENCES grow_variety(code),
    seed_is_pelleted         BOOLEAN,
    maint_part_type          TEXT,
    maint_part_number        TEXT,

    photos                   JSONB NOT NULL DEFAULT '[]',

    is_active                BOOLEAN NOT NULL DEFAULT true,

    -- CRUD
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by               TEXT,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by               TEXT,
    is_deleted                BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_invnt_item UNIQUE (org_id, name)
);

COMMENT ON TABLE invnt_item IS 'The main inventory record. Items belong to an organization and optionally to a specific farm. Classification is handled by the category/subcategory structure. All item details are proper columns grouped by logical sections. Seed-specific fields are prefixed seed_; maintenance part fields are prefixed maint_.';

CREATE INDEX idx_invnt_item_org_id ON invnt_item (org_id);
CREATE INDEX idx_invnt_item_vendor      ON invnt_item (invnt_vendor_id);
CREATE INDEX idx_invnt_item_category    ON invnt_item (invnt_category_id);
CREATE INDEX idx_invnt_item_subcategory ON invnt_item (invnt_subcategory_id);
CREATE INDEX idx_invnt_item_site ON invnt_item (site_id);
CREATE INDEX idx_invnt_item_equipment ON invnt_item (equipment_id);

COMMENT ON COLUMN invnt_item.invnt_category_id IS 'References invnt_category rows where sub_category_name IS NULL';
COMMENT ON COLUMN invnt_item.invnt_subcategory_id IS 'References invnt_category rows where sub_category_name IS NOT NULL';
COMMENT ON COLUMN invnt_item.burn_uom IS 'Smallest consumption unit used for burn rate tracking (e.g. ml, g, seed)';
COMMENT ON COLUMN invnt_item.cushion_weeks IS 'Safety stock buffer in weeks used in next-order-date calculations';
COMMENT ON COLUMN invnt_item.seed_is_pelleted IS 'Whether seed item is pelleted; null for non-seed items';
COMMENT ON COLUMN invnt_item.maint_part_type IS 'Type classification for parts (e.g. electrical, mechanical, plumbing)';
COMMENT ON COLUMN invnt_item.site_id IS 'Filtered to org_site where category = storage; the storage location for this item';
COMMENT ON COLUMN invnt_item.photos IS 'Reference photos of the item used for visual identification during ordering';
COMMENT ON COLUMN invnt_item.is_active IS 'Whether this item is currently active for ordering and tracking; false means inactive but not deleted';
COMMENT ON COLUMN invnt_item.reorder_point_in_burn IS 'Auto-calculated: burn_per_week * cushion_weeks; triggers reorder alert when on-hand falls below this';
COMMENT ON COLUMN invnt_item.reorder_quantity_in_burn IS 'Auto-calculated: burn_per_week * cushion_weeks; default quantity for auto-reorder in burn units';
