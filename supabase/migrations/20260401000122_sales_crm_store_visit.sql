CREATE TABLE IF NOT EXISTS sales_crm_store_visit (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    sales_crm_store_id      TEXT NOT NULL REFERENCES sales_crm_store(id),
    visit_date              DATE NOT NULL,
    notes                   TEXT,
    visited_by              TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT sales_crm_store_visit_visited_by_emp_fkey FOREIGN KEY (org_id, visited_by) REFERENCES hr_employee(org_id, id)
);

COMMENT ON TABLE sales_crm_store_visit IS 'Store visit records capturing field observations, notes from store managers, and action items.';


CREATE INDEX idx_sales_crm_store_visit_org ON sales_crm_store_visit (org_id);
CREATE INDEX idx_sales_crm_store_visit_store ON sales_crm_store_visit (sales_crm_store_id);
CREATE INDEX idx_sales_crm_store_visit_date ON sales_crm_store_visit (visit_date);
