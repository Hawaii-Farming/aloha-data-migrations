CREATE TABLE IF NOT EXISTS sys_sub_module (
    id                TEXT PRIMARY KEY,
    sys_module_id  TEXT NOT NULL REFERENCES sys_module(name),
    name              TEXT NOT NULL,
    description       TEXT,
    sys_access_level_id  TEXT NOT NULL REFERENCES sys_access_level(name),
    display_order     INTEGER NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        TEXT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        TEXT,
    is_deleted        BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sys_sub_module UNIQUE (sys_module_id, name)
);

COMMENT ON TABLE sys_sub_module IS 'System-level lookup defining sub-modules within each module. sys_access_level_id determines the minimum employee access level required to see this sub-module.';

COMMENT ON COLUMN sys_sub_module.sys_access_level_id IS 'Sourced from sys_access_level; defines the minimum access level required to view this sub-module';

-- --------------------------------------------------------------------
-- Grants for authenticated role (workspace shell / sys_navigation view)
-- --------------------------------------------------------------------
GRANT SELECT ON public.sys_sub_module TO authenticated;
