CREATE TABLE IF NOT EXISTS grow_trial_type (
    id        TEXT PRIMARY KEY,
    org_id      TEXT NOT NULL REFERENCES org(id),
    farm_id     TEXT NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_trial_type UNIQUE (org_id, farm_id, id),
    CONSTRAINT grow_trial_type_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE grow_trial_type IS 'Lookup table defining types of seeding trials (e.g. new lot, new variety, new seed source). Farm-scoped.';

-- Static reference row used by grow_cuke_seed_batch.grow_trial_type_id on
-- the 13 historical trial blocks migrated from grow_C_seeding. Retired
-- migration 024 used to re-seed this nightly; with that gone, the row
-- needs to live here.
INSERT INTO public.grow_trial_type (org_id, farm_id, id, description, created_by, updated_by)
VALUES (
  'hawaii_farming',
  'Cuke',
  'Legacy Trial',
  'Generic trial type used to flag historical trial seedings migrated from the legacy grow_C_seeding sheet',
  'data@hawaiifarming.com',
  'data@hawaiifarming.com'
)
ON CONFLICT (id) DO NOTHING;
