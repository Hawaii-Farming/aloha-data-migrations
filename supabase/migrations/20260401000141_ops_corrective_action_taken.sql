CREATE TABLE IF NOT EXISTS ops_corrective_action_taken (
    org_id                              TEXT        NOT NULL REFERENCES org(id),
    id                                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                             TEXT        REFERENCES org_farm(name),
    ops_template_name                     TEXT        REFERENCES ops_template(name),
    ops_template_result_id                     UUID        REFERENCES ops_template_result(id),
    fsafe_result_id                 UUID        REFERENCES fsafe_result(id),
    fsafe_pest_result_id            UUID        REFERENCES fsafe_pest_result(id),
    ops_corrective_action_choice_name     TEXT        REFERENCES ops_corrective_action_choice(name),

    other_action        TEXT,
    assigned_to         TEXT,
    due_date            DATE,
    completed_at        TIMESTAMPTZ,
    is_resolved         BOOLEAN     NOT NULL DEFAULT false,
    notes               TEXT,

    result_description  TEXT,

    verified_at         TIMESTAMPTZ,
    verified_by         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN     NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_ops_corrective_action_taken_assigned_to
      FOREIGN KEY (assigned_to) REFERENCES hr_employee(name),
    CONSTRAINT fk_ops_corrective_action_taken_verified_by
      FOREIGN KEY (verified_by) REFERENCES hr_employee(name)
);

COMMENT ON TABLE ops_corrective_action_taken IS 'Corrective actions raised against a failing checklist response or EMP test result. Tracks the action required, who is responsible, and the resolution status.';

CREATE INDEX idx_ops_corrective_action_taken_org_id   ON ops_corrective_action_taken (org_id);
CREATE INDEX idx_ops_corrective_action_taken_response ON ops_corrective_action_taken (ops_template_result_id);
CREATE INDEX idx_ops_corrective_action_taken_result   ON ops_corrective_action_taken (fsafe_result_id);
CREATE INDEX idx_ops_corrective_action_taken_pest_result ON ops_corrective_action_taken (fsafe_pest_result_id);
CREATE INDEX idx_ops_corrective_action_taken_assigned ON ops_corrective_action_taken (assigned_to);
CREATE INDEX idx_ops_corrective_action_taken_resolved ON ops_corrective_action_taken (org_id, is_resolved);
COMMENT ON COLUMN ops_corrective_action_taken.ops_template_name IS 'Inherited from ops_template_result.ops_template_name when sourced from a failing checklist response';
COMMENT ON COLUMN ops_corrective_action_taken.ops_template_result_id IS 'Sourced from the failing ops_template_result that triggered this corrective action';
COMMENT ON COLUMN ops_corrective_action_taken.fsafe_result_id IS 'Sourced from the failing fsafe_result that triggered this corrective action';
COMMENT ON COLUMN ops_corrective_action_taken.fsafe_pest_result_id IS 'Sourced from the pest activity observation that triggered this corrective action';

