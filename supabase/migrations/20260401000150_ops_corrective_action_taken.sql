CREATE TABLE IF NOT EXISTS ops_corrective_action_taken (
    id                                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                              TEXT        NOT NULL REFERENCES org(id),
    farm_id                             TEXT,
    ops_template_id                     TEXT        REFERENCES ops_template(id),
    ops_template_result_id                     UUID        REFERENCES ops_template_result(id),
    fsafe_result_id                 UUID        REFERENCES fsafe_result(id),
    fsafe_pest_result_id            UUID        REFERENCES fsafe_pest_result(id),
    ops_corrective_action_choice_id     TEXT        REFERENCES ops_corrective_action_choice(id),

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
      FOREIGN KEY (org_id, assigned_to) REFERENCES hr_employee(org_id, id),
    CONSTRAINT fk_ops_corrective_action_taken_verified_by
      FOREIGN KEY (org_id, verified_by) REFERENCES hr_employee(org_id, id),
    CONSTRAINT ops_corrective_action_taken_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE ops_corrective_action_taken IS 'Corrective actions raised against a failing checklist response or EMP test result. Tracks the action required, who is responsible, and the resolution status.';

CREATE INDEX idx_ops_corrective_action_taken_org_id   ON ops_corrective_action_taken (org_id);
CREATE INDEX idx_ops_corrective_action_taken_response ON ops_corrective_action_taken (ops_template_result_id);
CREATE INDEX idx_ops_corrective_action_taken_result   ON ops_corrective_action_taken (fsafe_result_id);
CREATE INDEX idx_ops_corrective_action_taken_pest_result ON ops_corrective_action_taken (fsafe_pest_result_id);
CREATE INDEX idx_ops_corrective_action_taken_assigned ON ops_corrective_action_taken (assigned_to);
CREATE INDEX idx_ops_corrective_action_taken_resolved ON ops_corrective_action_taken (org_id, is_resolved);
COMMENT ON COLUMN ops_corrective_action_taken.ops_template_id IS 'Inherited from ops_template_result.ops_template_id when sourced from a failing checklist response';
COMMENT ON COLUMN ops_corrective_action_taken.ops_template_result_id IS 'Sourced from the failing ops_template_result that triggered this corrective action';
COMMENT ON COLUMN ops_corrective_action_taken.fsafe_result_id IS 'Sourced from the failing fsafe_result that triggered this corrective action';
COMMENT ON COLUMN ops_corrective_action_taken.fsafe_pest_result_id IS 'Sourced from the pest activity observation that triggered this corrective action';

