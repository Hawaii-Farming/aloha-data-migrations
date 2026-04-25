CREATE TABLE IF NOT EXISTS ops_task_tracker (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_name         TEXT REFERENCES org_farm(name),
    site_id         TEXT REFERENCES org_site(id),
    sales_product_id TEXT REFERENCES sales_product(code),
    ops_task_name     TEXT NOT NULL REFERENCES ops_task(name),
    start_time      TIMESTAMPTZ NOT NULL,
    stop_time       TIMESTAMPTZ,
    is_completed    BOOLEAN NOT NULL DEFAULT false,
    number_of_people INTEGER,
    notes           TEXT,
    verified_at     TIMESTAMPTZ,
    verified_by     TEXT REFERENCES hr_employee(name),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE ops_task_tracker IS 'Header record for a task event. One record per task session — captures what task was done, where, when, and its verification status.';

CREATE INDEX idx_ops_task_tracker_org_id ON ops_task_tracker (org_id);
CREATE INDEX idx_ops_task_tracker_task   ON ops_task_tracker (ops_task_name);
CREATE INDEX idx_ops_task_tracker_completed ON ops_task_tracker (org_id, is_completed);
CREATE INDEX idx_ops_task_tracker_site   ON ops_task_tracker (site_id);

COMMENT ON COLUMN ops_task_tracker.farm_name IS 'Pre-filled from ops_task.farm_name when task is selected; editable';
COMMENT ON COLUMN ops_task_tracker.sales_product_id IS 'The product being packed; set for packing activities, null for all other task types';
COMMENT ON COLUMN ops_task_tracker.is_completed IS 'Auto-set to true when stop_time is entered and activity is submitted';
COMMENT ON COLUMN ops_task_tracker.number_of_people IS 'Crew size assigned to this task session; used for productivity/labor-hour calculations';

