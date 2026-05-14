-- RECOVERED FROM PROD via pull-prod-drift workflow.
-- Original prod migration: version=20260514174552, name='create_hr_staffing_pp_detail_v'.
-- Review the SQL below, rename this file, and edit before
-- treating as authoritative.

CREATE OR REPLACE VIEW public.hr_staffing_pp_detail_v
WITH (security_invoker = false) AS
WITH ranked AS (
  SELECT
    EXTRACT(YEAR FROM check_date)::int AS year,
    DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM check_date) ORDER BY check_date) AS pp,
    check_date,
    CASE hr_work_authorization_id
      WHEN 'Local'           THEN 'local'
      WHEN 'WFE'             THEN 'wfe'
      WHEN 'H2A'             THEN 'h2a'
      WHEN 'FUERTE (Local)'  THEN 'f_local'
      WHEN 'FUERTE'          THEN 'fuerte'
    END AS labor_type,
    employee_name,
    hr_department_id,
    hr_work_authorization_id,
    total_hours,
    total_cost,
    gross_wage
  FROM hr_payroll
  WHERE is_deleted = false
    AND is_standard = true
    AND pay_structure = 'Hourly'
    AND hr_work_authorization_id IN ('Local','WFE','H2A','FUERTE (Local)','FUERTE')
    AND hr_employee_id != 'manuel_beke'
)
SELECT year, pp::int AS pp, check_date, labor_type,
       employee_name, hr_department_id, hr_work_authorization_id,
       total_hours, total_cost, gross_wage
FROM ranked;

GRANT SELECT ON public.hr_staffing_pp_detail_v TO anon, authenticated;
