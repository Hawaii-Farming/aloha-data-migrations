CREATE TABLE IF NOT EXISTS org_site_category (
    id                  TEXT PRIMARY KEY,
    org_id              TEXT NOT NULL REFERENCES org(id),
    category_name       TEXT NOT NULL,
    sub_category_name   TEXT,
    display_order       INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE org_site_category IS 'Two-level site category hierarchy. Rows with sub_category_name IS NULL are top-level categories (e.g. growing, packing, housing). Rows with sub_category_name set are subcategories (e.g. greenhouse, nursery under growing). Both org_site_category_id and org_site_subcategory_id on org_site reference this table.';

CREATE UNIQUE INDEX uq_org_site_category_top ON org_site_category (org_id, category_name) WHERE sub_category_name IS NULL;
CREATE UNIQUE INDEX uq_org_site_category_sub ON org_site_category (org_id, category_name, sub_category_name) WHERE sub_category_name IS NOT NULL;

COMMENT ON COLUMN org_site_category.sub_category_name IS 'NULL for top-level categories; set for subcategories under that category_name';
