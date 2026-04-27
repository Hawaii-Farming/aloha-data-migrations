CREATE TABLE IF NOT EXISTS org_module (
    id      TEXT PRIMARY KEY,
    org_id            TEXT NOT NULL REFERENCES org(id),
    sys_module_id  TEXT NOT NULL REFERENCES sys_module(id),
    is_enabled        BOOLEAN NOT NULL DEFAULT true,
    display_order     INTEGER NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by        TEXT,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by        TEXT,
    is_deleted        BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_module UNIQUE (org_id, sys_module_id)
);

COMMENT ON TABLE org_module IS 'Org-scoped copy of system modules. Seeded when a new org is created. Org admins toggle is_enabled to control which modules are available to their users.';

COMMENT ON COLUMN org_module.sys_module_id IS 'Sourced from sys_module; identifies which system module this org copy represents';
COMMENT ON COLUMN org_module.id IS 'Pre-filled from sys_module.id at provisioning time; editable by org admins';
COMMENT ON COLUMN org_module.is_enabled IS 'Auto-set to true when provisioned; toggled by org admins to enable/disable the module';

CREATE INDEX idx_org_module_org ON org_module (org_id);

-- --------------------------------------------------------------------
-- Grants for authenticated role (workspace shell / sys_navigation view)
-- --------------------------------------------------------------------
GRANT SELECT ON public.org_module TO authenticated;
