CREATE TABLE IF NOT EXISTS grow_lettuce_seed_mix_item (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_name         TEXT NOT NULL REFERENCES org_farm(name),
    grow_lettuce_seed_mix_id TEXT NOT NULL REFERENCES grow_lettuce_seed_mix(id),
    invnt_item_id   TEXT NOT NULL REFERENCES invnt_item(id),
    invnt_lot_id    TEXT REFERENCES invnt_lot(id),
    percentage      NUMERIC NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_lettuce_seed_mix_item UNIQUE (grow_lettuce_seed_mix_id, invnt_item_id)
);

COMMENT ON TABLE grow_lettuce_seed_mix_item IS 'Individual seed items within a mix recipe with their proportion. Each row defines one seed and its percentage in the blend.';

COMMENT ON COLUMN grow_lettuce_seed_mix_item.invnt_lot_id IS 'Sourced from invnt_lot filtered by the selected invnt_item_id';
COMMENT ON COLUMN grow_lettuce_seed_mix_item.percentage IS 'Proportion in the mix (e.g. 0.6 for 60%); all items in a mix should sum to 1.0';

