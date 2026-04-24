CREATE TABLE IF NOT EXISTS ops_template_result (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT        NOT NULL REFERENCES org(id),
    farm_id                 TEXT        REFERENCES org_farm(name),
    ops_task_tracker_id     UUID        NOT NULL REFERENCES ops_task_tracker(id),
    ops_template_id         TEXT        NOT NULL REFERENCES ops_template(id),
    ops_template_question_id         UUID        REFERENCES ops_template_question(id),
    site_id                 TEXT        REFERENCES org_site(id),
    equipment_id            TEXT        REFERENCES org_equipment(id),

    response_boolean        BOOLEAN,
    response_numeric        NUMERIC,
    response_enum           TEXT,
    response_text           TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted               BOOLEAN     NOT NULL DEFAULT false
);

COMMENT ON TABLE ops_template_result IS 'Employee responses to checklist questions. One row per question per task tracker session. Each result targets either a site or equipment, never both. The linked ops_task_tracker record acts as the header (who completed the checklist, when).';

CREATE INDEX idx_ops_template_result_org_id      ON ops_template_result (org_id);
CREATE INDEX idx_ops_template_result_tracker     ON ops_template_result (ops_task_tracker_id);
CREATE INDEX idx_ops_template_result_question    ON ops_template_result (ops_template_question_id);

-- Partial unique indexes: checklist responses are unique per tracker+question; ATP results are unique per tracker+site
CREATE UNIQUE INDEX uq_ops_template_result_checklist ON ops_template_result (ops_task_tracker_id, ops_template_question_id) WHERE ops_template_question_id IS NOT NULL;
CREATE UNIQUE INDEX uq_ops_template_result_atp      ON ops_template_result (ops_task_tracker_id, site_id) WHERE ops_template_question_id IS NULL AND site_id IS NOT NULL;

COMMENT ON COLUMN ops_template_result.farm_id IS 'Inherited from ops_task_tracker.farm_id when response is created';
COMMENT ON COLUMN ops_template_result.ops_template_id IS 'Sourced from ops_task_template; identifies which template this response belongs to';
COMMENT ON COLUMN ops_template_result.ops_template_question_id IS 'Sourced from ops_template_question; null for ATP surface test results';
COMMENT ON COLUMN ops_template_result.site_id IS 'The site this checklist was completed for; null for equipment-specific checklists or standard responses without a site';
COMMENT ON COLUMN ops_template_result.equipment_id IS 'The equipment this checklist was completed for; null for site-specific checklists';
