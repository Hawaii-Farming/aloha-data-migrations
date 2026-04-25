CREATE TABLE IF NOT EXISTS org_site_cuke_gh (
    id                  TEXT PRIMARY KEY,
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    farm_section        TEXT NOT NULL CHECK (farm_section IN ('JTL', 'BIP')),
    acres               NUMERIC,
    rows_orientation    TEXT NOT NULL CHECK (rows_orientation IN ('vertical', 'horizontal')),
    sidewalk_position   TEXT NOT NULL CHECK (sidewalk_position IN ('middle', 'top', 'bottom', 'left', 'right', 'none')),
    blocks_vertical     BOOLEAN NOT NULL DEFAULT false,
    layout_grid_row     INTEGER NOT NULL,
    layout_grid_col     INTEGER NOT NULL,
    layout_stack_pos    INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE org_site_cuke_gh IS 'Cuke greenhouse registry — one row per GH with layout and display config for the plant-map dashboard and other GH-aware features. Standalone: id is a cuke-GH-scoped identifier and is not FK-linked to org_site.';

COMMENT ON COLUMN org_site_cuke_gh.farm_section IS 'Physical farm area this GH belongs to. JTL = numbered greenhouses (GH1-GH8); BIP = named houses (Kona, Kohala, Hamakua, Waimea, Hilo). Drives dashboard grouping and layout';
COMMENT ON COLUMN org_site_cuke_gh.acres IS 'Cultivated area of this greenhouse. Used by reporting / yield-per-acre calculations. Nullable so a GH can be registered before its acreage is measured';
COMMENT ON COLUMN org_site_cuke_gh.rows_orientation IS 'vertical = rows run top-to-bottom; horizontal = rows run left-to-right';
COMMENT ON COLUMN org_site_cuke_gh.sidewalk_position IS 'Where the sidewalk renders in the GH visual: middle, top, bottom, left, right, or none. Dashboard renders sidewalks in grey';
COMMENT ON COLUMN org_site_cuke_gh.blocks_vertical IS 'When true the renderer stacks blocks vertically instead of placing them side-by-side';
COMMENT ON COLUMN org_site_cuke_gh.layout_grid_row IS 'Dashboard grid row position. Controls top/bottom placement. GHs with lower values render higher. All GHs in the same grid row render at the same pixel height';
COMMENT ON COLUMN org_site_cuke_gh.layout_grid_col IS 'Dashboard grid column position. Controls left/right placement. JTL houses have lower values, BIP houses have higher values';
COMMENT ON COLUMN org_site_cuke_gh.layout_stack_pos IS 'When multiple GHs share the same (grid_row, grid_col), this orders them within the shared cell. Null when no stacking';

CREATE INDEX idx_org_site_cuke_gh_org ON org_site_cuke_gh (org_id);
CREATE INDEX idx_org_site_cuke_gh_farm ON org_site_cuke_gh (farm_name);
