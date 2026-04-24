CREATE TABLE IF NOT EXISTS ops_training (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_name                 TEXT REFERENCES org_farm(name),

    ops_training_type_id    TEXT REFERENCES ops_training_type(id),
    training_date           DATE,
    topics_covered          JSONB NOT NULL DEFAULT '[]',
    trainer_id              TEXT,
    materials_url           TEXT,

    notes                   TEXT,

    verified_at             TIMESTAMPTZ,
    verified_by             TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted               BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_ops_training_trainer
      FOREIGN KEY (trainer_id) REFERENCES hr_employee(id),
    CONSTRAINT fk_ops_training_verified_by
      FOREIGN KEY (verified_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE ops_training IS 'Staff training session records. Each row is one training event covering a specific topic for a group of employees.';

CREATE INDEX idx_ops_training_org_id ON ops_training (org_id);
CREATE INDEX idx_ops_training_farm   ON ops_training (farm_name);
CREATE INDEX idx_ops_training_date   ON ops_training (org_id, training_date);
CREATE INDEX idx_ops_training_type   ON ops_training (ops_training_type_id);

COMMENT ON COLUMN ops_training.trainer_id IS 'Sourced from hr_employee; the employee who conducted the training session';
COMMENT ON COLUMN ops_training.topics_covered IS 'JSON array of topic strings covered during the training session';

