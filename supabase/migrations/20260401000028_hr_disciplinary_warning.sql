CREATE TABLE IF NOT EXISTS hr_disciplinary_warning (
    org_id                          TEXT NOT NULL REFERENCES org(id),
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hr_employee_id                     TEXT NOT NULL,

    -- Warning details
    warning_date                    DATE,
    warning_type                    TEXT CHECK (warning_type IN ('verbal_warning', 'written_warning', 'final_warning')),
    offense_type                    TEXT,
    offense_description             TEXT,

    -- Action plan
    plan_for_improvement            TEXT,
    further_infraction_consequences TEXT,
    notes                           TEXT,

    -- Acknowledgment
    is_acknowledged                 BOOLEAN NOT NULL DEFAULT false,
    acknowledged_at                 TIMESTAMPTZ,
    employee_signature_url          TEXT,

    status                          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed')),

    reported_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    reported_by                     TEXT,
    reviewed_at                     TIMESTAMPTZ,
    reviewed_by                     TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                       BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_hr_disciplinary_warning_employee
      FOREIGN KEY (hr_employee_id) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_disciplinary_warning_reported_by
      FOREIGN KEY (reported_by) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_disciplinary_warning_reviewed_by
      FOREIGN KEY (reviewed_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE hr_disciplinary_warning IS 'Employee disciplinary warning records. Tracks the offense, action plan, and employee acknowledgment alongside a pending to reviewed workflow.';

CREATE INDEX idx_hr_disciplinary_warning_org_id ON hr_disciplinary_warning (org_id);
CREATE INDEX idx_hr_disciplinary_warning_employee ON hr_disciplinary_warning (hr_employee_id);
CREATE INDEX idx_hr_disciplinary_warning_status ON hr_disciplinary_warning (org_id, status);
CREATE INDEX idx_hr_disciplinary_warning_date ON hr_disciplinary_warning (hr_employee_id, warning_date);

COMMENT ON COLUMN hr_disciplinary_warning.warning_type IS 'verbal_warning, written_warning, final_warning';
COMMENT ON COLUMN hr_disciplinary_warning.status IS 'pending, reviewed';
