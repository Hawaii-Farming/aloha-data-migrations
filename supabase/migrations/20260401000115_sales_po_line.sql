CREATE TABLE IF NOT EXISTS sales_po_line (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL REFERENCES org_farm(id),
    sales_po_id         UUID NOT NULL REFERENCES sales_po(id),
    sales_product_id    TEXT NOT NULL REFERENCES sales_product(id),

    order_quantity      NUMERIC NOT NULL,
    price_per_case      NUMERIC NOT NULL,

    -- Buyer-side line identifiers from inbound 850. Snapshots at PO
    -- receipt time so outbound 856/810 echo the original buyer values
    -- even if sales_product_buyer_part is later edited. NULL for manual
    -- (non-EDI) orders.
    buyer_part_number   TEXT,
    buyer_description   TEXT,
    buyer_uom           TEXT,
    buyer_line_sequence INTEGER,
    gtin_case           TEXT,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_po_line UNIQUE (sales_po_id, sales_product_id)
);

COMMENT ON TABLE sales_po_line IS 'Individual products within an order. One row per product per order with snapshot pricing at time of order. Buyer-side identifiers (buyer_part_number, buyer_description, buyer_uom, buyer_line_sequence, gtin_case) are populated from inbound SPS 850 documents and echoed on outbound 856/810.';

COMMENT ON COLUMN sales_po_line.price_per_case IS 'Snapshot from sales_product_price; resolved by customer_id first, then customer_group_id, then default fob price; read-only';
COMMENT ON COLUMN sales_po_line.buyer_part_number IS 'EDI-only. Snapshot from 850 LineItem BuyerPartNumber. Resolved against sales_product_buyer_part to set sales_product_id at PO receipt; preserved here so outbound 856/810 echo the original.';
COMMENT ON COLUMN sales_po_line.buyer_description IS 'EDI-only. Snapshot of the buyer''s line description from 850. Echoed on 810 invoice lines.';
COMMENT ON COLUMN sales_po_line.buyer_uom IS 'EDI-only. Buyer''s ordering UOM from 850 LineItem (e.g. CA, EA). Free text - buyers'' codes don''t always map to sys_uom.';
COMMENT ON COLUMN sales_po_line.buyer_line_sequence IS 'EDI-only. Line sequence number from 850 LineItem PO101. Required on outbound 856 LIN and 810 IT1 to maintain line correlation.';
COMMENT ON COLUMN sales_po_line.gtin_case IS 'EDI-only. Case-level GTIN-14 snapshot at PO receipt. Pulled from sales_product_buyer_part.gtin_case; copied here so outbound 856/810 don''t depend on the lookup row still existing.';

CREATE INDEX idx_sales_po_line_org_id  ON sales_po_line (org_id);
CREATE INDEX idx_sales_po_line_order   ON sales_po_line (sales_po_id);
CREATE INDEX idx_sales_po_line_product ON sales_po_line (sales_product_id);
