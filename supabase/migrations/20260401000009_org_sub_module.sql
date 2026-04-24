CREATE TABLE IF NOT EXISTS org_sub_module (
    org_id                TEXT NOT NULL REFERENCES org(id),
    sys_module_name         TEXT NOT NULL REFERENCES sys_module(name),
    sys_sub_module_name  TEXT NOT NULL REFERENCES sys_sub_module(name),
    sys_access_level_name TEXT NOT NULL REFERENCES sys_access_level(name),
    name          TEXT PRIMARY KEY,
    is_enabled            BOOLEAN NOT NULL DEFAULT true,
    display_order         INTEGER NOT NULL DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by            TEXT,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by            TEXT,
    is_deleted            BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_sub_module UNIQUE (org_id, sys_module_name, sys_sub_module_name)
);

COMMENT ON TABLE org_sub_module IS 'Org-scoped copy of system sub-modules. Seeded when a new org is created. Org admins toggle is_enabled to control which sub-modules are available within each enabled module.';

COMMENT ON COLUMN org_sub_module.sys_module_name IS 'Sourced from sys_sub_module.sys_module_name at provisioning time';
COMMENT ON COLUMN org_sub_module.sys_sub_module_name IS 'Sourced from sys_sub_module; identifies which system sub-module this org copy represents';
COMMENT ON COLUMN org_sub_module.sys_access_level_name IS 'Pre-filled from sys_sub_module.sys_access_level_name at provisioning time; editable by org admins';
COMMENT ON COLUMN org_sub_module.name IS 'Pre-filled from sys_sub_module.name at provisioning time; editable by org admins';
COMMENT ON COLUMN org_sub_module.is_enabled IS 'Auto-set to true when provisioned; toggled by org admins to enable/disable the sub-module';

CREATE INDEX idx_org_sub_module_org ON org_sub_module (org_id);
CREATE INDEX idx_org_sub_module_module ON org_sub_module (sys_module_name);

-- --------------------------------------------------------------------
-- Grants for authenticated role (workspace shell / sys_navigation view)
-- --------------------------------------------------------------------
GRANT SELECT ON public.org_sub_module TO authenticated;
