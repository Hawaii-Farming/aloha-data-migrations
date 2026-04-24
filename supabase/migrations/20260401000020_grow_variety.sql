CREATE TABLE IF NOT EXISTS grow_variety (
    org_id     TEXT NOT NULL REFERENCES org(id),
    code       TEXT PRIMARY KEY,
    farm_name    TEXT NOT NULL REFERENCES org_farm(name),
    name       TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_variety_name UNIQUE (farm_name, name)
);

COMMENT ON TABLE grow_variety IS 'Crop varieties grown on a specific farm, each with a short code for quick reference during data entry. Used across seeding, growing, and harvest modules.';
