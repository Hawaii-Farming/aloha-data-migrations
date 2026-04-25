CREATE TABLE IF NOT EXISTS grow_trial_type (
    name        TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES org(id),
    farm_name     TEXT NOT NULL REFERENCES org_farm(name),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_trial_type UNIQUE (org_id, farm_name, name)
);

COMMENT ON TABLE grow_trial_type IS 'Lookup table defining types of seeding trials (e.g. new lot, new variety, new seed source). Farm-scoped.';

-- Static reference row used by grow_cuke_seed_batch.grow_trial_type_name on
-- the 13 historical trial blocks migrated from grow_C_seeding. Retired
-- migration 024 used to re-seed this nightly; with that gone, the row
-- needs to live here.
INSERT INTO public.grow_trial_type (id, org_id, farm_name, name, description, created_by, updated_by)
VALUES (
  'legacy_trial',
  'hawaii_farming',
  'cuke',
  'Legacy Trial',
  'Generic trial type used to flag historical trial seedings migrated from the legacy grow_C_seeding sheet',
  'data@hawaiifarming.com',
  'data@hawaiifarming.com'
)
ON CONFLICT (id) DO NOTHING;
