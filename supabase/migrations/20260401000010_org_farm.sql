CREATE TABLE IF NOT EXISTS org_farm (
    id               TEXT PRIMARY KEY,
    org_id           TEXT NOT NULL REFERENCES org(id),
    name             TEXT NOT NULL,
    weighing_uom  TEXT REFERENCES sys_uom(code),
    growing_uom   TEXT REFERENCES sys_uom(code),
    volume_uom    TEXT REFERENCES sys_uom(code),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by       TEXT,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       TEXT,
    is_deleted        BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_farm UNIQUE (org_id, name)
);

COMMENT ON TABLE org_farm IS 'Represents a crop or product line within an organization (e.g. Cuke Farm, Lettuce Farm). Each farm has its own sites, varieties, grades, and products. Farm-level defaults reference units of measure for weighing and growing operations.';

COMMENT ON COLUMN org_farm.weighing_uom IS 'Default weight unit for this farm; pre-fills grow_harvest_container.weight_uom and sales_product.weight_uom';
COMMENT ON COLUMN org_farm.growing_uom IS 'Default growing unit for this farm; pre-fills grow_seed_batch.seeding_uom';
COMMENT ON COLUMN org_farm.volume_uom IS 'Default volume unit for this farm; pre-fills grow_spray_equipment.water_uom and grow_fertigation.volume_uom';
