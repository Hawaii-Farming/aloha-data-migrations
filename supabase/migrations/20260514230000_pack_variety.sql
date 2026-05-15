-- pack_variety: lookup for leftover-by-variety reporting (Bal box on lettuce pack page).
-- Composite PK (org_id, id) so different orgs can have different variety codes.

CREATE TABLE IF NOT EXISTS pack_variety (
    id              TEXT NOT NULL,
    org_id          TEXT NOT NULL REFERENCES org(id),
    description     TEXT,
    display_order   INTEGER NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT pk_pack_variety PRIMARY KEY (org_id, id)
);

COMMENT ON TABLE pack_variety IS 'Lookup for pack varieties used in leftover-by-variety reporting (e.g. L=Lettuce, W=Watercress, A=Arugula).';

CREATE INDEX idx_pack_variety_org_id ON pack_variety (org_id);

-- Seed L/W/A for hawaii_farming.
INSERT INTO pack_variety (org_id, id, description, display_order)
SELECT id, 'L', 'Lettuce',    10 FROM org WHERE id = 'hawaii_farming'
ON CONFLICT (org_id, id) DO NOTHING;

INSERT INTO pack_variety (org_id, id, description, display_order)
SELECT id, 'W', 'Watercress', 20 FROM org WHERE id = 'hawaii_farming'
ON CONFLICT (org_id, id) DO NOTHING;

INSERT INTO pack_variety (org_id, id, description, display_order)
SELECT id, 'A', 'Arugula',    30 FROM org WHERE id = 'hawaii_farming'
ON CONFLICT (org_id, id) DO NOTHING;
