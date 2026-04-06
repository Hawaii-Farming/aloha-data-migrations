CREATE TABLE IF NOT EXISTS grow_fertigation_recipe (
    id              TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL REFERENCES org_farm(id),
    name            TEXT NOT NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_fertigation_recipe UNIQUE (org_id, farm_id, name)
);

COMMENT ON TABLE grow_fertigation_recipe IS 'Reusable fertigation recipe. Can be a fertilizer mix, flush water, or top-up water — each is a separate recipe. Items are defined in grow_fertigation_recipe_item. Sites are linked via grow_fertigation_recipe_site.';
