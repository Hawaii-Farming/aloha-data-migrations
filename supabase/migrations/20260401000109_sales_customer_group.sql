CREATE TABLE IF NOT EXISTS sales_customer_group (
    org_id     TEXT NOT NULL REFERENCES org(id),
    name       TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sales_customer_group UNIQUE (org_id, name)
);

COMMENT ON TABLE sales_customer_group IS 'Allows each organization to classify customers into groups for reporting and group-based pricing (e.g. Wholesale, Retail, Restaurant).';

