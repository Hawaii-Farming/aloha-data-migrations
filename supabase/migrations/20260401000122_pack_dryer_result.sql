CREATE TABLE IF NOT EXISTS pack_dryer_result (
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                          TEXT NOT NULL REFERENCES org(id),
    farm_id                         TEXT NOT NULL REFERENCES org_farm(id),
    site_id                         TEXT NOT NULL REFERENCES org_site(id),
    grow_lettuce_seed_batch_id      UUID REFERENCES grow_lettuce_seed_batch(id),
    invnt_item_id                   TEXT REFERENCES invnt_item(id),

    check_at                        TIMESTAMPTZ NOT NULL,
    temperature_uom                 TEXT NOT NULL REFERENCES sys_uom(code),
    dryer_temperature               NUMERIC,
    greenhouse_temperature          NUMERIC,
    packhouse_temperature           NUMERIC,
    pre_packing_leaf_temperature    NUMERIC,
    moisture_uom                    TEXT NOT NULL REFERENCES sys_uom(code),
    moisture_before_dryer           NUMERIC,
    moisture_after_dryer            NUMERIC,
    belt_speed                      NUMERIC,
    tracking_code                   TEXT,
    pack_dryer_result_id_original   UUID REFERENCES pack_dryer_result(id),
    notes                           TEXT,

    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                      BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pack_dryer_result IS 'Environmental and moisture readings taken during the packing process. One row per check at a specific time, tracking temperature and moisture conditions before and after the dryer.';

COMMENT ON COLUMN pack_dryer_result.tracking_code IS 'Human-readable code identifying this check for re-tracking';
COMMENT ON COLUMN pack_dryer_result.pack_dryer_result_id_original IS 'Self-referencing FK to the original check when this row is a re-check';

CREATE INDEX idx_pack_dryer_result_org    ON pack_dryer_result (org_id);
CREATE INDEX idx_pack_dryer_result_farm   ON pack_dryer_result (farm_id);
CREATE INDEX idx_pack_dryer_result_batch  ON pack_dryer_result (grow_lettuce_seed_batch_id);
CREATE INDEX idx_pack_dryer_result_date     ON pack_dryer_result (check_at);
CREATE INDEX idx_pack_dryer_result_original ON pack_dryer_result (pack_dryer_result_id_original);
