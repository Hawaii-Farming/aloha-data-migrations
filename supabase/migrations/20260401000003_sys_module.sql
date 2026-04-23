CREATE TABLE IF NOT EXISTS sys_module (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sys_module_name UNIQUE (name)
);

COMMENT ON TABLE sys_module IS 'System-level lookup defining the application modules available for access control (e.g. Inventory, HR, Operations, Pack, Sales, Maintenance, Food Safety).';
COMMENT ON COLUMN sys_module.id IS 'Human-readable identifier derived from module name (e.g. inventory, human_resources)';
