CREATE TABLE IF NOT EXISTS ops_task_template (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT,
    ops_task_id     TEXT NOT NULL REFERENCES ops_task(id),
    ops_template_id TEXT NOT NULL REFERENCES ops_template(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_ops_task_template UNIQUE (ops_task_id, ops_template_id),
    CONSTRAINT ops_task_template_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE ops_task_template IS 'Many-to-many link between tasks and checklist templates. One task can require multiple checklists and the same checklist can be reused across tasks (e.g. spraying → pre_spray_safety_check + ppe_checklist). When a user creates an activity, the app auto-loads all templates linked to that task.';

COMMENT ON COLUMN ops_task_template.farm_id IS 'Inherited from ops_task.farm_id or ops_template.farm_id when the link is created';

CREATE INDEX idx_ops_task_template_task ON ops_task_template (ops_task_id);
CREATE INDEX idx_ops_task_template_template ON ops_task_template (ops_template_id);
