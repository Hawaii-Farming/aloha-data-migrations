CREATE TABLE IF NOT EXISTS grow_lettuce_seed_mix (
    name        TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES org(id),
    farm_name     TEXT NOT NULL REFERENCES org_farm(name),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_lettuce_seed_mix UNIQUE (org_id, farm_name, name)
);

COMMENT ON TABLE grow_lettuce_seed_mix IS 'Named seed blend recipes (e.g. Spring Blend, Mixed Version 1). Farm-scoped. Items and percentages are defined in grow_lettuce_seed_mix_item.';
