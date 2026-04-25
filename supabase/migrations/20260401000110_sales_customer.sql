CREATE TABLE IF NOT EXISTS sales_customer (
    org_id          TEXT NOT NULL REFERENCES org(id),
    sales_customer_group_name   TEXT REFERENCES sales_customer_group(name),
    sales_fob_name          TEXT REFERENCES sales_fob(name),
    qb_account     TEXT,
    name            TEXT PRIMARY KEY,
    email           TEXT,
    cc_emails       JSONB NOT NULL DEFAULT '[]',
    billing_address TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sales_customer_org_name UNIQUE (org_id, name)
);

COMMENT ON TABLE sales_customer IS 'Stores an organization''s customers with their group classification, preferred delivery method, billing address, and a link to external accounting software via qb_account. Additional contact emails are stored in cc_emails.';

CREATE INDEX idx_sales_customer_org_id ON sales_customer (org_id);

COMMENT ON COLUMN sales_customer.sales_customer_group_name IS 'Cascades to sales_po.sales_customer_group_name when an order is created for this customer';
COMMENT ON COLUMN sales_customer.sales_fob_name IS 'Default FOB delivery point; cascades to sales_po.sales_fob_name when an order is created for this customer';
COMMENT ON COLUMN sales_customer.qb_account IS 'QuickBooks account identifier for accounting integration';
