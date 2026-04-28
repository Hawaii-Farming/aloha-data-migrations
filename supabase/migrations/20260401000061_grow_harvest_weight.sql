CREATE TABLE IF NOT EXISTS grow_harvest_weight (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_id                     TEXT NOT NULL REFERENCES org_farm(id),
    site_id                     TEXT REFERENCES org_site(id),
    ops_task_tracker_id         UUID REFERENCES ops_task_tracker(id),
    grow_lettuce_seed_batch_id  UUID REFERENCES grow_lettuce_seed_batch(id),
    grow_cuke_seed_batch_id     UUID REFERENCES grow_cuke_seed_batch(id),
    grow_grade_id               TEXT REFERENCES grow_grade(id),
    harvest_date                DATE NOT NULL,
    grow_harvest_container_id   TEXT NOT NULL REFERENCES grow_harvest_container(id),
    number_of_containers        INTEGER NOT NULL,
    weight_uom                  TEXT NOT NULL REFERENCES sys_uom(id),
    gross_weight                NUMERIC NOT NULL,
    net_weight                  NUMERIC NOT NULL,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT chk_grow_harvest_weight_batch_exactly_one CHECK (
        (grow_lettuce_seed_batch_id IS NOT NULL AND grow_cuke_seed_batch_id IS NULL)
        OR
        (grow_lettuce_seed_batch_id IS NULL AND grow_cuke_seed_batch_id IS NOT NULL)
    )
);

COMMENT ON TABLE grow_harvest_weight IS 'Individual weigh-in for a harvest. One row per container type weighed. Links directly to the seeding batch for traceability. Tare is calculated on the fly from grow_harvest_container.tare_weight × number_of_containers.';

COMMENT ON COLUMN grow_harvest_weight.site_id IS 'Growing site being harvested; pre-filled from the seed batch.site_id';
COMMENT ON COLUMN grow_harvest_weight.grow_lettuce_seed_batch_id IS 'The lettuce seeding batch being harvested. Populated when farm_id = Lettuce; null for Cuke';
COMMENT ON COLUMN grow_harvest_weight.grow_cuke_seed_batch_id IS 'The cuke seeding batch being harvested. Populated when farm_id = Cuke; null for Lettuce';
COMMENT ON COLUMN grow_harvest_weight.grow_grade_id IS 'Grade assigned to this harvest (e.g. Grade A, Grade B)';
COMMENT ON COLUMN grow_harvest_weight.grow_harvest_container_id IS 'Container type used for this weigh-in; drives tare weight calculation';
COMMENT ON COLUMN grow_harvest_weight.weight_uom IS 'Pre-filled from grow_harvest_container.weight_uom; editable';
COMMENT ON COLUMN grow_harvest_weight.gross_weight IS 'Total weight on the scale including containers';
COMMENT ON COLUMN grow_harvest_weight.net_weight IS 'Auto-calculated: gross_weight minus (grow_harvest_container.tare_weight × number_of_containers)';

CREATE INDEX idx_grow_harvest_weight_tracker ON grow_harvest_weight (ops_task_tracker_id);
CREATE INDEX idx_grow_harvest_weight_lettuce_batch ON grow_harvest_weight (grow_lettuce_seed_batch_id);
CREATE INDEX idx_grow_harvest_weight_cuke_batch ON grow_harvest_weight (grow_cuke_seed_batch_id);
CREATE INDEX idx_grow_harvest_weight_container ON grow_harvest_weight (grow_harvest_container_id);
