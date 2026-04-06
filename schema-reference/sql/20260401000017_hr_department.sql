-- HR Department lookup table.
-- Org-specific departments used to classify employees (e.g. GH, PH, Lettuce).
-- TEXT PK derived from name (trimmed lowercase), unique within the org.
CREATE TABLE IF NOT EXISTS hr_department (
    id          TEXT        PRIMARY KEY,
    org_id      TEXT        NOT NULL REFERENCES org(id),
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted   BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT uq_hr_department UNIQUE (org_id, name)
);

COMMENT ON TABLE hr_department IS 'Org-specific departments used to classify employees. Each org defines its own set of departments.';

CREATE INDEX idx_hr_department_org_id ON hr_department (org_id);
CREATE INDEX idx_hr_department_active ON hr_department (org_id, is_deleted);

