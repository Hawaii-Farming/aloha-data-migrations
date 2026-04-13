CREATE TABLE IF NOT EXISTS hr_title (
    id          TEXT        PRIMARY KEY,
    org_id      TEXT        NOT NULL REFERENCES org(id),
    name        TEXT        NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted   BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT uq_hr_title UNIQUE (org_id, name)
);

COMMENT ON TABLE hr_title IS 'Org-specific job titles used to classify employees. Each org defines its own set of titles.';

CREATE INDEX idx_hr_title_org_id ON hr_title (org_id);
CREATE INDEX idx_hr_title_active ON hr_title (org_id, is_deleted);

