CREATE TABLE IF NOT EXISTS org_site_gh_row (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL REFERENCES org_farm(id),
    site_id             TEXT NOT NULL REFERENCES org_site(id),
    row_num             INTEGER NOT NULL,
    num_bags_capacity   INTEGER NOT NULL,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_site_gh_row_site_row UNIQUE (site_id, row_num)
);

COMMENT ON TABLE org_site_gh_row IS 'Physical greenhouse row infrastructure. One row per physical GH row. Crop-agnostic and rendering-agnostic — referenced by seeding, scouting, maintenance, and spraying activities when they target a specific row. Block membership and render order are defined in org_site_gh_block.';

COMMENT ON COLUMN org_site_gh_row.row_num IS 'Physical row number. Unique within a greenhouse. Used on labels and for crew navigation. Block membership is derived by joining to org_site_gh_block on site_id where row_num is between row_num_from and row_num_to';
COMMENT ON COLUMN org_site_gh_row.num_bags_capacity IS 'Maximum number of grow bags that physically fit in this row. Rows are always planted to full capacity. When a row is split between two varieties, each variety occupies capacity/2 bags';

CREATE INDEX idx_org_site_gh_row_site ON org_site_gh_row (site_id);
CREATE INDEX idx_org_site_gh_row_org ON org_site_gh_row (org_id);
