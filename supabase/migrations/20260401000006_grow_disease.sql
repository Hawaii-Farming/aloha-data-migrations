CREATE TABLE IF NOT EXISTS grow_disease (
    name       TEXT PRIMARY KEY,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_disease UNIQUE (name)
);

COMMENT ON TABLE grow_disease IS 'System-wide disease catalog for scouting observations. Diseases are biological facts shared across all organizations.';
