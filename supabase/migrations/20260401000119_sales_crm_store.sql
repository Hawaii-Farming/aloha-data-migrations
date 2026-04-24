CREATE TABLE IF NOT EXISTS sales_crm_store (
    org_id                  TEXT NOT NULL REFERENCES org(id),
    id                      TEXT PRIMARY KEY,
    sales_customer_id       TEXT REFERENCES sales_customer(id),
    chain                   TEXT,
    name                    TEXT NOT NULL,
    location                TEXT,
    island                  TEXT,
    contact_name            TEXT,
    contact_title           TEXT,
    contact_email           TEXT,
    contact_phone           TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sales_crm_store UNIQUE (org_id, name)
);

COMMENT ON TABLE sales_crm_store IS 'Physical retail locations where products are sold. Each store belongs to a chain and optionally links to a sales_customer for order tracking.';

CREATE INDEX idx_sales_crm_store_org ON sales_crm_store (org_id);
CREATE INDEX idx_sales_crm_store_customer ON sales_crm_store (sales_customer_id);
