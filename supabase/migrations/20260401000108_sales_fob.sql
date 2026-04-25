CREATE TABLE IF NOT EXISTS sales_fob (
    org_id     TEXT NOT NULL REFERENCES org(id),
    name       TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sales_fob UNIQUE (org_id, name)
);

COMMENT ON TABLE sales_fob IS 'Defines each organization''s available delivery methods (e.g. Farm Pick-up, Local Delivery, Distributor). Used in customer setup to set a preferred delivery and in pricing to set delivery-specific prices.';

