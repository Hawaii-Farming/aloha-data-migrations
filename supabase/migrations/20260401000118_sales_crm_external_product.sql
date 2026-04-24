CREATE TABLE IF NOT EXISTS sales_crm_external_product (
    id              TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    name            TEXT NOT NULL,
    display_order   INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sales_crm_external_product UNIQUE (org_id, name)
);

COMMENT ON TABLE sales_crm_external_product IS 'Competitor products observed during store visits. Simple name-based lookup (e.g. Nalo 14oz, Mainland 16oz, Sensei 4oz).';

CREATE INDEX idx_sales_crm_ext_product_org ON sales_crm_external_product (org_id);
