CREATE TABLE IF NOT EXISTS pack_productivity_fail_category (
    id       TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT REFERENCES org_farm(id),
    description     TEXT,
    display_order   INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pack_productivity_fail_category IS 'Lookup for pack line fail categories (e.g. film, tray, printer, leaves, ridges). Used to classify fails per hour in pack_productivity_hour_fail.';

CREATE UNIQUE INDEX uq_pack_productivity_fail_category_org ON pack_productivity_fail_category (org_id, id) WHERE farm_id IS NULL;
CREATE UNIQUE INDEX uq_pack_productivity_fail_category_farm ON pack_productivity_fail_category (org_id, farm_id, id) WHERE farm_id IS NOT NULL;
