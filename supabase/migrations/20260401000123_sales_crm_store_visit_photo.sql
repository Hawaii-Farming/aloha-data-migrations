CREATE TABLE IF NOT EXISTS sales_crm_store_visit_photo (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_crm_store_visit_id    UUID NOT NULL REFERENCES sales_crm_store_visit(id),
    photo_url                   TEXT NOT NULL,
    caption                     TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE sales_crm_store_visit_photo IS 'Photos taken during a store visit. One row per photo.';

CREATE INDEX idx_sales_crm_visit_photo_visit ON sales_crm_store_visit_photo (sales_crm_store_visit_id);
