CREATE TABLE IF NOT EXISTS grow_fertigation_recipe_site (
    org_id                      TEXT NOT NULL REFERENCES org(id),
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                     TEXT NOT NULL REFERENCES org_farm(name),
    grow_fertigation_recipe_id  TEXT NOT NULL REFERENCES grow_fertigation_recipe(id),
    site_id                     TEXT NOT NULL REFERENCES org_site(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_fertigation_recipe_site UNIQUE (grow_fertigation_recipe_id, site_id)
);

COMMENT ON TABLE grow_fertigation_recipe_site IS 'Sites that receive this fertigation recipe. Used to pre-fill site selection and look up active seedings during a fertigation event.';

CREATE INDEX idx_grow_fertigation_recipe_site_recipe ON grow_fertigation_recipe_site (grow_fertigation_recipe_id);
