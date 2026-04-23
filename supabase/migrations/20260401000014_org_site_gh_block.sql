CREATE TABLE IF NOT EXISTS org_site_gh_block (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL REFERENCES org_farm(id),
    site_id         TEXT NOT NULL REFERENCES org_site(id),
    block_num       INTEGER NOT NULL,
    name            TEXT NOT NULL,
    row_num_from    INTEGER NOT NULL,
    row_num_to      INTEGER NOT NULL,
    direction       TEXT NOT NULL CHECK (direction IN ('forward', 'reverse')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_site_gh_block_site_block UNIQUE (site_id, block_num)
);

COMMENT ON TABLE org_site_gh_block IS 'Block definitions per greenhouse. A block is a visually contiguous group of rows rendered together on the dashboard. Sidewalks render between blocks. GHs with no side divisions have a single block covering all rows.';

COMMENT ON COLUMN org_site_gh_block.block_num IS 'Block sequence (1, 2, 3...). The dashboard renders blocks in ascending block_num, with sidewalks between them';
COMMENT ON COLUMN org_site_gh_block.name IS 'Display label for the block header on the plant-map dashboard (e.g. North, Middle, South, East, West, Hamakua, Kohala, Main). For GHs that contain multiple physical structures sharing one org_site (HK = Hamakua+Kohala), each structure gets its own block with a distinct name';
COMMENT ON COLUMN org_site_gh_block.row_num_from IS 'First row_num in this block (inclusive). Block membership is defined by row_num range: a row belongs to the block where row_num_from <= row_num <= row_num_to';
COMMENT ON COLUMN org_site_gh_block.row_num_to IS 'Last row_num in this block (inclusive)';
COMMENT ON COLUMN org_site_gh_block.direction IS 'forward = rows render in ascending row_num order within the block. reverse = rows render in descending row_num order';

CREATE INDEX idx_org_site_gh_block_site ON org_site_gh_block (site_id);
CREATE INDEX idx_org_site_gh_block_org ON org_site_gh_block (org_id);
