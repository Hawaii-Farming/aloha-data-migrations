CREATE TABLE IF NOT EXISTS ops_task (
    id          TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES org(id),
    farm_id     TEXT REFERENCES org_farm(id),
    name        TEXT NOT NULL,
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
COMMENT ON COLUMN ops_task.qb_account IS 'QuickBooks account that scheduled hours on this task roll up to for cost attribution; nullable when a task has no bookkeeping account assigned.';

CREATE INDEX idx_ops_task_org_id ON ops_task (org_id);

