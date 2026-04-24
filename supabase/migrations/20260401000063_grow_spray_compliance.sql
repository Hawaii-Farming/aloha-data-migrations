CREATE TABLE IF NOT EXISTS grow_spray_compliance (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    farm_name                     TEXT REFERENCES org_farm(name),
    invnt_item_id               TEXT REFERENCES invnt_item(id),

    -- Regulatory Information — legacy label rows often lack these fields.
    -- Keep the columns nullable so the full regulatory archive can be
    -- loaded from the Chemicals sheet without throwing away incomplete
    -- historical entries; the app guards the active/selection path on
    -- its own via effective/expiration dates + required-field checks.
    epa_registration            TEXT,
    phi_days                    INTEGER NOT NULL DEFAULT 0,
    rei_hours                   INTEGER NOT NULL DEFAULT 0,

    -- Application & Usage
    application_method          JSONB NOT NULL DEFAULT '[]',
    target_pest_disease         JSONB NOT NULL DEFAULT '[]',
    application_uom             TEXT REFERENCES sys_uom(code),
    maximum_quantity_per_acre   NUMERIC,
    burn_uom                    TEXT REFERENCES sys_uom(code),
    application_per_burn        NUMERIC NOT NULL DEFAULT 1,

    -- Label & Compliance
    label_date                  DATE,
    effective_date              DATE,
    expiration_date             DATE,
    external_label_url          TEXT NOT NULL,

    -- CRUD
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_spray_compliance IS 'Chemical label registry storing regulatory information per product. One row per chemical/fertilizer item with REI, PHI, label rates, and application restrictions.';


CREATE INDEX idx_grow_spray_compliance_item ON grow_spray_compliance (invnt_item_id);

COMMENT ON COLUMN grow_spray_compliance.invnt_item_id IS 'The chemical or fertilizer product this compliance record applies to';
COMMENT ON COLUMN grow_spray_compliance.epa_registration IS 'EPA registration number from the product label';
COMMENT ON COLUMN grow_spray_compliance.phi_days IS 'Pre-Harvest Interval in days; minimum days between last application and harvest';
COMMENT ON COLUMN grow_spray_compliance.rei_hours IS 'Restricted Entry Interval in hours; minimum hours before workers can re-enter treated area';
COMMENT ON COLUMN grow_spray_compliance.application_method IS 'JSON array of allowed application methods from the label (e.g. ["spray", "drench", "granular"])';
COMMENT ON COLUMN grow_spray_compliance.target_pest_disease IS 'JSON array of pests/diseases this product is labeled to treat';
COMMENT ON COLUMN grow_spray_compliance.maximum_quantity_per_acre IS 'Maximum label rate per acre per application; app enforces this limit on grow_spray_input';
COMMENT ON COLUMN grow_spray_compliance.burn_uom IS 'Smallest consumption unit for this product (e.g. oz, ml, g)';
COMMENT ON COLUMN grow_spray_compliance.application_per_burn IS 'Application rate expressed in burn units; used for inventory deduction';
COMMENT ON COLUMN grow_spray_compliance.label_date IS 'Date printed on the product label';
COMMENT ON COLUMN grow_spray_compliance.effective_date IS 'Date this compliance record becomes active; only the active record is shown for selection';
COMMENT ON COLUMN grow_spray_compliance.expiration_date IS 'Date this compliance record expires; null means no expiry';
COMMENT ON COLUMN grow_spray_compliance.external_label_url IS 'URL to the full product label PDF for reference';
