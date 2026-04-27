CREATE TABLE IF NOT EXISTS sales_product (
    id                       TEXT PRIMARY KEY,
    org_id                     TEXT NOT NULL REFERENCES org(id),
    farm_id                    TEXT NOT NULL REFERENCES org_farm(id),
    grow_grade_id              TEXT REFERENCES grow_grade(id),
    name                       TEXT NOT NULL,
    description                TEXT,
    invnt_item_id         TEXT REFERENCES invnt_item(id),

    -- Packaging hierarchy: item -> pack -> case -> pallet
    item_uom                   TEXT REFERENCES sys_uom(id),
    pack_uom                   TEXT REFERENCES sys_uom(id),
    item_per_pack              NUMERIC,
    pack_per_case              NUMERIC,
    maximum_case_per_pallet    NUMERIC,

    -- Net weights (all in weight_uom)
    weight_uom                 TEXT REFERENCES sys_uom(id),
    pack_net_weight            NUMERIC,
    case_net_weight            NUMERIC,
    pallet_net_weight          NUMERIC,

    -- Case dimensions (all in dimension_uom)
    dimension_uom              TEXT REFERENCES sys_uom(id),
    case_length                NUMERIC,
    case_width                 NUMERIC,
    case_height                NUMERIC,

    -- Storage & shelf life
    manufacturer_storage_method TEXT,
    temperature_uom            TEXT REFERENCES sys_uom(id),
    minimum_storage_temperature NUMERIC,
    maximum_storage_temperature NUMERIC,
    shelf_life_days            INT,

    -- Pallet
    pallet_ti                  NUMERIC,
    pallet_hi                  NUMERIC,
    shipping_requirements      TEXT,

    -- Flags
    is_catch_weight            BOOLEAN NOT NULL DEFAULT false,
    is_hazardous               BOOLEAN NOT NULL DEFAULT false,
    is_fsma_traceable          BOOLEAN NOT NULL DEFAULT false,

    -- Identification
    gtin                       TEXT,
    upc                        TEXT,

    photos                     JSONB NOT NULL DEFAULT '[]',
    display_order              INTEGER NOT NULL DEFAULT 0,
    is_active                  BOOLEAN NOT NULL DEFAULT true,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                 TEXT,
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                 TEXT,
    is_deleted                 BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_product_name UNIQUE (farm_id, name)
);

COMMENT ON TABLE sales_product IS 'The sellable products from each farm. Combines a grade with a full packaging hierarchy (item → pack → case → pallet). The sale unit is always a case; the shipping unit is always a pallet.';

CREATE INDEX idx_sales_product_farm_id ON sales_product (farm_id);

COMMENT ON COLUMN sales_product.invnt_item_id IS 'Filtered to packaging items in inventory';
COMMENT ON COLUMN sales_product.item_uom IS 'Smallest countable unit of the product (e.g. count, lb, oz)';
COMMENT ON COLUMN sales_product.pack_uom IS 'Intermediate packaging unit (e.g. bag, tray)';
COMMENT ON COLUMN sales_product.item_per_pack IS 'Number of items per pack unit';
COMMENT ON COLUMN sales_product.pack_per_case IS 'Number of pack units per case';
COMMENT ON COLUMN sales_product.maximum_case_per_pallet IS 'Maximum number of cases that fit on a pallet';
COMMENT ON COLUMN sales_product.weight_uom IS 'Unit for all net weight fields (e.g. lb, kg)';
COMMENT ON COLUMN sales_product.dimension_uom IS 'Unit for all case dimension fields (e.g. in, cm)';
COMMENT ON COLUMN sales_product.temperature_uom IS 'Unit for storage temperature fields (e.g. °F, °C)';
COMMENT ON COLUMN sales_product.shelf_life_days IS 'Expected shelf life in days from pack date; used to auto-calculate best_by_date on pack_lot_item';
COMMENT ON COLUMN sales_product.pallet_ti IS 'Pallet tier — number of cases per layer on pallet';
COMMENT ON COLUMN sales_product.pallet_hi IS 'Pallet high — number of layers stacked on pallet';
COMMENT ON COLUMN sales_product.is_catch_weight IS 'Whether sold by actual weight rather than fixed unit count';
COMMENT ON COLUMN sales_product.is_fsma_traceable IS 'Whether this product requires FSMA traceability documentation';
COMMENT ON COLUMN sales_product.gtin IS 'Global Trade Item Number for supply chain identification';
COMMENT ON COLUMN sales_product.upc IS 'Universal Product Code for retail scanning';
