CREATE TABLE IF NOT EXISTS ops_template (
    org_id                      TEXT        NOT NULL REFERENCES org(id),
    id                          TEXT        PRIMARY KEY,
    farm_name                     TEXT        REFERENCES org_farm(name),

    name                        TEXT        NOT NULL,
    org_module_name               TEXT        REFERENCES org_module(name),
    description                 TEXT,

    display_order               INTEGER     NOT NULL DEFAULT 0,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                   BOOLEAN     NOT NULL DEFAULT false
);

COMMENT ON TABLE ops_template IS 'Master checklist template. Defines the checklist and the questions employees answer during a task event.';

CREATE INDEX idx_ops_template_org_id ON ops_template (org_id);

-- Partial unique indexes handle NULL farm_name correctly (NULL != NULL in standard UNIQUE constraints)
CREATE UNIQUE INDEX uq_ops_template_org_level  ON ops_template (org_id, name) WHERE farm_name IS NULL;
CREATE UNIQUE INDEX uq_ops_template_farm_level ON ops_template (org_id, farm_name, name) WHERE farm_name IS NOT NULL;

