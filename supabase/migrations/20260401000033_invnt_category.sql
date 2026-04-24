CREATE TABLE IF NOT EXISTS invnt_category (
    org_id              TEXT NOT NULL REFERENCES org(id),
    id                  TEXT PRIMARY KEY,
    category_name       TEXT NOT NULL,
    sub_category_name   TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE invnt_category IS 'Two-level category hierarchy for inventory items in a single table. A row with sub_category_name IS NULL is a top-level category (e.g. Fertilizers). A row with sub_category_name set is a subcategory under that category_name (e.g. Nitrogen Fertilizers under Fertilizers). Both invnt_category_id and invnt_subcategory_id in invnt_item reference this table.';

CREATE INDEX idx_invnt_category_org_id ON invnt_category (org_id);

-- Partial unique indexes handle NULL sub_category_name correctly (NULL != NULL in standard UNIQUE constraints)
CREATE UNIQUE INDEX uq_invnt_category_top_level  ON invnt_category (org_id, category_name) WHERE sub_category_name IS NULL;
CREATE UNIQUE INDEX uq_invnt_category_sub_level   ON invnt_category (org_id, category_name, sub_category_name) WHERE sub_category_name IS NOT NULL;

COMMENT ON COLUMN invnt_category.sub_category_name IS 'NULL when this row represents a top-level category';
