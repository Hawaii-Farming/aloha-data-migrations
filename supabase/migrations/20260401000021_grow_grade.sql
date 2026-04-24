CREATE TABLE IF NOT EXISTS grow_grade (
    org_id     TEXT NOT NULL REFERENCES org(id),
    code       TEXT PRIMARY KEY,
    farm_name    TEXT NOT NULL REFERENCES org_farm(name),
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_grade_name UNIQUE (farm_name, name)
);

COMMENT ON TABLE grow_grade IS 'Harvest quality grades for a specific farm, each with a short code. Applied during harvest logging and carried through to product definition, packing, and sales.';
