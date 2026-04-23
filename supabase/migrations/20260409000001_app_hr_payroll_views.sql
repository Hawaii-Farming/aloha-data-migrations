-- Payroll aggregation views for Phase 04 payroll submodules
-- Follows time-off view pattern: JOIN hr_employee for name/photo, LEFT JOIN for nullable FKs

-- View 1: Payroll by department (task grouping) per pay period
CREATE OR REPLACE VIEW app_hr_payroll_by_task AS
SELECT
    p.org_id,
    p.pay_period_start,
    p.pay_period_end,
    p.hr_department_id,
    d.name AS department_name,
    COUNT(DISTINCT p.hr_employee_id) AS employee_count,
    SUM(p.regular_hours) AS total_regular_hours,
    SUM(p.overtime_hours) AS total_overtime_hours,
    SUM(p.total_hours) AS total_hours,
    SUM(p.gross_wage) AS total_gross_wage,
    SUM(p.net_pay) AS total_net_pay
FROM hr_payroll p
LEFT JOIN hr_department d ON d.id = p.hr_department_id
WHERE p.is_deleted = false
GROUP BY p.org_id, p.pay_period_start, p.pay_period_end, p.hr_department_id, d.name;

GRANT SELECT ON app_hr_payroll_by_task TO authenticated;

-- View 2: Payroll by employee per pay period
CREATE OR REPLACE VIEW app_hr_payroll_by_employee AS
SELECT
    p.org_id,
    p.pay_period_start,
    p.pay_period_end,
    p.hr_employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    e.preferred_name,
    e.profile_photo_url,
    d.name AS department_name,
    SUM(p.regular_hours) AS total_regular_hours,
    SUM(p.overtime_hours) AS total_overtime_hours,
    SUM(p.total_hours) AS total_hours,
    SUM(p.gross_wage) AS total_gross_wage,
    SUM(p.net_pay) AS total_net_pay
FROM hr_payroll p
JOIN hr_employee e ON e.id = p.hr_employee_id
LEFT JOIN hr_department d ON d.id = p.hr_department_id
WHERE p.is_deleted = false
GROUP BY p.org_id, p.pay_period_start, p.pay_period_end, p.hr_employee_id,
         e.first_name, e.last_name, e.preferred_name, e.profile_photo_url, d.name;

GRANT SELECT ON app_hr_payroll_by_employee TO authenticated;

-- View 3: Payroll by compensation manager (detail rows per employee)
CREATE OR REPLACE VIEW app_hr_payroll_by_comp_manager AS
SELECT
    p.id,
    p.org_id,
    p.hr_employee_id,
    p.pay_period_start,
    p.pay_period_end,
    p.check_date,
    e.first_name || ' ' || e.last_name AS full_name,
    e.preferred_name,
    e.profile_photo_url,
    e.compensation_manager_id,
    cm.first_name || ' ' || cm.last_name AS compensation_manager_name,
    d.name AS department_name,
    p.regular_hours,
    p.overtime_hours,
    p.total_hours,
    p.gross_wage,
    p.net_pay
FROM hr_payroll p
JOIN hr_employee e ON e.id = p.hr_employee_id
LEFT JOIN hr_employee cm ON cm.id = e.compensation_manager_id
LEFT JOIN hr_department d ON d.id = p.hr_department_id
WHERE p.is_deleted = false;

GRANT SELECT ON app_hr_payroll_by_comp_manager TO authenticated;

-- View 4: Full payroll detail with employee and lookup joins
CREATE OR REPLACE VIEW app_hr_payroll_detail AS
SELECT
    p.id,
    p.org_id,
    p.hr_employee_id,
    p.payroll_id,
    p.pay_period_start,
    p.pay_period_end,
    p.check_date,
    p.invoice_number,
    p.payroll_processor,
    p.is_standard,
    p.employee_name,
    p.hr_department_id,
    p.hr_work_authorization_id,
    p.wc,
    p.pay_structure,
    p.hourly_rate,
    p.overtime_threshold,
    p.regular_hours,
    p.overtime_hours,
    p.holiday_hours,
    p.pto_hours,
    p.sick_hours,
    p.funeral_hours,
    p.total_hours,
    p.pto_hours_accrued,
    p.regular_pay,
    p.overtime_pay,
    p.holiday_pay,
    p.pto_pay,
    p.sick_pay,
    p.funeral_pay,
    p.other_pay,
    p.bonus_pay,
    p.auto_allowance,
    p.per_diem,
    p.salary,
    p.gross_wage,
    p.fit,
    p.sit,
    p.social_security,
    p.medicare,
    p.comp_plus,
    p.hds_dental,
    p.pre_tax_401k,
    p.auto_deduction,
    p.child_support,
    p.program_fees,
    p.net_pay,
    p.labor_tax,
    p.other_tax,
    p.workers_compensation,
    p.health_benefits,
    p.other_health_charges,
    p.admin_fees,
    p.hawaii_get,
    p.other_charges,
    p.tdi,
    p.total_cost,
    p.created_at,
    p.updated_at,
    p.is_deleted,
    e.first_name || ' ' || e.last_name AS full_name,
    e.preferred_name,
    e.profile_photo_url,
    d.name AS department_name,
    wa.name AS work_authorization_name
FROM hr_payroll p
JOIN hr_employee e ON e.id = p.hr_employee_id
LEFT JOIN hr_department d ON d.id = p.hr_department_id
LEFT JOIN hr_work_authorization wa ON wa.id = p.hr_work_authorization_id
WHERE p.is_deleted = false;

GRANT SELECT ON app_hr_payroll_detail TO authenticated;
