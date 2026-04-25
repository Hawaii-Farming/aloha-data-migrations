CREATE TABLE IF NOT EXISTS grow_cycle_pattern (
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    name                TEXT PRIMARY KEY,
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_cycle_pattern UNIQUE (org_id, farm_name, name)
);

COMMENT ON TABLE grow_cycle_pattern IS 'Defines growing cycle patterns per farm (e.g. 18/17/17 harvest pattern). Used to classify seeding batches by their growth cycle.';
