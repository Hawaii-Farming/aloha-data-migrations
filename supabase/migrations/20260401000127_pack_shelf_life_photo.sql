CREATE TABLE IF NOT EXISTS pack_shelf_life_photo (
    org_id                      TEXT NOT NULL REFERENCES org(id),
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                     TEXT REFERENCES org_farm(name),
    pack_shelf_life_id    UUID NOT NULL REFERENCES pack_shelf_life(id),

    observation_date            DATE NOT NULL,
    shelf_life_day              INTEGER NOT NULL,
    side                 TEXT NOT NULL CHECK (side IN ('top', 'side', 'bottom')),
    photo_url                   TEXT NOT NULL,
    caption                     TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                   BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE pack_shelf_life_photo IS 'Photos taken during a shelf life trial observation. Multiple photos per observation date per trial.';

COMMENT ON COLUMN pack_shelf_life_photo.side IS 'top, side, bottom';
COMMENT ON COLUMN pack_shelf_life_photo.shelf_life_day IS 'Auto-calculated: observation_date minus pack_lot.pack_date';

CREATE INDEX idx_pack_shelf_life_photo_org_id ON pack_shelf_life_photo (org_id);
CREATE INDEX idx_pack_shelf_life_photo_trial  ON pack_shelf_life_photo (pack_shelf_life_id);

