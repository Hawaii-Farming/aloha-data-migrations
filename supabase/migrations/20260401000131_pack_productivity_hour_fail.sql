CREATE TABLE IF NOT EXISTS pack_productivity_hour_fail (
    org_id                          TEXT NOT NULL REFERENCES org(id),
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                         TEXT NOT NULL REFERENCES org_farm(name),
    pack_productivity_hour_id       UUID NOT NULL REFERENCES pack_productivity_hour(id),
    pack_productivity_fail_category_name           TEXT NOT NULL REFERENCES pack_productivity_fail_category(name),
    fail_count                      INTEGER NOT NULL DEFAULT 0,
    notes                           TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                      BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pack_productivity_hour_fail IS 'Fail counts per category per hour. Total fails for an hour = SUM(fail_count) across all categories.';

COMMENT ON COLUMN pack_productivity_hour_fail.fail_count IS 'Number of fails for this category in this hour';

CREATE INDEX idx_pack_prod_hour_fail_hour ON pack_productivity_hour_fail (pack_productivity_hour_id);
CREATE UNIQUE INDEX uq_pack_prod_hour_fail ON pack_productivity_hour_fail (pack_productivity_hour_id, pack_productivity_fail_category_name);
