CREATE TABLE IF NOT EXISTS hr_employee (
    id                           TEXT NOT NULL,
    org_id                       TEXT NOT NULL REFERENCES org(id),

    -- =============================================
    -- EMPLOYEE PROFILE
    -- =============================================
    first_name                   TEXT NOT NULL,
    last_name                    TEXT NOT NULL,
    preferred_name               TEXT,
    gender                       TEXT CHECK (gender IN ('Male', 'Female')),
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
    hr_department_id             TEXT,
    sys_access_level_id          TEXT NOT NULL REFERENCES sys_access_level(id),
    team_lead_id                 TEXT,
    compensation_manager_id      TEXT,

    -- =============================================
    -- EMPLOYMENT
    -- =============================================
    hr_work_authorization_id     TEXT,
    start_date                   DATE,
    end_date                     DATE,

    -- =============================================
    -- PAYROLL & COMPENSATION
    -- =============================================
    payroll_id                   TEXT,
    pay_structure                TEXT CHECK (pay_structure IN ('Hourly', 'Salary')),
    overtime_threshold           NUMERIC,
    wc                           TEXT,
    payroll_processor            TEXT,
    pay_delivery_method          TEXT,

    -- =============================================
    -- HOUSING
    -- =============================================
    housing_id                   TEXT REFERENCES org_site_housing(id),

    -- =============================================
    -- AUDIT
    -- =============================================
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                   TEXT,
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                   TEXT,
    is_deleted                   BOOLEAN NOT NULL DEFAULT false,

    -- Composite PK lets the same person have a row in multiple orgs
    -- without ID-namespace collisions. Linked across orgs by user_id /
    -- company_email when the employee is a real signed-in user.
    PRIMARY KEY (org_id, id),

    CONSTRAINT uq_hr_employee_name UNIQUE (org_id, first_name, last_name),

    -- Composite FKs into the now-composite-PK lookup tables
    CONSTRAINT hr_employee_hr_department_fkey
      FOREIGN KEY (org_id, hr_department_id)
      REFERENCES hr_department(org_id, id),
    CONSTRAINT hr_employee_hr_work_authorization_fkey
      FOREIGN KEY (org_id, hr_work_authorization_id)
      REFERENCES hr_work_authorization(org_id, id),

    -- Self-referential composite FKs (named so PostgREST can disambiguate
    -- when embedding e.g. team_lead:hr_employee!hr_employee_team_lead_fkey(...))
    CONSTRAINT hr_employee_team_lead_fkey
      FOREIGN KEY (org_id, team_lead_id) REFERENCES hr_employee(org_id, id),
    CONSTRAINT hr_employee_compensation_manager_fkey
      FOREIGN KEY (org_id, compensation_manager_id) REFERENCES hr_employee(org_id, id)
);

COMMENT ON TABLE hr_employee IS 'Unified employee register and org membership table. Composite PK (org_id, id) lets the same person have a row in multiple orgs without namespace collisions; the cross-org link is user_id / company_email. Every employee gets a row here with a required sys_access_level_id that defines their role (Owner, Admin, Manager, Team Lead, Employee). Employees without app access have a null user_id.';

CREATE INDEX idx_hr_employee_user_id    ON hr_employee (user_id);
CREATE INDEX idx_hr_employee_active     ON hr_employee (org_id, is_deleted);
CREATE INDEX idx_hr_employee_team_lead  ON hr_employee (org_id, team_lead_id);
CREATE INDEX idx_hr_employee_department ON hr_employee (org_id, hr_department_id);

COMMENT ON COLUMN hr_employee.is_primary_org IS 'When user belongs to multiple orgs, the primary org auto-loads on login; only one row per user_id should be true';
COMMENT ON COLUMN hr_employee.team_lead_id IS 'Filtered to employees with sys_access_level_id = team_lead';
COMMENT ON COLUMN hr_employee.compensation_manager_id IS 'Filtered to employees with sys_access_level_id = manager';
COMMENT ON COLUMN hr_employee.sys_access_level_id IS 'Sourced from sys_access_level; determines the employee role and module visibility';
COMMENT ON COLUMN hr_employee.overtime_threshold IS 'Hours per week before overtime applies; only relevant when pay_structure = hourly';
COMMENT ON COLUMN hr_employee.pay_structure IS 'hourly, salary';
COMMENT ON COLUMN hr_employee.wc IS 'Workers compensation code identifying the compensation plan or pay grade';
COMMENT ON COLUMN hr_employee.housing_id IS 'References org_site_housing; the housing facility the employee is assigned to. Null if the employee is not housed';

-- RLS lives in 20260401000200_sys_rls_policies.sql.
