CREATE TABLE IF NOT EXISTS invnt_lot (
    org_id                      TEXT NOT NULL REFERENCES org(id),
    id                          TEXT PRIMARY KEY,
    farm_name                     TEXT NOT NULL REFERENCES org_farm(name),
    invnt_item_id               TEXT NOT NULL REFERENCES invnt_item(id),
    lot_number                  TEXT NOT NULL,
    lot_expiry_date             DATE,
    is_active                   BOOLEAN NOT NULL DEFAULT true,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_invnt_lot UNIQUE (org_id, invnt_item_id, lot_number)
);

COMMENT ON TABLE invnt_lot IS 'Tracks unique inventory lots by item and lot number. The id (PK) includes the item to ensure global uniqueness since different items can share the same lot number. The constraint on (org_id, invnt_item_id, lot_number) prevents duplicate lots per item.';

COMMENT ON COLUMN invnt_lot.farm_name IS 'Inherited from invnt_item.farm_name when lot is created';
COMMENT ON COLUMN invnt_lot.is_active IS 'Auto-set to false when latest invnt_onhand quantity is zero; can also be manually set to false by user';
