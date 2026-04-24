CREATE TABLE IF NOT EXISTS hr_employee (

    -- =============================================
    -- IDENTITY
    -- =============================================
    id                           TEXT PRIMARY KEY,
    org_id                       TEXT NOT NULL REFERENCES org(id),

    -- =============================================
    -- EMPLOYEE PROFILE
    -- =============================================
    first_name                   TEXT NOT NULL,
    last_name                    TEXT NOT NULL,
    preferred_name               TEXT,
    gender                       TEXT CHECK (gender IN ('male', 'female')),
    date_of_birth                DATE,
    ethnicity                    TEXT DEFAULT 'Non-Caucasian' CHECK (ethnicity IN ('Caucasian', 'Non-Caucasian')),
    profile_photo_url            TEXT,

    -- =============================================
    -- CONTACT
    -- =============================================
    phone                        TEXT,
    email                        TEXT,
    company_email                TEXT,
    user_id                      UUID REFERENCES auth.users(id),
    is_primary_org               BOOLEAN NOT NULL DEFAULT false,

    -- =============================================
    -- ORGANISATION & ROLE
    -- =============================================
    hr_department_id             TEXT REFERENCES hr_department(id),
    sys_access_level_name       TEXT NOT NULL REFERENCES sys_access_level(name),
    is_manager                   BOOLEAN NOT NULL DEFAULT false,
    team_lead_id                 TEXT,
    compensation_manager_id      TEXT,

    -- =============================================
    -- EMPLOYMENT
    -- =============================================
    hr_work_authorization_id     TEXT REFERENCES hr_work_authorization(id),
    start_date                   DATE,
    end_date                     DATE,

    -- =============================================
    -- PAYROLL & COMPENSATION
    -- =============================================
    payroll_id                   TEXT,
    pay_structure                TEXT CHECK (pay_structure IN ('hourly', 'salary')),
    overtime_threshold           NUMERIC,
    wc                           TEXT,
    payroll_processor                TEXT,
    pay_delivery_method      TEXT,

    -- =============================================
    -- HOUSING
    -- =============================================
    site_id                      TEXT REFERENCES org_site_housing(id),

    -- =============================================
    -- AUDIT
    -- =============================================
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                   TEXT,
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                   TEXT,
    is_deleted                    BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_hr_employee_name UNIQUE (org_id, first_name, last_name),

    -- Named self-referential FKs so PostgREST can disambiguate them
    -- when embedding (e.g. team_lead:hr_employee!fk_hr_employee_team_lead(...))
    CONSTRAINT fk_hr_employee_team_lead
      FOREIGN KEY (team_lead_id) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_employee_compensation_manager
      FOREIGN KEY (compensation_manager_id) REFERENCES hr_employee(id)
);

COMMENT ON TABLE hr_employee IS 'Unified employee register and org membership table. Every employee gets a row here with a required sys_access_level_name that defines their role (owner, manager, team_lead, employee). Employees without app access have a null user_id. A user can belong to multiple orgs by having one row per org. Tracks employment details, management hierarchy, and compensation.';

CREATE INDEX idx_hr_employee_org_id     ON hr_employee (org_id);
CREATE INDEX idx_hr_employee_user_id    ON hr_employee (user_id);
CREATE INDEX idx_hr_employee_active     ON hr_employee (org_id, is_deleted);
CREATE INDEX idx_hr_employee_team_lead  ON hr_employee (team_lead_id);
CREATE INDEX idx_hr_employee_department ON hr_employee (hr_department_id);

COMMENT ON COLUMN hr_employee.is_primary_org IS 'When user belongs to multiple orgs, the primary org auto-loads on login; only one row per user_id should be true';
COMMENT ON COLUMN hr_employee.team_lead_id IS 'Filtered to employees with sys_access_level_name = team_lead';
COMMENT ON COLUMN hr_employee.compensation_manager_id IS 'Filtered to employees with sys_access_level_name = manager';
COMMENT ON COLUMN hr_employee.sys_access_level_name IS 'Sourced from sys_access_level; determines the employee role and module visibility';
COMMENT ON COLUMN hr_employee.overtime_threshold IS 'Hours per week before overtime applies; only relevant when pay_structure = hourly';
COMMENT ON COLUMN hr_employee.pay_structure IS 'hourly, salary';
COMMENT ON COLUMN hr_employee.wc IS 'Workers compensation code identifying the compensation plan or pay grade';
COMMENT ON COLUMN hr_employee.site_id IS 'References org_site_housing; the housing facility the employee is assigned to. Null if the employee is not housed';

-- RLS lives in 20260401000200_sys_rls_policies.sql.
