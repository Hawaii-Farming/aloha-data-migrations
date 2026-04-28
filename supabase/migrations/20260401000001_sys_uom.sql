CREATE TABLE IF NOT EXISTS sys_uom (
    id         TEXT PRIMARY KEY,
    category     TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by   TEXT,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   TEXT,
    is_deleted    BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE sys_uom IS 'Standardized measurement units shared across all organizations for consistent data entry and calculations throughout the system.';

CREATE INDEX idx_sys_uom_category ON sys_uom (category);
