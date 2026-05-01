CREATE TABLE IF NOT EXISTS org_farm (
    id            TEXT NOT NULL,
    org_id        TEXT NOT NULL REFERENCES org(id),
    weighing_uom  TEXT REFERENCES sys_uom(id),
    growing_uom   TEXT REFERENCES sys_uom(id),
    volume_uom    TEXT REFERENCES sys_uom(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    TEXT,
    is_deleted    BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (org_id, id)
);

COMMENT ON TABLE org_farm IS 'Represents a crop or product line within an organization (e.g. Cuke Farm, Lettuce Farm). Each farm has its own sites, varieties, grades, and products. Farm-level defaults reference units of measure for weighing and growing operations. Composite PK (org_id, id) lets every org reuse the same farm names without ID-namespace collisions.';

COMMENT ON COLUMN org_farm.weighing_uom IS 'Default weight unit for this farm; pre-fills grow_harvest_container.weight_uom and sales_product.weight_uom';
COMMENT ON COLUMN org_farm.growing_uom IS 'Default growing unit for this farm; pre-fills grow_lettuce_seed_batch.seeding_uom (cuke batches do not carry a seeding unit)';
COMMENT ON COLUMN org_farm.volume_uom IS 'Default volume unit for this farm; pre-fills grow_spray_equipment.water_uom and grow_fertigation.volume_uom';

-- Seed the two known farms so later SQL migrations that carry reference
-- data (grow_trial_type.legacy_trial) don't hit an FK violation. The
-- Python migration 002_org.py upserts the same rows with full UOM
-- defaults on the next nightly.
INSERT INTO public.org_farm (org_id, id)
VALUES
  ('hawaii_farming', 'Cuke'),
  ('hawaii_farming', 'Lettuce')
ON CONFLICT (org_id, id) DO NOTHING;
