-- HR Department lookup table.
-- Org-specific departments used to classify employees (e.g. GH, PH, Lettuce).
-- Composite PK (org_id, id) lets every org reuse the same department names
-- (e.g. "Operations") without ID-namespace collisions across orgs.
CREATE TABLE IF NOT EXISTS hr_department (
    id          TEXT        NOT NULL,
    org_id      TEXT        NOT NULL REFERENCES org(id),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN     NOT NULL DEFAULT false,
    PRIMARY KEY (org_id, id)
);

COMMENT ON TABLE hr_department IS 'Org-specific departments used to classify employees. Each org defines its own set of departments. id is the display name (e.g. "GH", "PH", "Lettuce", "Operations").';

CREATE INDEX idx_hr_department_active ON hr_department (org_id, is_deleted);
