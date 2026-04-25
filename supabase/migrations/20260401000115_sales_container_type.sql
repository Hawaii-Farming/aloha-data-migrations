CREATE TABLE IF NOT EXISTS sales_container_type (
    name       TEXT PRIMARY KEY,
    org_id                  TEXT NOT NULL REFERENCES org(id),
    maximum_spaces          INTEGER NOT NULL,
    is_active               BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sales_container_type UNIQUE (org_id, name)
);

COMMENT ON TABLE sales_container_type IS 'Lookup table for shipping container types. Defines the available container types and their maximum pallet space capacity.';
