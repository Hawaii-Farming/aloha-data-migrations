CREATE TABLE IF NOT EXISTS ops_training_attendee (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_id                     TEXT,
    ops_training_id             UUID NOT NULL REFERENCES ops_training(id),
    hr_employee_id              TEXT NOT NULL REFERENCES hr_employee(id),

    signed_at                   TIMESTAMPTZ,

    certification_number        TEXT,
    certificate_issuer          TEXT,
    certification_issued_on     DATE,
    certification_expires_on    DATE,
    certificate_url             TEXT,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_ops_training_attendee UNIQUE (ops_training_id, hr_employee_id),
    CONSTRAINT ops_training_attendee_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE ops_training_attendee IS 'Individual attendance and certification records for each employee per training session. One row per employee per training.';

COMMENT ON COLUMN ops_training_attendee.farm_id IS 'Inherited from ops_training.farm_id when attendee record is created';

CREATE INDEX idx_ops_training_attendee_training ON ops_training_attendee (ops_training_id);
CREATE INDEX idx_ops_training_attendee_employee ON ops_training_attendee (hr_employee_id);
CREATE INDEX idx_ops_training_attendee_org      ON ops_training_attendee (org_id);

