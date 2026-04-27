CREATE TABLE IF NOT EXISTS grow_cuke_gh_row_planting (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT NOT NULL REFERENCES org_farm(id),
    org_site_cuke_gh_row_id      UUID NOT NULL,
    scenario                TEXT NOT NULL CHECK (scenario IN ('Current', 'Planned')),
    grow_variety_id         TEXT NOT NULL,
    grow_variety_id_2       TEXT,
    plants_per_bag          INTEGER NOT NULL CHECK (plants_per_bag IN (4, 5)),
    num_bags                INTEGER,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_cuke_gh_row_planting_row_scenario UNIQUE (org_site_cuke_gh_row_id, scenario),
    CONSTRAINT fk_grow_cuke_gh_row_planting_row
        FOREIGN KEY (org_site_cuke_gh_row_id) REFERENCES org_site_cuke_gh_row(id),
    CONSTRAINT fk_grow_cuke_gh_row_planting_variety_primary
        FOREIGN KEY (grow_variety_id) REFERENCES grow_variety(id),
    CONSTRAINT fk_grow_cuke_gh_row_planting_variety_secondary
        FOREIGN KEY (grow_variety_id_2) REFERENCES grow_variety(id)
);

COMMENT ON TABLE grow_cuke_gh_row_planting IS 'Cuke planting assignment per physical GH row. Two scenarios per row: current (live layout the transplant crew follows) and planned (proposed future layout). Rows are always planted to full capacity; split rows are always 50/50.';

COMMENT ON COLUMN grow_cuke_gh_row_planting.org_site_cuke_gh_row_id IS 'The physical row being planted. References org_site_cuke_gh_row';
COMMENT ON COLUMN grow_cuke_gh_row_planting.scenario IS 'current = live layout being followed by the transplant crew. planned = proposed future layout under review. Exactly one row per (org_site_cuke_gh_row_id, scenario)';
COMMENT ON COLUMN grow_cuke_gh_row_planting.grow_variety_id IS 'Primary variety planted in this row. If grow_variety_id_2 is null, this variety fills all num_bags. If split, it occupies num_bags / 2.';
COMMENT ON COLUMN grow_cuke_gh_row_planting.grow_variety_id_2 IS 'Second variety when the row is split 50/50. Null for non-split rows';
COMMENT ON COLUMN grow_cuke_gh_row_planting.plants_per_bag IS 'Plants per bag: 4 or 5. Applies uniformly across the row, including both varieties in a split';
COMMENT ON COLUMN grow_cuke_gh_row_planting.num_bags IS 'Bags per row for this scenario. Total plants in this row under this scenario = num_bags * plants_per_bag';

CREATE INDEX idx_grow_cuke_gh_row_planting_row ON grow_cuke_gh_row_planting (org_site_cuke_gh_row_id);
CREATE INDEX idx_grow_cuke_gh_row_planting_scenario ON grow_cuke_gh_row_planting (scenario);
CREATE INDEX idx_grow_cuke_gh_row_planting_org ON grow_cuke_gh_row_planting (org_id);
