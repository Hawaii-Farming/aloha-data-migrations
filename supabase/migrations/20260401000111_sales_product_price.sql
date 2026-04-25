CREATE TABLE IF NOT EXISTS sales_product_price (
    org_id         TEXT NOT NULL REFERENCES org(id),
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name        TEXT NOT NULL REFERENCES org_farm(name),
    sales_product_id     TEXT NOT NULL REFERENCES sales_product(code),
    sales_fob_name         TEXT NOT NULL REFERENCES sales_fob(name),
    sales_customer_group_name  TEXT REFERENCES sales_customer_group(name),
    sales_customer_name        TEXT REFERENCES sales_customer(name),
    price_per_case NUMERIC NOT NULL,
    effective_from DATE NOT NULL,
    effective_to   DATE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by     TEXT,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by     TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE sales_product_price IS 'Manages product pricing with three tiers of specificity and date ranges to track price changes over time. When a price changes, the current row gets an effective_to date and a new row is created. Currency always uses the org default from org.currency.';

CREATE INDEX idx_sales_product_price_lookup ON sales_product_price (sales_product_id, sales_fob_name);

CREATE INDEX idx_sales_product_price_org ON sales_product_price (org_id);
