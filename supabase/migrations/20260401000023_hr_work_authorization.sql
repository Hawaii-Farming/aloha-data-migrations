-- HR Work Authorization lookup table.
-- Org-specific work authorization types used to classify employees (e.g. Local, FURTE, WFE, H1B).
-- TEXT PK is the display name verbatim.
CREATE TABLE IF NOT EXISTS hr_work_authorization (
    id          TEXT        PRIMARY KEY,
    org_id      TEXT        NOT NULL REFERENCES org(id),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted   BOOLEAN     NOT NULL DEFAULT false
);

COMMENT ON TABLE hr_work_authorization IS 'Org-specific work authorization types used to classify employees. Each org defines its own set of types. id is the display name (e.g. "Local", "FURTE", "WFE", "H1B").';

CREATE INDEX idx_hr_work_authorization_org_id ON hr_work_authorization (org_id);
CREATE INDEX idx_hr_work_authorization_active ON hr_work_authorization (org_id, is_deleted);
