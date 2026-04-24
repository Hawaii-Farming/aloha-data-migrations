CREATE TABLE IF NOT EXISTS invnt_po (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                 TEXT NOT NULL REFERENCES org(id),
    farm_name                TEXT REFERENCES org_farm(name),

    -- Request classification
    request_type           TEXT NOT NULL DEFAULT 'inventory_item' CHECK (request_type IN ('non_inventory_item', 'inventory_item')),
    urgency_level          TEXT CHECK (urgency_level IN ('today', '2_days', '7_days', 'not_urgent')),

    -- Item identification
    invnt_category_id      TEXT NOT NULL REFERENCES invnt_category(id),
    invnt_item_id          TEXT REFERENCES invnt_item(id),
    item_name              TEXT NOT NULL,

    -- Order quantities & units (snapshots from item at order time)
    burn_uom               TEXT NOT NULL REFERENCES sys_uom(code),
    order_uom              TEXT NOT NULL REFERENCES sys_uom(code),
    order_quantity         NUMERIC NOT NULL,
    burn_per_order         NUMERIC NOT NULL DEFAULT 0,

    -- Vendor & cost
    vendor_po_number       TEXT,
    invnt_vendor_id        TEXT REFERENCES invnt_vendor(id),
    total_cost             NUMERIC,
    is_freight_included    BOOLEAN,
    expected_delivery_date DATE,
    tracking_number        TEXT,

    -- Notes & photos
    notes                  TEXT,
    rejected_reason        TEXT,
    request_photos         JSONB NOT NULL DEFAULT '[]',

    -- Status & audit
    status                 TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'approved', 'rejected', 'ordered', 'partial', 'received', 'cancelled')),
    requested_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    requested_by           TEXT NOT NULL REFERENCES hr_employee(id),
    reviewed_at            TIMESTAMPTZ,
    reviewed_by            TEXT REFERENCES hr_employee(id),
    ordered_at             TIMESTAMPTZ,
    ordered_by             TEXT REFERENCES hr_employee(id),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by             TEXT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by             TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE invnt_po IS 'Tracks purchase order requests through a workflow from request to receipt. Each order snapshots the item name, units, and cost at order time so the record stays accurate even if the item changes later.';

CREATE INDEX idx_invnt_po_org_id ON invnt_po (org_id);
CREATE INDEX idx_invnt_po_status ON invnt_po (org_id, status);
CREATE INDEX idx_invnt_po_item   ON invnt_po (invnt_item_id);

COMMENT ON COLUMN invnt_po.request_type IS 'non_inventory_item, inventory_item';
COMMENT ON COLUMN invnt_po.urgency_level IS 'today, 2_days, 7_days, not_urgent';
COMMENT ON COLUMN invnt_po.invnt_category_id IS 'Pre-filled from invnt_item for inventory_item; user-selected for non_inventory_item';
COMMENT ON COLUMN invnt_po.item_name IS 'Snapshot from invnt_item.name for inventory_item; manually entered for non_inventory_item';
COMMENT ON COLUMN invnt_po.burn_uom IS 'Snapshot from invnt_item.burn_uom for inventory_item; defaults to order_uom for non_inventory_item';
COMMENT ON COLUMN invnt_po.order_uom IS 'Snapshot from invnt_item.order_uom for inventory_item; user-selected for non_inventory_item';
COMMENT ON COLUMN invnt_po.burn_per_order IS 'Snapshot from invnt_item.burn_per_order for inventory_item; defaults to 1 for non_inventory_item';
COMMENT ON COLUMN invnt_po.invnt_vendor_id IS 'Pre-filled from invnt_item.invnt_vendor_id when item is selected; editable';
COMMENT ON COLUMN invnt_po.status IS 'requested, approved, rejected, ordered, partial, received, cancelled';
