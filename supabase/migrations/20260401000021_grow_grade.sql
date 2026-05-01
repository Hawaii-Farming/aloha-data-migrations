CREATE TABLE IF NOT EXISTS grow_grade (
    id       TEXT PRIMARY KEY,
    org_id     TEXT NOT NULL REFERENCES org(id),
    farm_id    TEXT NOT NULL,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_grade_name UNIQUE (farm_id, name),
    CONSTRAINT grow_grade_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE grow_grade IS 'Harvest quality grades for a specific farm, each with a short code. Applied during harvest logging and carried through to product definition, packing, and sales.';
