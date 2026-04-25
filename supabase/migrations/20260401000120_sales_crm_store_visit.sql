CREATE TABLE IF NOT EXISTS sales_crm_store_visit (
    org_id                  TEXT NOT NULL REFERENCES org(id),
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_crm_store_id      TEXT NOT NULL REFERENCES sales_crm_store(id),
    visit_date              DATE NOT NULL,
    notes                   TEXT,
    visited_by              TEXT REFERENCES hr_employee(name),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE sales_crm_store_visit IS 'Store visit records capturing field observations, notes from store managers, and action items.';


CREATE INDEX idx_sales_crm_store_visit_org ON sales_crm_store_visit (org_id);
CREATE INDEX idx_sales_crm_store_visit_store ON sales_crm_store_visit (sales_crm_store_id);
CREATE INDEX idx_sales_crm_store_visit_date ON sales_crm_store_visit (visit_date);
