-- RECOVERED FROM PROD via pull-prod-drift workflow.
-- Original prod migration: version=20260514190001, name='staffing_view_also_exclude_batha_reports'.
-- Review the SQL below, rename this file, and edit before
-- treating as authoritative.

CREATE OR REPLACE VIEW public.hr_staffing_pp_v
WITH (security_invoker = false) AS
WITH ranked AS (
  SELECT
    EXTRACT(YEAR FROM p.check_date)::int AS year,
    DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.check_date) ORDER BY p.check_date) AS pp,
    p.check_date,
    CASE p.hr_work_authorization_id
      WHEN 'Local'           THEN 'local'
      WHEN 'WFE'             THEN 'wfe'
      WHEN 'H2A'             THEN 'h2a'
      WHEN 'FUERTE (Local)'  THEN 'f_local'
      WHEN 'FUERTE'          THEN 'fuerte'
    END AS labor_type,
    p.hr_employee_id,
    p.total_hours, p.total_cost, p.gross_wage
  FROM hr_payroll p
  LEFT JOIN hr_employee e ON e.id = p.hr_employee_id
  WHERE p.is_deleted = false
    AND p.is_standard = true
    AND p.hr_work_authorization_id IN ('Local','WFE','H2A','FUERTE (Local)','FUERTE')
    AND p.hr_department_id IS DISTINCT FROM 'Maintenance'
    AND e.compensation_manager_id IS NOT NULL
    AND e.compensation_manager_id NOT IN ('feder_leonard', 'cervantes_acosta_eric_abraham', 'batha_eric')
)
SELECT year, pp::int AS pp, MIN(check_date) AS check_date, labor_type,
       COUNT(DISTINCT hr_employee_id)::int AS headcount,
       SUM(total_hours) AS hours,
       SUM(total_cost) AS cost_total,
       SUM(gross_wage) AS cost_gross
FROM ranked
GROUP BY year, pp, labor_type;

GRANT SELECT ON public.hr_staffing_pp_v TO anon, authenticated;

CREATE OR REPLACE VIEW public.hr_staffing_pp_detail_v
WITH (security_invoker = false) AS
WITH ranked AS (
  SELECT
    EXTRACT(YEAR FROM p.check_date)::int AS year,
    DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.check_date) ORDER BY p.check_date) AS pp,
    p.check_date,
    CASE p.hr_work_authorization_id
      WHEN 'Local'           THEN 'local'
      WHEN 'WFE'             THEN 'wfe'
      WHEN 'H2A'             THEN 'h2a'
      WHEN 'FUERTE (Local)'  THEN 'f_local'
      WHEN 'FUERTE'          THEN 'fuerte'
    END AS labor_type,
    p.employee_name, p.hr_department_id, p.hr_work_authorization_id,
    p.total_hours, p.total_cost, p.gross_wage
  FROM hr_payroll p
  LEFT JOIN hr_employee e ON e.id = p.hr_employee_id
  WHERE p.is_deleted = false
    AND p.is_standard = true
    AND p.hr_work_authorization_id IN ('Local','WFE','H2A','FUERTE (Local)','FUERTE')
    AND p.hr_department_id IS DISTINCT FROM 'Maintenance'
    AND e.compensation_manager_id IS NOT NULL
    AND e.compensation_manager_id NOT IN ('feder_leonard', 'cervantes_acosta_eric_abraham', 'batha_eric')
)
SELECT year, pp::int AS pp, check_date, labor_type,
       employee_name, hr_department_id, hr_work_authorization_id,
       total_hours, total_cost, gross_wage
FROM ranked;

GRANT SELECT ON public.hr_staffing_pp_detail_v TO anon, authenticated;
