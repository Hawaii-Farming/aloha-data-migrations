CREATE TABLE IF NOT EXISTS ops_task_template (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_name         TEXT REFERENCES org_farm(name),
    ops_task_name     TEXT NOT NULL REFERENCES ops_task(name),
    ops_template_name TEXT NOT NULL REFERENCES ops_template(name),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_ops_task_template UNIQUE (ops_task_name, ops_template_name)
);

COMMENT ON TABLE ops_task_template IS 'Many-to-many link between tasks and checklist templates. One task can require multiple checklists and the same checklist can be reused across tasks (e.g. spraying → pre_spray_safety_check + ppe_checklist). When a user creates an activity, the app auto-loads all templates linked to that task.';

COMMENT ON COLUMN ops_task_template.farm_name IS 'Inherited from ops_task.farm_name or ops_template.farm_name when the link is created';

CREATE INDEX idx_ops_task_template_task ON ops_task_template (ops_task_name);
CREATE INDEX idx_ops_task_template_template ON ops_task_template (ops_template_name);
