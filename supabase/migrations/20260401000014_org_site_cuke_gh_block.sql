CREATE TABLE IF NOT EXISTS org_site_cuke_gh_block (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_name         TEXT NOT NULL REFERENCES org_farm(name),
    site_id         TEXT NOT NULL REFERENCES org_site_cuke_gh(id),
    block_number       INTEGER NOT NULL,
    name            TEXT NOT NULL,
    row_number_from    INTEGER NOT NULL,
    row_number_to      INTEGER NOT NULL,
    direction       TEXT NOT NULL CHECK (direction IN ('forward', 'reverse')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_site_cuke_gh_block_site_block UNIQUE (site_id, block_number)
);

COMMENT ON TABLE org_site_cuke_gh_block IS 'Block definitions per greenhouse. A block is a visually contiguous group of rows rendered together on the dashboard. Sidewalks render between blocks. GHs with no side divisions have a single block covering all rows.';

COMMENT ON COLUMN org_site_cuke_gh_block.block_number IS 'Block sequence (1, 2, 3...). The dashboard renders blocks in ascending block_number, with sidewalks between them';
COMMENT ON COLUMN org_site_cuke_gh_block.name IS 'Display label for the block header on the plant-map dashboard (e.g. North, Middle, South, East, West, Hamakua, Kohala, Main). For GHs that contain multiple physical structures sharing one org_site (HK = Hamakua+Kohala), each structure gets its own block with a distinct name';
COMMENT ON COLUMN org_site_cuke_gh_block.row_number_from IS 'First row_number in this block (inclusive). Block membership is defined by row_number range: a row belongs to the block where row_number_from <= row_number <= row_number_to';
COMMENT ON COLUMN org_site_cuke_gh_block.row_number_to IS 'Last row_number in this block (inclusive)';
COMMENT ON COLUMN org_site_cuke_gh_block.direction IS 'forward = rows render in ascending row_number order within the block. reverse = rows render in descending row_number order';

CREATE INDEX idx_org_site_cuke_gh_block_site ON org_site_cuke_gh_block (site_id);
CREATE INDEX idx_org_site_cuke_gh_block_org ON org_site_cuke_gh_block (org_id);
