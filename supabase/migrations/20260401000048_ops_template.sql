CREATE TABLE IF NOT EXISTS ops_template (
    id                          TEXT        PRIMARY KEY,
    org_id                      TEXT        NOT NULL REFERENCES org(id),
    farm_id                     TEXT,

    sys_module_id               TEXT,
    description                 TEXT,

    display_order               INTEGER     NOT NULL DEFAULT 0,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT ops_template_farm_fkey
      FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id),
    CONSTRAINT ops_template_org_module_fkey
      FOREIGN KEY (org_id, sys_module_id) REFERENCES org_module(org_id, sys_module_id)
);

COMMENT ON TABLE ops_template IS 'Master checklist template. Defines the checklist and the questions employees answer during a task event.';

CREATE INDEX idx_ops_template_org_id ON ops_template (org_id);

-- Partial unique indexes handle NULL farm_id correctly (NULL != NULL in standard UNIQUE constraints)
CREATE UNIQUE INDEX uq_ops_template_org_level  ON ops_template (org_id, id) WHERE farm_id IS NULL;
CREATE UNIQUE INDEX uq_ops_template_farm_level ON ops_template (org_id, farm_id, id) WHERE farm_id IS NOT NULL;
