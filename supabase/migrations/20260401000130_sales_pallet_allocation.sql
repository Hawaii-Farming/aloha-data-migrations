-- sales_pallet_allocation
-- =======================
-- Line items on a pallet. One row per (pallet, fulfillment) pair, with
-- the quantity slice of the fulfillment that physically rides on the
-- pallet. A single sales_po_fulfillment row may split across multiple
-- pallets (e.g. Costco KW 84-case smart-split into 60 + 24 on two
-- pallets) and a single Shareable pallet may carry slices from multiple
-- fulfillment rows for the same customer.
--
-- The link chain is:
--   sales_po_line -> sales_po_fulfillment -> sales_pallet_allocation
--                                                 -> sales_pallet
--                                                    -> sales_shipment_container
--                                                       -> sales_shipment
--
-- ON DELETE CASCADE on sales_pallet_id so wiping a pallet during a
-- regeneration cleans up its allocations atomically.

CREATE TABLE IF NOT EXISTS sales_pallet_allocation (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_pallet_id             UUID NOT NULL REFERENCES sales_pallet(id) ON DELETE CASCADE,
    sales_po_fulfillment_id     UUID NOT NULL REFERENCES sales_po_fulfillment(id),

    allocated_quantity          NUMERIC NOT NULL CHECK (allocated_quantity > 0),

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE sales_pallet_allocation IS 'Line items on a pallet. Each row = a slice of a sales_po_fulfillment rolling onto a sales_pallet, with allocated_quantity carrying that slice''s case count. A fulfillment may split across multiple pallets and a Shareable pallet may carry multiple fulfillments.';

CREATE INDEX idx_sales_pallet_allocation_org         ON sales_pallet_allocation (org_id);
CREATE INDEX idx_sales_pallet_allocation_pallet      ON sales_pallet_allocation (sales_pallet_id);
CREATE INDEX idx_sales_pallet_allocation_fulfillment ON sales_pallet_allocation (sales_po_fulfillment_id);

COMMENT ON COLUMN sales_pallet_allocation.allocated_quantity IS 'Number of cases from the source fulfillment that ride on this pallet. Sum of all allocations for one fulfillment must equal sales_po_fulfillment.fulfilled_quantity (enforced by the app, not the DB, because partial allocations are valid mid-workflow).';
