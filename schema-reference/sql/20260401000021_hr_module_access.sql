CREATE TABLE IF NOT EXISTS hr_module_access (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    hr_employee_id  TEXT NOT NULL REFERENCES hr_employee(id),
    org_module_id   TEXT NOT NULL REFERENCES org_module(id),
    is_enabled      BOOLEAN NOT NULL DEFAULT true,
    can_edit        BOOLEAN NOT NULL DEFAULT true,
    can_delete      BOOLEAN NOT NULL DEFAULT false,
    can_verify      BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_hr_module_access UNIQUE (hr_employee_id, org_module_id)
);

COMMENT ON TABLE hr_module_access IS 'Controls which modules each employee can access. One row per employee per module; is_enabled toggles access without deleting the record.';

COMMENT ON COLUMN hr_module_access.org_module_id IS 'Sourced from org_module; identifies which module this access record controls';
COMMENT ON COLUMN hr_module_access.is_enabled IS 'Pre-filled from org_module.is_enabled when employee access is seeded; editable per employee';
COMMENT ON COLUMN hr_module_access.can_edit IS 'Auto-set to true when provisioned; controls whether employee can edit records in this module';
COMMENT ON COLUMN hr_module_access.can_delete IS 'Auto-set to false when provisioned; controls whether employee can delete records in this module';
COMMENT ON COLUMN hr_module_access.can_verify IS 'Auto-set to false when provisioned; controls whether employee can verify/approve records in this module';

CREATE INDEX idx_hr_module_access_employee ON hr_module_access (hr_employee_id);
CREATE INDEX idx_hr_module_access_module ON hr_module_access (org_module_id);
