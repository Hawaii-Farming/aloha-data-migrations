CREATE TABLE IF NOT EXISTS invnt_po_received (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                 TEXT NOT NULL REFERENCES org(id),
    farm_id                TEXT REFERENCES org_farm(id),
    invnt_po_id            UUID NOT NULL REFERENCES invnt_po(id),
    received_date          DATE NOT NULL,
    received_uom           TEXT NOT NULL REFERENCES sys_uom(id),
    received_quantity      NUMERIC NOT NULL,
    burn_per_received      NUMERIC NOT NULL DEFAULT 0,

    -- Lot tracking
    invnt_lot_id           TEXT REFERENCES invnt_lot(id),

    -- Delivery acceptance
    fsafe_delivery_truck_clean   BOOLEAN,
    fsafe_delivery_acceptable    BOOLEAN,
    notes                  TEXT,
    received_photos        JSONB NOT NULL DEFAULT '[]',

    received_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    received_by            TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by             TEXT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by             TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE invnt_po_received IS 'Individual deliveries received against a purchase order. One order can have multiple received records to handle partial deliveries. References invnt_lot for lot tracking.';

COMMENT ON COLUMN invnt_po_received.farm_id IS 'Inherited from invnt_po.farm_id when receiving against a PO';
COMMENT ON COLUMN invnt_po_received.received_uom IS 'Pre-filled from invnt_po.order_uom; editable at receive time';
COMMENT ON COLUMN invnt_po_received.burn_per_received IS 'Snapshot from invnt_po.burn_per_order at receive time';
COMMENT ON COLUMN invnt_po_received.received_photos IS 'Photos taken at delivery for audit and quality verification';

CREATE INDEX idx_invnt_po_received_po  ON invnt_po_received (invnt_po_id);
CREATE INDEX idx_invnt_po_received_org ON invnt_po_received (org_id);

