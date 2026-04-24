CREATE TABLE IF NOT EXISTS ops_task (
    org_id      TEXT NOT NULL REFERENCES org(id),
    farm_id     TEXT REFERENCES org_farm(name),
    name       TEXT PRIMARY KEY,
    description TEXT,
    qb_account  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted   BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_ops_task_name UNIQUE (org_id, name)
);

COMMENT ON TABLE ops_task IS 'Flat task catalog for labor tracking. Tasks can be org-wide or scoped to a specific farm.';

CREATE INDEX idx_ops_task_org_id ON ops_task (org_id);

