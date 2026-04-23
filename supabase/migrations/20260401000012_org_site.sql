CREATE TABLE IF NOT EXISTS org_site (
    id                      TEXT PRIMARY KEY,
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT REFERENCES org_farm(id),
    name                    TEXT NOT NULL,
    org_site_category_id    TEXT NOT NULL,
    org_site_subcategory_id TEXT,
    site_id_parent          TEXT REFERENCES org_site(id),

    -- Growing site details (shown when category = growing)
    acres                   NUMERIC,
    monitoring_stations     JSONB NOT NULL DEFAULT '[]',

    -- Food safety details (shown for food safety child sites)
    zone                    TEXT CHECK (zone IN ('zone_1', 'zone_2', 'zone_3', 'zone_4', 'water')),

    -- Housing details (shown for housing sites)
    max_beds                INTEGER,

    -- Geo coordinates
    latitude                NUMERIC,
    longitude               NUMERIC,
    elevation               NUMERIC,

    notes                   TEXT,
    is_active               BOOLEAN NOT NULL DEFAULT true,
    display_order           INTEGER NOT NULL DEFAULT 0,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding org_site_category
    CONSTRAINT fk_org_site_category
      FOREIGN KEY (org_site_category_id) REFERENCES org_site_category(id),
    CONSTRAINT fk_org_site_subcategory
      FOREIGN KEY (org_site_subcategory_id) REFERENCES org_site_category(id)
);

COMMENT ON TABLE org_site IS 'Unified site register for all physical locations across the organization. Supports a parent-child hierarchy via site_id_parent — top-level sites (greenhouses, packhouses, housing) contain child sites (food safety surfaces, pest traps, rooms). The category drives which fields are relevant in the UI.';

CREATE UNIQUE INDEX uq_org_site_org_level ON org_site (org_id, name) WHERE farm_id IS NULL;
CREATE UNIQUE INDEX uq_org_site_farm_level ON org_site (org_id, farm_id, name) WHERE farm_id IS NOT NULL;

CREATE INDEX idx_org_site_org_id ON org_site (org_id);
CREATE INDEX idx_org_site_farm ON org_site (farm_id);
CREATE INDEX idx_org_site_category ON org_site (org_site_category_id);
CREATE INDEX idx_org_site_parent ON org_site (site_id_parent);

COMMENT ON COLUMN org_site.farm_id IS 'Inherited from parent org_farm when site is farm-scoped; null for org-wide sites';
COMMENT ON COLUMN org_site.monitoring_stations IS 'JSON array of station names for monitoring; rendered as dropdown in grow_monitoring_result.monitoring_station';
COMMENT ON COLUMN org_site.org_site_category_id IS 'References org_site_category rows where sub_category_name IS NULL';
COMMENT ON COLUMN org_site.org_site_subcategory_id IS 'References org_site_category rows where sub_category_name IS NOT NULL';
COMMENT ON COLUMN org_site.site_id_parent IS 'Null for top-level sites; set for child locations within a parent site (e.g. food safety surfaces, pest traps, housing rooms)';
COMMENT ON COLUMN org_site.acres IS 'Only for growing sites with no subcategory, or subcategory greenhouse, pond, nursery; null for all other site types';
COMMENT ON COLUMN org_site.zone IS 'zone_1 (food contact surface), zone_2, zone_3, zone_4, water; available on all sites regardless of category';
COMMENT ON COLUMN org_site.max_beds IS 'Maximum bed capacity for housing sites; NULL for non-housing sites';
