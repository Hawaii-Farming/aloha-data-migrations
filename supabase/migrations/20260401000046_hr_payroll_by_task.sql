-- hr_payroll_by_task
-- ==================
-- Port of the legacy `payrollSchedComparison` Google Apps Script that builds
-- the `hr_ee_payroll_by_tasks` tab. One row per (employee, check_date,
-- QuickBooks account) with payroll totals allocated proportionally to how the
-- employee was scheduled across accounts inside that pay period.
--
-- Allocation method (matches GAS):
--   1. Aggregate hr_payroll per (employee, check_date) — sum any duplicate rows.
--   2. Aggregate ops_task_schedule within [pay_period_start, pay_period_end]
--      per (employee, qb_account). qb_account is ops_task.qb_account, falling
--      back to the employee's department when the task has no QB mapping.
--   3. Compute each acct's ratio = scheduled_hours / total_scheduled_hours.
--   4. Multiply each payroll hour/pay field by the ratio and round to 2dp.
--   5. When an employee has no schedule in the pay period, emit one row under
--      their department with the full payroll totals (same as the GAS fallback).
--
-- The scheduled_hours column is the RAW schedule-side hours (not scaled),
-- so a variance column downstream can compare scheduled vs paid per acct.
--
-- Filter matches the GAS script: check_date >= 2025-01-01.

CREATE OR REPLACE VIEW hr_payroll_by_task
WITH (security_invoker = true) AS
WITH payroll_agg AS (
    SELECT
        p.org_id,
        p.hr_employee_id,
        p.check_date,
        p.pay_period_start,
        p.pay_period_end,
        p.hr_department_id,
        p.hr_work_authorization_id,
        p.wc,
        SUM(p.total_hours)                        AS total_hours,
        SUM(p.regular_hours)                      AS regular_hours,
        SUM(p.pto_hours)                          AS pto_hours,
        SUM(p.discretionary_overtime_hours)       AS discretionary_overtime_hours,
        SUM(p.total_cost)                         AS total_cost,
        SUM(p.regular_pay)                        AS regular_pay,
        SUM(p.discretionary_overtime_pay)         AS discretionary_overtime_pay
    FROM hr_payroll p
    WHERE NOT p.is_deleted
      AND p.check_date >= DATE '2025-01-01'
      -- Only actual payroll-processed employees. The 'HF' processor covers
      -- reimbursements to owners/vendors (Bruce Wilkins, Childers Minor,
      -- Food Ventures etc.) which the legacy GAS output excluded.
      AND p.payroll_processor = 'HRB'
    GROUP BY 1,2,3,4,5,6,7,8
),
sched_by_acct AS (
    SELECT
        pa.hr_employee_id,
        pa.check_date,
        COALESCE(t.qb_account, pa.hr_department_id) AS acct,
        -- Use lunch-adjusted total_hours captured from the sheet's daily
        -- Hours column; fall back to stop-start when unavailable.
        SUM(COALESCE(
            s.total_hours,
            EXTRACT(EPOCH FROM (s.stop_time - s.start_time)) / 3600.0
        )) AS scheduled_hours
    FROM payroll_agg pa
    JOIN ops_task_schedule s
      ON s.org_id = pa.org_id
     AND s.hr_employee_id = pa.hr_employee_id
     AND s.start_time::date BETWEEN pa.pay_period_start AND pa.pay_period_end
     AND NOT s.is_deleted
    LEFT JOIN ops_task t ON t.id = s.ops_task_id
    GROUP BY 1, 2, 3
),
sched_totals AS (
    SELECT hr_employee_id, check_date, SUM(scheduled_hours) AS sched_total
    FROM sched_by_acct
    GROUP BY 1, 2
),
-- Rows where the employee has a schedule: one per acct
with_schedule AS (
    SELECT
        pa.*,
        sa.acct,
        sa.scheduled_hours,
        st.sched_total
    FROM payroll_agg pa
    JOIN sched_by_acct sa
      ON sa.hr_employee_id = pa.hr_employee_id
     AND sa.check_date = pa.check_date
    JOIN sched_totals st
      ON st.hr_employee_id = pa.hr_employee_id
     AND st.check_date = pa.check_date
),
-- Rows with no schedule: single synthetic row bucketed to department
without_schedule AS (
    SELECT
        pa.*,
        pa.hr_department_id AS acct,
        0::numeric          AS scheduled_hours,
        NULL::numeric       AS sched_total
    FROM payroll_agg pa
    WHERE NOT EXISTS (
        SELECT 1 FROM sched_by_acct sa
        WHERE sa.hr_employee_id = pa.hr_employee_id
          AND sa.check_date = pa.check_date
    )
),
allocated AS (
    SELECT * FROM with_schedule
    UNION ALL
    SELECT * FROM without_schedule
)
SELECT
    a.org_id,
    a.hr_employee_id,
    a.check_date,
    e.is_manager,
    e.compensation_manager_id,
    a.hr_work_authorization_id                          AS status,
    a.wc                                                AS workers_compensation_code,
    a.acct                                              AS task,
    ROUND(a.scheduled_hours::numeric, 2)                AS scheduled_hours,
    -- Allocated payroll fields
    ROUND(
        CASE
            WHEN a.sched_total IS NULL AND a.total_hours = 0 AND a.pto_hours > 0
                THEN a.pto_hours
            WHEN a.sched_total IS NULL
                THEN a.total_hours
            WHEN a.sched_total > 0
                THEN a.total_hours * a.scheduled_hours / a.sched_total
            ELSE 0
        END::numeric, 2)                                AS total_hours,
    ROUND(
        CASE
            WHEN a.sched_total IS NULL           THEN a.regular_hours
            WHEN a.sched_total > 0               THEN a.regular_hours * a.scheduled_hours / a.sched_total
            ELSE 0
        END::numeric, 2)                                AS regular_hours,
    ROUND(
        CASE
            WHEN a.sched_total IS NULL           THEN a.discretionary_overtime_hours
            WHEN a.sched_total > 0               THEN a.discretionary_overtime_hours * a.scheduled_hours / a.sched_total
            ELSE 0
        END::numeric, 2)                                AS discretionary_overtime_hours,
    ROUND(
        CASE
            WHEN a.sched_total IS NULL           THEN a.total_cost
            WHEN a.sched_total > 0               THEN a.total_cost * a.scheduled_hours / a.sched_total
            ELSE a.total_cost
        END::numeric, 2)                                AS total_cost,
    ROUND(
        CASE
            WHEN a.sched_total IS NULL           THEN a.regular_pay
            WHEN a.sched_total > 0               THEN a.regular_pay * a.scheduled_hours / a.sched_total
            ELSE 0
        END::numeric, 2)                                AS regular_pay,
    ROUND(
        CASE
            WHEN a.sched_total IS NULL           THEN a.discretionary_overtime_pay
            WHEN a.sched_total > 0               THEN a.discretionary_overtime_pay * a.scheduled_hours / a.sched_total
            ELSE 0
        END::numeric, 2)                                AS discretionary_overtime_pay
FROM allocated a
JOIN hr_employee e ON e.id = a.hr_employee_id;

GRANT SELECT ON hr_payroll_by_task TO authenticated;

COMMENT ON VIEW hr_payroll_by_task IS 'Replicates the legacy payrollSchedComparison GAS output: payroll totals split across QuickBooks accounts proportionally to scheduled hours per pay period. Scheduled hours column is raw (unscaled) so variance vs paid can be computed downstream.';
