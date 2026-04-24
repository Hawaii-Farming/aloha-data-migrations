CREATE TABLE IF NOT EXISTS sales_crm_store_visit_result (
    org_id                          TEXT NOT NULL REFERENCES org(id),
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_crm_store_visit_id        UUID NOT NULL REFERENCES sales_crm_store_visit(id),
    sales_product_id                TEXT REFERENCES sales_product(code),
    sales_crm_external_product_name   TEXT REFERENCES sales_crm_external_product(name),
    shelf_price                     NUMERIC,
    best_by_date                    DATE,
    stock_level                     TEXT CHECK (stock_level IN ('zero', 'low', 'medium', 'full')),
    cases_per_week                  NUMERIC,
    notes                           TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT chk_sales_crm_visit_result_product CHECK (
        (sales_product_id IS NOT NULL AND sales_crm_external_product_name IS NULL)
        OR (sales_product_id IS NULL AND sales_crm_external_product_name IS NOT NULL)
    )
);

COMMENT ON TABLE sales_crm_store_visit_result IS 'Per-product observations collected during a store visit. Each row captures shelf price, best-by date, stock level, and weekly velocity for either an own product or a competitor product.';

CREATE INDEX idx_sales_crm_visit_result_visit ON sales_crm_store_visit_result (sales_crm_store_visit_id);
CREATE INDEX idx_sales_crm_visit_result_product ON sales_crm_store_visit_result (sales_product_id);
CREATE INDEX idx_sales_crm_visit_result_ext ON sales_crm_store_visit_result (sales_crm_external_product_name);
