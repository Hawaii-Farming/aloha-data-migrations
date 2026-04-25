CREATE TABLE IF NOT EXISTS sys_access_level (
    name       TEXT PRIMARY KEY,
    level         INTEGER NOT NULL UNIQUE,
    description   TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    TEXT,
    is_deleted    BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_sys_access_level_name UNIQUE (name)
);

COMMENT ON TABLE sys_access_level IS 'System-level lookup defining the access levels available for employee roles. The level integer is used to compare against sys_sub_module.sys_access_level_name for visibility control.';
COMMENT ON COLUMN sys_access_level.name IS 'Human-readable identifier (e.g. employee, team_lead, manager, admin, owner)';

-- --------------------------------------------------------------------
-- Grants for authenticated role (workspace shell / sys_navigation view)
-- --------------------------------------------------------------------
GRANT SELECT ON public.sys_access_level TO authenticated;
