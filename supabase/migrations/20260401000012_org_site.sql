CREATE TABLE IF NOT EXISTS org_site (
    id                      TEXT PRIMARY KEY,
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT,
    name                    TEXT NOT NULL,
    org_site_category_id    TEXT NOT NULL,
    org_site_subcategory_id TEXT,
    site_id_parent          TEXT REFERENCES org_site(id),

    -- Growing site details (shown when category = growing)
    acres                   NUMERIC,
    monitoring_stations     JSONB NOT NULL DEFAULT '[]',

    -- Food safety details (shown for food safety child sites)
    zone                    TEXT CHECK (zone IN ('Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Water')),

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
      FOREIGN KEY (org_site_subcategory_id) REFERENCES org_site_category(id),
    CONSTRAINT org_site_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE org_site IS 'Site register for growing sites, packhouses, and food-safety zones. Supports parent-child hierarchy via site_id_parent. Cuke greenhouses and housing facilities live in their own dedicated standalone tables (org_site_cuke_gh, org_site_housing).';

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
