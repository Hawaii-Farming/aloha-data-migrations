CREATE TABLE IF NOT EXISTS grow_cuke_seed_batch (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT NOT NULL REFERENCES org_farm(name),
    site_id                 TEXT REFERENCES org_site_cuke_gh(id),
    -- ops_task_tracker_id and invnt_lot_id intentionally carry no FK: both
    -- parent tables are TRUNCATEd nightly and CASCADE would wipe this
    -- static/forward-planned plant-map table with no nightly re-populator.
    ops_task_tracker_id     UUID,
    grow_trial_type_id      TEXT REFERENCES grow_trial_type(id),
    invnt_item_id           TEXT REFERENCES invnt_item(id),
    invnt_lot_id            TEXT,
    seeding_date            DATE NOT NULL,
    transplant_date         DATE NOT NULL,
    next_bag_change_date    DATE,
    rows_4_per_bag          INTEGER NOT NULL DEFAULT 0,
    rows_5_per_bag          INTEGER NOT NULL DEFAULT 0,
    seeds                   INTEGER NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'seeded', 'transplanted', 'harvesting', 'harvested')),
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_cuke_seed_batch IS 'Cuke seeding cycle record. One row per variety per greenhouse per seeding event. Holds historical and forward-planned cycles. Snapshot fields (rows_4_per_bag, rows_5_per_bag, seeds) are frozen at seeding time from the plant map and not recomputed.';

COMMENT ON COLUMN grow_cuke_seed_batch.site_id IS 'Greenhouse being seeded; filtered to org_site where subcategory = greenhouse';
COMMENT ON COLUMN grow_cuke_seed_batch.grow_trial_type_id IS 'Null if not a trial; set when testing a new lot, variety, or seed source';
COMMENT ON COLUMN grow_cuke_seed_batch.invnt_item_id IS 'Specific seed cultivar used for this cycle (e.g. delta_star_minis_rz). Variety (k/j/e) is derivable via invnt_item.grow_variety_id';
COMMENT ON COLUMN grow_cuke_seed_batch.invnt_lot_id IS 'Lot number for the cultivar. References invnt_lot filtered by invnt_item_id';
COMMENT ON COLUMN grow_cuke_seed_batch.seeding_date IS 'Actual planting date. For future cycles this is the planned date. Dashboard derives ISO week from this';
COMMENT ON COLUMN grow_cuke_seed_batch.transplant_date IS 'Planned or actual date transplant crew moves seedlings into the greenhouse';
COMMENT ON COLUMN grow_cuke_seed_batch.next_bag_change_date IS 'Scheduled bag-swap date for this cycle. Null if not yet scheduled';
COMMENT ON COLUMN grow_cuke_seed_batch.rows_4_per_bag IS 'Snapshot: number of physical GH rows at 4 plants per bag for this variety this cycle. Populated from the plant map at seeding time. -1 indicates historical data imported before the snapshot was tracked';
COMMENT ON COLUMN grow_cuke_seed_batch.rows_5_per_bag IS 'Snapshot: number of physical GH rows at 5 plants per bag for this variety this cycle. Populated from the plant map at seeding time. -1 indicates historical data imported before the snapshot was tracked';
COMMENT ON COLUMN grow_cuke_seed_batch.seeds IS 'Total seeds sown for this variety this cycle. Calculated at seeding time';
COMMENT ON COLUMN grow_cuke_seed_batch.status IS 'Auto-set: planned (seeding_date > today), seeded (seeding_date <= today < transplant_date), transplanted (transplant_date <= today < estimated_harvest_date), harvesting, harvested (manually set when complete)';

CREATE INDEX idx_grow_cuke_seed_batch_org ON grow_cuke_seed_batch (org_id);
CREATE INDEX idx_grow_cuke_seed_batch_site_date ON grow_cuke_seed_batch (site_id, seeding_date);
CREATE INDEX idx_grow_cuke_seed_batch_date ON grow_cuke_seed_batch (seeding_date);
CREATE INDEX idx_grow_cuke_seed_batch_item ON grow_cuke_seed_batch (invnt_item_id);
CREATE INDEX idx_grow_cuke_seed_batch_tracker ON grow_cuke_seed_batch (ops_task_tracker_id);
