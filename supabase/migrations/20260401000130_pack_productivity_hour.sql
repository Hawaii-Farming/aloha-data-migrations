CREATE TABLE IF NOT EXISTS pack_productivity_hour (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_name                 TEXT NOT NULL REFERENCES org_farm(name),
    ops_task_tracker_id     UUID NOT NULL REFERENCES ops_task_tracker(id),
    pack_end_hour               TIMESTAMPTZ NOT NULL,

    -- Crew counts by role
    catchers                INTEGER NOT NULL DEFAULT 0,
    packers                 INTEGER NOT NULL DEFAULT 0,
    mixers                  INTEGER NOT NULL DEFAULT 0,
    boxers                  INTEGER NOT NULL DEFAULT 0,

    cases_packed            INTEGER NOT NULL DEFAULT 0,

    -- Quality & status
    leftover_pounds         NUMERIC NOT NULL DEFAULT 0,
    fsafe_metal_detected_at TIMESTAMPTZ,
    notes                   TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pack_productivity_hour IS 'Hourly pack line productivity snapshot. One row per hour per packing session. Product is on ops_task_tracker.sales_product_id. Derived metrics: trays = cases_packed × product.pack_per_case, trays_per_packer_per_minute = trays / (packers × 60), pounds = cases_packed × product.case_net_weight.';

COMMENT ON COLUMN pack_productivity_hour.pack_end_hour IS 'The hour being recorded (e.g. 2026-03-26 11:00); one row per clock hour';
COMMENT ON COLUMN pack_productivity_hour.fsafe_metal_detected_at IS 'Timestamp of food safety metal detection check during this packing hour; null means no detection was recorded';

CREATE INDEX idx_pack_productivity_hour_tracker ON pack_productivity_hour (ops_task_tracker_id);
CREATE INDEX idx_pack_productivity_hour_date ON pack_productivity_hour (org_id, pack_end_hour);
CREATE UNIQUE INDEX uq_pack_productivity_hour ON pack_productivity_hour (ops_task_tracker_id, pack_end_hour);
