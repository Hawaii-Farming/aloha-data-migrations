CREATE TABLE IF NOT EXISTS pack_lot (
    org_id          TEXT NOT NULL REFERENCES org(id),
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name         TEXT NOT NULL REFERENCES org_farm(name),

    lot_number      TEXT NOT NULL,
    harvest_date    DATE,
    pack_date       DATE NOT NULL,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_pack_lot UNIQUE (org_id, lot_number)
);

COMMENT ON TABLE pack_lot IS 'Production lot header. One row per lot. The same lot number is shared across all products packed on the same day.';

COMMENT ON COLUMN pack_lot.lot_number IS 'System-generated from pack_date; editable by user';
COMMENT ON COLUMN pack_lot.harvest_date IS 'Optional; user-selected to track which harvest this lot came from';

CREATE INDEX idx_pack_lot_org_id  ON pack_lot (org_id);
CREATE INDEX idx_pack_lot_farm_id ON pack_lot (farm_name);

