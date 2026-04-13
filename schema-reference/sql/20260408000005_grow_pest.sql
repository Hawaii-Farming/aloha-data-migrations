CREATE TABLE IF NOT EXISTS grow_pest (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_pest UNIQUE (name)
);

COMMENT ON TABLE grow_pest IS 'System-wide pest catalog for scouting observations. Pests are biological facts shared across all organizations.';
