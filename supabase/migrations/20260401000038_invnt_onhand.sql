CREATE TABLE IF NOT EXISTS invnt_onhand (
    org_id                 TEXT NOT NULL REFERENCES org(id),
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                TEXT REFERENCES org_farm(name),
    invnt_item_name          TEXT NOT NULL REFERENCES invnt_item(name),
    onhand_date            DATE NOT NULL,
    burn_uom               TEXT REFERENCES sys_uom(code),
    onhand_uom             TEXT REFERENCES sys_uom(code),
    onhand_quantity        NUMERIC NOT NULL,
    burn_per_onhand   NUMERIC NOT NULL DEFAULT 0,

    -- Lot tracking
    invnt_lot_id           TEXT REFERENCES invnt_lot(id),

    notes                  TEXT,

    -- Status & audit
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by             TEXT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by             TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE invnt_onhand IS 'Records on-hand inventory snapshots per item. References invnt_lot for lot tracking. Source of truth for computed totals like current stock, burn-per-week, and weeks-on-hand.';

COMMENT ON COLUMN invnt_onhand.farm_name IS 'Inherited from invnt_item.farm_name when on-hand record is created';
COMMENT ON COLUMN invnt_onhand.burn_uom IS 'Pre-filled from invnt_item.burn_uom; read-only snapshot';
COMMENT ON COLUMN invnt_onhand.onhand_uom IS 'Pre-filled from invnt_item.onhand_uom; editable';
COMMENT ON COLUMN invnt_onhand.burn_per_onhand IS 'Snapshot from invnt_item.burn_per_onhand at record creation time';

CREATE INDEX idx_invnt_onhand_org_id ON invnt_onhand (org_id);
CREATE INDEX idx_invnt_onhand_item ON invnt_onhand (invnt_item_name, onhand_date);

