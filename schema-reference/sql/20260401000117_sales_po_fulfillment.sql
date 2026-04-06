CREATE TABLE IF NOT EXISTS sales_po_fulfillment (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL REFERENCES org_farm(id),
    sales_po_id         UUID NOT NULL REFERENCES sales_po(id),
    sales_po_line_id    UUID NOT NULL REFERENCES sales_po_line(id),
    pack_lot_id         UUID REFERENCES pack_lot(id),

    fulfilled_quantity  NUMERIC NOT NULL,

    -- Shipping traceability (bulk-set during containerization)
    sales_container_type_id TEXT REFERENCES sales_container_type(id),
    container_id        TEXT,
    booking_id          TEXT,
    pallet_number       TEXT,
    container_space     TEXT,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE sales_po_fulfillment IS 'Fulfillment records linking order lines to pack lots. One row per lot per order line, supporting partial fulfillment across multiple lots. Shipping traceability fields are bulk-set during containerization and cascaded from a form filtered by invoice date and farm.';

COMMENT ON COLUMN sales_po_fulfillment.sales_container_type_id IS 'Container type used for shipping; set during containerization';
COMMENT ON COLUMN sales_po_fulfillment.container_id IS 'Physical shipping container number; cascaded from containerization form';
COMMENT ON COLUMN sales_po_fulfillment.booking_id IS 'Shipping line booking reference; cascaded from containerization form';
COMMENT ON COLUMN sales_po_fulfillment.pallet_number IS 'Pallet identifier assigned during palletization (e.g. CP01, LP02)';
COMMENT ON COLUMN sales_po_fulfillment.container_space IS 'Container space position assigned during containerization (e.g. C01, L02)';

COMMENT ON COLUMN sales_po_fulfillment.pack_lot_id IS 'Sourced from pack_lot; links fulfilled quantity to a specific production lot';

CREATE INDEX idx_sales_po_fulfillment_org_id     ON sales_po_fulfillment (org_id);
CREATE INDEX idx_sales_po_fulfillment_order_line ON sales_po_fulfillment (sales_po_line_id);
CREATE INDEX idx_sales_po_fulfillment_lot        ON sales_po_fulfillment (pack_lot_id);

