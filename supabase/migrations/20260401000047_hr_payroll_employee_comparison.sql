-- hr_payroll_employee_comparison
-- ==============================
-- Port of the legacy `hr_ee_payroll_employee_comparison` sheet tab. One row per
-- (employee, task) comparing the two most recent check_dates in the dataset,
-- with computed deltas for hours, cost, and pay components.
--
-- Current / previous are determined globally (MAX and 2nd-MAX check_date
-- across hr_payroll_by_task) — matching the legacy behaviour where every row
-- in the sheet tab shared the same CheckDateCurrentPeriod / CheckDatePreviousPeriod.
--
-- An (employee, task) present in only one of the two periods still appears,
-- with zeros filled in for the missing side so deltas are still meaningful.
--
-- pto_hours_accrued is carried from hr_payroll (employee-level, same value
-- for every task row of a given paycheck).

CREATE OR REPLACE VIEW hr_payroll_employee_comparison AS
WITH standard_dates AS (
    -- Period boundaries come from is_standard=TRUE check_dates only.
    -- Off-cycle / adjustment runs (is_standard=FALSE) can land on arbitrary
    -- dates and must not shift the "current period" anchor.
    SELECT DISTINCT check_date
    FROM hr_payroll
    WHERE is_standard = true
      AND payroll_processor = 'HRB'
      AND NOT is_deleted
),
ranked_dates AS (
    SELECT check_date,
           dense_rank() OVER (ORDER BY check_date DESC) AS rnk
    FROM standard_dates
),
periods AS (
    SELECT
        MAX(check_date) FILTER (WHERE rnk = 1) AS cur_date,
        MAX(check_date) FILTER (WHERE rnk = 2) AS prev_date
    FROM ranked_dates
),
current_p AS (
    SELECT v.*
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.cur_date
),
previous_p AS (
    SELECT v.*
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.prev_date
),
-- Employee-level PTO accrual per paycheck — same value repeats across every
-- task row in the sheet output, so join by (employee, check_date) not task.
pto_current AS (
    SELECT hr_employee_id, SUM(pto_hours_accrued) AS pto_hours_accrued
    FROM hr_payroll p, periods pr
    WHERE p.check_date = pr.cur_date
      AND p.payroll_processor = 'HRB'
      AND NOT p.is_deleted
    GROUP BY hr_employee_id
)
SELECT
    COALESCE(c.org_id, pr.org_id)                                        AS org_id,
    COALESCE(c.hr_employee_id, pr.hr_employee_id)                        AS hr_employee_id,
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)      AS compensation_manager_id,
    COALESCE(c.task, pr.task)                                            AS task,
    COALESCE(c.status, pr.status)                                        AS status,
    COALESCE(c.workers_compensation_code, pr.workers_compensation_code)  AS workers_compensation_code,

    -- Current period
    (SELECT cur_date FROM periods)                                   AS check_date_current_period,
    COALESCE(c.scheduled_hours, 0)                                       AS scheduled_hours,
    COALESCE(c.total_hours, 0)                                           AS hours_current_period,
    COALESCE(c.total_cost, 0)                                            AS total_cost_current_period,
    COALESCE(c.regular_pay, 0)                                           AS regular_pay_current_period,
    COALESCE(c.discretionary_overtime_hours, 0)                          AS discretionary_overtime_hours_current_period,
    COALESCE(c.discretionary_overtime_pay, 0)                            AS discretionary_overtime_pay_current_period,
    pt.pto_hours_accrued                                                 AS pto_hours_accrued,

    -- Previous period
    (SELECT prev_date FROM periods)                                  AS check_date_previous_period,
    COALESCE(pr.total_hours, 0)                                          AS hours_previous_period,
    COALESCE(pr.total_cost, 0)                                           AS total_cost_previous_period,
    COALESCE(pr.regular_pay, 0)                                          AS regular_pay_previous_period,
    COALESCE(pr.discretionary_overtime_pay, 0)                           AS discretionary_overtime_pay_previous_period,

    -- Deltas (current - previous)
    COALESCE(c.total_hours, 0)                  - COALESCE(pr.total_hours, 0)                  AS hours_delta,
    COALESCE(c.total_cost, 0)                   - COALESCE(pr.total_cost, 0)                   AS total_cost_delta,
    COALESCE(c.regular_pay, 0)                  - COALESCE(pr.regular_pay, 0)                  AS regular_pay_delta,
    COALESCE(c.discretionary_overtime_pay, 0)   - COALESCE(pr.discretionary_overtime_pay, 0)   AS discretionary_overtime_pay_delta,
    -- Other pay delta = what's left over after regular + discretionary OT
    (COALESCE(c.total_cost, 0) - COALESCE(pr.total_cost, 0))
      - (COALESCE(c.regular_pay, 0) - COALESCE(pr.regular_pay, 0))
      - (COALESCE(c.discretionary_overtime_pay, 0) - COALESCE(pr.discretionary_overtime_pay, 0))
        AS other_pay_delta
FROM current_p c
FULL OUTER JOIN previous_p pr
    ON pr.hr_employee_id = c.hr_employee_id
   AND pr.task = c.task
LEFT JOIN pto_current pt
    ON pt.hr_employee_id = COALESCE(c.hr_employee_id, pr.hr_employee_id);

GRANT SELECT ON hr_payroll_employee_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_employee_comparison IS 'Per-employee per-task comparison of the two most recent check_dates in hr_payroll_by_task. Includes current, previous, and deltas for hours/cost/regular_pay/discretionary_overtime_pay, plus a computed other_pay_delta and the current period pto_hours_accrued.';
