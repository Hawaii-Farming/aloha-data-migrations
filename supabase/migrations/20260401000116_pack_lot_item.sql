CREATE TABLE IF NOT EXISTS pack_lot_item (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    pack_lot_id         UUID NOT NULL REFERENCES pack_lot(id),
    sales_product_id    TEXT NOT NULL REFERENCES sales_product(code),

    best_by_date        DATE NOT NULL,
    pack_quantity       NUMERIC NOT NULL,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_pack_lot_item UNIQUE (pack_lot_id, sales_product_id)
);

COMMENT ON TABLE pack_lot_item IS 'Individual products packed within a lot. One row per product per lot. pack_quantity is always in the product sale_uom.';

COMMENT ON COLUMN pack_lot_item.pack_quantity IS 'Always in the sale_uom defined on the associated sales_product';
COMMENT ON COLUMN pack_lot_item.best_by_date IS 'Auto-calculated: pack_lot.pack_date plus sales_product.shelf_life_days';

CREATE INDEX idx_pack_lot_item_org_id   ON pack_lot_item (org_id);
CREATE INDEX idx_pack_lot_item_lot      ON pack_lot_item (pack_lot_id);
CREATE INDEX idx_pack_lot_item_product  ON pack_lot_item (sales_product_id);

