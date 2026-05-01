CREATE TABLE IF NOT EXISTS sales_po_fulfillment (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL,
    sales_po_id         UUID NOT NULL REFERENCES sales_po(id),
    sales_po_line_id    UUID NOT NULL REFERENCES sales_po_line(id),
    pack_lot_id         UUID REFERENCES pack_lot(id),

    fulfilled_quantity  NUMERIC NOT NULL,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT sales_po_fulfillment_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE sales_po_fulfillment IS 'Fulfillment records linking order lines to pack lots. One row per lot per order line, supporting partial fulfillment across multiple lots. Pallet/container assignment lives downstream on sales_pallet + sales_pallet_allocation.';

COMMENT ON COLUMN sales_po_fulfillment.pack_lot_id IS 'Sourced from pack_lot; links fulfilled quantity to a specific production lot';

CREATE INDEX idx_sales_po_fulfillment_org_id     ON sales_po_fulfillment (org_id);
CREATE INDEX idx_sales_po_fulfillment_order_line ON sales_po_fulfillment (sales_po_line_id);
CREATE INDEX idx_sales_po_fulfillment_lot        ON sales_po_fulfillment (pack_lot_id);
