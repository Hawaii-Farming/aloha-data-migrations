CREATE TABLE IF NOT EXISTS maint_request (
    org_id                    TEXT        NOT NULL REFERENCES org(id),
    id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                   TEXT        REFERENCES org_farm(name),
    site_id                   TEXT        REFERENCES org_site(id),
    equipment_name              TEXT        REFERENCES org_equipment(name),
    CHECK ((site_id IS NOT NULL AND equipment_name IS NULL) OR (site_id IS NULL AND equipment_name IS NOT NULL)),

    status                    TEXT        NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'pending', 'priority', 'done')),
    request_description       TEXT,
    recurring_frequency       TEXT        CHECK (recurring_frequency IN ('daily', 'weekly', 'monthly', 'quarterly', 'semi_annually', 'annually')),
    due_date                  DATE,
    completed_at              TIMESTAMPTZ,
    fixer_name                  TEXT,
    fixer_description         TEXT,

    requested_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    requested_by              TEXT        NOT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                TEXT,
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                TEXT,
    is_deleted                 BOOLEAN     NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_maint_request_fixer
      FOREIGN KEY (fixer_name) REFERENCES hr_employee(name),
    CONSTRAINT fk_maint_request_requested_by
      FOREIGN KEY (requested_by) REFERENCES hr_employee(name)
);

COMMENT ON TABLE maint_request IS 'Standalone maintenance work order requests. Each request targets either a site or equipment, never both. Equipment location is derived from org_equipment.site_id. Preventive maintenance is indicated by recurring_frequency being set.';

CREATE INDEX idx_maint_request_org_id  ON maint_request (org_id);
CREATE INDEX idx_maint_request_site    ON maint_request (site_id);
CREATE INDEX idx_maint_request_status  ON maint_request (org_id, status);
CREATE INDEX idx_maint_request_fixer   ON maint_request (fixer_name);
CREATE INDEX idx_maint_request_due     ON maint_request (org_id, due_date);

COMMENT ON COLUMN maint_request.site_id IS 'Any org_site regardless of category; set for site-specific requests, null for equipment requests';
COMMENT ON COLUMN maint_request.equipment_name IS 'The equipment needing maintenance; set for equipment requests, null for site requests';
COMMENT ON COLUMN maint_request.status IS 'new, pending, priority, done';
COMMENT ON COLUMN maint_request.recurring_frequency IS 'daily, weekly, monthly, quarterly, semi_annually, annually; null means not recurring; non-null implies preventive maintenance; auto-creates a new request after status is marked done';
