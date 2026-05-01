CREATE TABLE IF NOT EXISTS ops_task_schedule (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT,
    ops_task_id             TEXT NOT NULL REFERENCES ops_task(id),
    ops_task_tracker_id     UUID REFERENCES ops_task_tracker(id),
    hr_employee_id          TEXT NOT NULL,
    start_time              TIMESTAMPTZ NOT NULL,
    stop_time               TIMESTAMPTZ,
    -- Lunch-adjusted hours sourced from the schedule capture (sheet's daily
    -- Hours column). Computing stop - start overcounts by a 30-min lunch
    -- per shift, so the pre-computed value is authoritative here.
    total_hours             NUMERIC,

    -- NOTE: units_completed was removed because the unit type varies by task (boards for seeding,
    -- totes for harvesting, acres for spraying) and the totals are already captured in the
    -- domain-specific tables (grow_lettuce_seed_batch, grow_cuke_seed_batch, grow_harvest_weight, etc.). Individual employee
    -- contribution to the total is not yet tracked — this may be revisited with a per-employee
    -- breakdown table in the future.

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted               BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT ops_task_schedule_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id),
    CONSTRAINT ops_task_schedule_hr_employee_id_emp_fkey FOREIGN KEY (org_id, hr_employee_id) REFERENCES hr_employee(org_id, id)
);

COMMENT ON TABLE ops_task_schedule IS 'Employee task assignments for both planning and execution. When ops_task_tracker_id is null, the row is a planned schedule entry. When set, it is an executed activity. ops_task_id is always set — derived from the tracker when linked, or selected by the user for planned entries.';

COMMENT ON COLUMN ops_task_schedule.farm_id IS 'Inherited from ops_task_tracker.farm_id when linked to a tracker; user-selected for planned entries';
COMMENT ON COLUMN ops_task_schedule.ops_task_id IS 'Inherited from ops_task_tracker.ops_task_id when linked to a tracker; user-selected for planned entries';
COMMENT ON COLUMN ops_task_schedule.start_time IS 'Inherited from ops_task_tracker.start_time when linked to a tracker; user-selected for planned entries';
COMMENT ON COLUMN ops_task_schedule.stop_time IS 'Inherited from ops_task_tracker.stop_time when linked to a tracker; user-selected for planned entries';

-- Executed: one employee per tracker
CREATE UNIQUE INDEX uq_ops_task_schedule_executed ON ops_task_schedule (ops_task_tracker_id, hr_employee_id) WHERE ops_task_tracker_id IS NOT NULL;
-- Planned: one employee per task per start_time
CREATE UNIQUE INDEX uq_ops_task_schedule_planned ON ops_task_schedule (ops_task_id, hr_employee_id, start_time) WHERE ops_task_tracker_id IS NULL;

CREATE INDEX idx_ops_task_schedule_task     ON ops_task_schedule (ops_task_id);
CREATE INDEX idx_ops_task_schedule_tracker  ON ops_task_schedule (ops_task_tracker_id);
CREATE INDEX idx_ops_task_schedule_employee ON ops_task_schedule (hr_employee_id);
CREATE INDEX idx_ops_task_schedule_org_id   ON ops_task_schedule (org_id);

