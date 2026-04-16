CREATE TABLE IF NOT EXISTS hr_payroll (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    hr_employee_id              TEXT NOT NULL REFERENCES hr_employee(id),
    payroll_id                  TEXT NOT NULL,

    -- Pay period
    pay_period_start            DATE NOT NULL,
    pay_period_end              DATE NOT NULL,
    check_date                  DATE NOT NULL,
    invoice_number              TEXT,
    payroll_processor           TEXT NOT NULL,
    is_standard                 BOOLEAN NOT NULL DEFAULT true,

    -- Employee snapshot at time of processing
    employee_name               TEXT NOT NULL,
    hr_department_id            TEXT REFERENCES hr_department(id),
    hr_work_authorization_id    TEXT REFERENCES hr_work_authorization(id),
    wc                          TEXT,
    pay_structure               TEXT,
    hourly_rate                 NUMERIC,
    overtime_threshold          NUMERIC,

    -- Hours
    regular_hours               NUMERIC NOT NULL DEFAULT 0,
    overtime_hours              NUMERIC NOT NULL DEFAULT 0,
    discretionary_overtime_hours NUMERIC NOT NULL DEFAULT 0,
    pto_hours                   NUMERIC NOT NULL DEFAULT 0,
    total_hours                 NUMERIC NOT NULL DEFAULT 0,
    pto_hours_accrued           NUMERIC NOT NULL DEFAULT 0,

    -- Earnings
    regular_pay                 NUMERIC NOT NULL DEFAULT 0,
    overtime_pay                NUMERIC NOT NULL DEFAULT 0,
    discretionary_overtime_pay  NUMERIC NOT NULL DEFAULT 0,
    pto_pay                     NUMERIC NOT NULL DEFAULT 0,
    other_pay                   NUMERIC NOT NULL DEFAULT 0,
    bonus_pay                   NUMERIC NOT NULL DEFAULT 0,
    auto_allowance              NUMERIC NOT NULL DEFAULT 0,
    per_diem                    NUMERIC NOT NULL DEFAULT 0,
    gross_wage                  NUMERIC NOT NULL DEFAULT 0,

    -- Employee deductions
    fit                         NUMERIC NOT NULL DEFAULT 0,
    sit                         NUMERIC NOT NULL DEFAULT 0,
    social_security             NUMERIC NOT NULL DEFAULT 0,
    medicare                    NUMERIC NOT NULL DEFAULT 0,
    comp_plus                   NUMERIC NOT NULL DEFAULT 0,
    hds_dental                  NUMERIC NOT NULL DEFAULT 0,
    pre_tax_401k                NUMERIC NOT NULL DEFAULT 0,
    auto_deduction              NUMERIC NOT NULL DEFAULT 0,
    child_support               NUMERIC NOT NULL DEFAULT 0,
    program_fees                NUMERIC NOT NULL DEFAULT 0,
    net_pay                     NUMERIC NOT NULL DEFAULT 0,

    -- Employer costs
    labor_tax                   NUMERIC NOT NULL DEFAULT 0,
    other_tax                   NUMERIC NOT NULL DEFAULT 0,
    workers_compensation        NUMERIC NOT NULL DEFAULT 0,
    health_benefits             NUMERIC NOT NULL DEFAULT 0,
    other_health_charges        NUMERIC NOT NULL DEFAULT 0,
    admin_fees                  NUMERIC NOT NULL DEFAULT 0,
    hawaii_get                  NUMERIC NOT NULL DEFAULT 0,
    other_charges               NUMERIC NOT NULL DEFAULT 0,
    tdi                         NUMERIC NOT NULL DEFAULT 0,
    total_cost                  NUMERIC NOT NULL DEFAULT 0,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE hr_payroll IS 'Merged payroll data imported from external payroll processor. One row per employee per check date. Employee fields are snapshotted at time of processing to preserve historical accuracy.';

COMMENT ON COLUMN hr_payroll.payroll_id IS 'Employee ID as it appears in the payroll processor system; used to match records during import';
COMMENT ON COLUMN hr_payroll.payroll_processor IS 'Payroll processor identifier (e.g. HRB, HF)';
COMMENT ON COLUMN hr_payroll.is_standard IS 'Auto-set: true if invoice total hours > 5000; false for off-cycle or adjustment runs';
COMMENT ON COLUMN hr_payroll.employee_name IS 'Name as it appears in the payroll processor data; hr_employee_id is matched by the import script';
COMMENT ON COLUMN hr_payroll.hr_department_id IS 'Snapshot from hr_employee.hr_department_id at time of import';
COMMENT ON COLUMN hr_payroll.hr_work_authorization_id IS 'Snapshot from hr_employee.hr_work_authorization_id at time of import';
COMMENT ON COLUMN hr_payroll.wc IS 'Snapshot from hr_employee.wc at time of import';
COMMENT ON COLUMN hr_payroll.pay_structure IS 'Snapshot from hr_employee.pay_structure at time of import';
COMMENT ON COLUMN hr_payroll.hourly_rate IS 'Snapshot from payroll processor NetPay data';
COMMENT ON COLUMN hr_payroll.overtime_threshold IS 'Snapshot from hr_employee.overtime_threshold at time of import';
COMMENT ON COLUMN hr_payroll.discretionary_overtime_hours IS 'Hours worked above overtime_threshold, computed at import as GREATEST(total_hours - overtime_threshold, 0). Distinct from overtime_hours which comes from the payroll processor.';
COMMENT ON COLUMN hr_payroll.discretionary_overtime_pay IS 'Pay attributed to the discretionary overtime portion, computed at import as (discretionary_overtime_hours / overtime_hours) * overtime_pay.';
COMMENT ON COLUMN hr_payroll.fit IS 'Federal Income Tax withheld';
COMMENT ON COLUMN hr_payroll.sit IS 'State Income Tax withheld';
COMMENT ON COLUMN hr_payroll.hawaii_get IS 'Hawaii General Excise Tax';
COMMENT ON COLUMN hr_payroll.tdi IS 'Temporary Disability Insurance — employer portion';

CREATE INDEX idx_hr_payroll_org ON hr_payroll (org_id);
CREATE INDEX idx_hr_payroll_employee ON hr_payroll (hr_employee_id);
CREATE INDEX idx_hr_payroll_check_date ON hr_payroll (org_id, check_date);
CREATE INDEX idx_hr_payroll_period ON hr_payroll (org_id, pay_period_start, pay_period_end);
