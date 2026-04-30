-- sales_product_buyer_part
-- ========================
-- Maps each (sales_product, buyer) pair to the buyer's own part number
-- and case GTIN. Buyers reference their own part numbers in 850 line
-- items, not ours, so we need this lookup to resolve the inbound line
-- back to a sales_product. Also stores the case-level GTIN that gets
-- echoed on 856 cartons and 810 invoice lines.
--
-- SPS-only table: pure EDI mapping layer.

CREATE TABLE IF NOT EXISTS sales_product_buyer_part (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_product_id            TEXT NOT NULL REFERENCES sales_product(id),
    sales_customer_id           TEXT NOT NULL REFERENCES sales_customer(id),

    buyer_part_number           TEXT NOT NULL,
    buyer_description           TEXT,
    buyer_uom                   TEXT,

    gtin_case                   TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_product_buyer_part UNIQUE (sales_customer_id, buyer_part_number)
);

COMMENT ON TABLE sales_product_buyer_part IS 'SPS-only. Cross-reference from a buyer''s part number to our sales_product. Inbound 850 line items carry the buyer''s SKU; we look it up here (sales_customer_id + buyer_part_number) to resolve the line to a sales_product. The unique constraint enforces that a buyer''s part number maps to exactly one of our products.';

CREATE INDEX idx_sales_product_buyer_part_org     ON sales_product_buyer_part (org_id);
CREATE INDEX idx_sales_product_buyer_part_product ON sales_product_buyer_part (sales_product_id);

COMMENT ON COLUMN sales_product_buyer_part.buyer_part_number IS 'The buyer''s SKU/item number for this product. Sent in 850 LineItem and echoed on 856/810.';
COMMENT ON COLUMN sales_product_buyer_part.buyer_description IS 'Buyer''s description text snapshot; useful for human review of EDI documents but not authoritative.';
COMMENT ON COLUMN sales_product_buyer_part.buyer_uom IS 'Buyer''s ordering unit of measure as it appears in their 850 (e.g. CA, EA). Free text, not FK''d to sys_uom because buyer codes don''t always align.';
COMMENT ON COLUMN sales_product_buyer_part.gtin_case IS 'Case-level GTIN-14 used on 856 cartons and 810 invoice lines. Distinct from sales_product.gtin which is the consumer-unit GTIN.';
