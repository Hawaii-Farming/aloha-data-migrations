CREATE TABLE IF NOT EXISTS hr_module_access (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    hr_employee_id  TEXT NOT NULL REFERENCES hr_employee(id),
    sys_module_id   TEXT NOT NULL,
    is_enabled      BOOLEAN NOT NULL DEFAULT true,
    can_edit        BOOLEAN NOT NULL DEFAULT true,
    can_delete      BOOLEAN NOT NULL DEFAULT false,
    can_verify      BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_hr_module_access UNIQUE (hr_employee_id, sys_module_id),
    CONSTRAINT hr_module_access_org_module_fkey
      FOREIGN KEY (org_id, sys_module_id) REFERENCES org_module(org_id, sys_module_id)
);

COMMENT ON TABLE hr_module_access IS 'Controls which modules each employee can access. One row per employee per module; is_enabled toggles access without deleting the record. Composite FK (org_id, sys_module_id) into org_module.';

COMMENT ON COLUMN hr_module_access.sys_module_id IS 'Module identifier matching sys_module.id and the org_module row for the same org_id; identifies which module this access record controls.';
COMMENT ON COLUMN hr_module_access.is_enabled IS 'Pre-filled from org_module.is_enabled when employee access is seeded; editable per employee';
COMMENT ON COLUMN hr_module_access.can_edit IS 'Auto-set to true when provisioned; drives frontend edit-button rendering';
COMMENT ON COLUMN hr_module_access.can_delete IS 'Auto-set to false when provisioned; drives frontend delete-button rendering';
COMMENT ON COLUMN hr_module_access.can_verify IS 'Auto-set to false when provisioned; drives frontend verify-button rendering';

CREATE INDEX idx_hr_module_access_employee ON hr_module_access (hr_employee_id);
CREATE INDEX idx_hr_module_access_module ON hr_module_access (org_id, sys_module_id);

-- --------------------------------------------------------------------
-- Grants + composite index for the hr_rba_navigation view join
-- (defined in 20260401000031_hr_rba_navigation.sql).
-- --------------------------------------------------------------------
GRANT SELECT ON public.hr_module_access TO authenticated;

CREATE INDEX IF NOT EXISTS idx_hr_module_access_employee_module
  ON public.hr_module_access(hr_employee_id, sys_module_id);
