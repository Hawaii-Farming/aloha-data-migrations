CREATE TABLE IF NOT EXISTS grow_lettuce_seed_batch (
    org_id              TEXT NOT NULL REFERENCES org(id),
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    site_id             TEXT REFERENCES org_site(id),
    ops_task_tracker_id UUID REFERENCES ops_task_tracker(id),
    batch_code          TEXT NOT NULL,
    grow_cycle_pattern_name TEXT REFERENCES grow_cycle_pattern(name),
    grow_trial_type_name  TEXT REFERENCES grow_trial_type(name),
    grow_lettuce_seed_mix_name    TEXT REFERENCES grow_lettuce_seed_mix(name),
    invnt_item_name       TEXT REFERENCES invnt_item(name),
    invnt_lot_id        TEXT REFERENCES invnt_lot(id),
    seeding_uom         TEXT NOT NULL REFERENCES sys_uom(code),
    number_of_units     INTEGER NOT NULL,
    seeds_per_unit      INTEGER NOT NULL,
    number_of_rows      INTEGER NOT NULL,
    seeding_date        DATE NOT NULL,
    transplant_date     DATE NOT NULL,
    estimated_harvest_date DATE NOT NULL,
    status              TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'seeded', 'transplanted', 'harvesting', 'harvested')),
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_lettuce_seed_batch UNIQUE (org_id, batch_code),
    CONSTRAINT chk_grow_lettuce_seed_batch_source CHECK (
        (invnt_item_name IS NOT NULL AND grow_lettuce_seed_mix_name IS NULL)
        OR (invnt_item_name IS NULL AND grow_lettuce_seed_mix_name IS NOT NULL)
    )
);

COMMENT ON TABLE grow_lettuce_seed_batch IS 'Lettuce seeding batch linked to an ops activity. Either a single seed item or a seed mix, never both. Cuke seeding lives in grow_cuke_seed_batch.';

COMMENT ON COLUMN grow_lettuce_seed_batch.site_id IS 'Filtered to org_site where category = growing (subcategory: nursery, greenhouse, or pond)';
COMMENT ON COLUMN grow_lettuce_seed_batch.batch_code IS 'System-generated traceability code; carries through to harvesting; editable';
COMMENT ON COLUMN grow_lettuce_seed_batch.grow_cycle_pattern_name IS 'Describes the cycle pattern (e.g. 18/17/17 harvest pattern); does not drive calculations';
COMMENT ON COLUMN grow_lettuce_seed_batch.grow_trial_type_name IS 'Null if not a trial; set when testing a new lot, variety, or seed source';
COMMENT ON COLUMN grow_lettuce_seed_batch.grow_lettuce_seed_mix_name IS 'Set when seeding a mix; null when seeding a single variety. Mutually exclusive with invnt_item_name';
COMMENT ON COLUMN grow_lettuce_seed_batch.invnt_item_name IS 'Set when seeding a single seed item; null when seeding a mix. Mutually exclusive with grow_lettuce_seed_mix_name';
COMMENT ON COLUMN grow_lettuce_seed_batch.invnt_lot_id IS 'Only when invnt_item_name is set; sourced from invnt_lot filtered by the selected item';
COMMENT ON COLUMN grow_lettuce_seed_batch.seeding_uom IS 'Unit for number_of_units (e.g. board, flat, tray)';
COMMENT ON COLUMN grow_lettuce_seed_batch.transplant_date IS 'Planned or actual transplant date';
COMMENT ON COLUMN grow_lettuce_seed_batch.estimated_harvest_date IS 'User-selected estimated harvest date';
COMMENT ON COLUMN grow_lettuce_seed_batch.status IS 'Auto-set: planned (seeding_date > today), seeded (seeding_date <= today < transplant_date), transplanted (transplant_date <= today < estimated_harvest_date), harvesting (estimated_harvest_date <= today), harvested (manually set when complete)';

CREATE INDEX idx_grow_lettuce_seed_batch_org ON grow_lettuce_seed_batch (org_id);
CREATE INDEX idx_grow_lettuce_seed_batch_tracker ON grow_lettuce_seed_batch (ops_task_tracker_id);
CREATE INDEX idx_grow_lettuce_seed_batch_item ON grow_lettuce_seed_batch (invnt_item_name);
CREATE INDEX idx_grow_lettuce_seed_batch_mix ON grow_lettuce_seed_batch (grow_lettuce_seed_mix_name);
