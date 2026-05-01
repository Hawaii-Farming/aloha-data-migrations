-- HR Work Authorization lookup table.
-- Org-specific work authorization types used to classify employees (e.g. Local, FUERTE, WFE, H1B).
-- Composite PK (org_id, id) lets every org reuse the same authorization names
-- (e.g. "Local") without ID-namespace collisions across orgs.
CREATE TABLE IF NOT EXISTS hr_work_authorization (
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

COMMENT ON TABLE hr_work_authorization IS 'Org-specific work authorization types used to classify employees. Each org defines its own set of types. id is the display name (e.g. "Local", "FUERTE", "WFE", "H1B").';

CREATE INDEX idx_hr_work_authorization_active ON hr_work_authorization (org_id, is_deleted);
