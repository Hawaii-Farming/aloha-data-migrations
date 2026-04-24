-- hr_payroll_employee_comparison
-- ==============================
-- Per-employee per-task snapshot for the most recent is_standard=TRUE
-- HRB check_date, with deltas vs the prior is_standard=TRUE check_date.
-- Shows the current period values + deltas only; previous values and
-- previous check_date are inferable downstream (previous = current - delta,
-- previous_date = known pay cadence).
--
-- Period anchors use is_standard=TRUE dates only, so off-cycle / adjustment
-- runs (is_standard=FALSE) don't shift the current period forward.
--
-- FULL OUTER JOIN so (employee, task) rows present in only one of the two
-- periods still appear — previous-only rows carry zeros on the current
-- side and negative deltas; current-only rows carry positive deltas.

CREATE OR REPLACE VIEW hr_payroll_employee_comparison AS
WITH standard_dates AS (
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
)
SELECT
    COALESCE(c.org_id, pr.org_id)                                        AS org_id,
    COALESCE(c.hr_employee_id, pr.hr_employee_id)                        AS hr_employee_id,
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)      AS compensation_manager_id,
    COALESCE(c.task, pr.task)                                            AS task,
    COALESCE(c.status, pr.status)                                        AS status,
    COALESCE(c.workers_compensation_code, pr.workers_compensation_code)  AS workers_compensation_code,
    (SELECT cur_date FROM periods)                                       AS check_date,

    -- Current period values
    COALESCE(c.scheduled_hours, 0)                                       AS scheduled_hours,
    COALESCE(c.total_hours, 0)                                           AS total_hours,
    COALESCE(c.total_cost, 0)                                            AS total_cost,
    COALESCE(c.regular_pay, 0)                                           AS regular_pay,
    COALESCE(c.discretionary_overtime_hours, 0)                          AS discretionary_overtime_hours,
    COALESCE(c.discretionary_overtime_pay, 0)                            AS discretionary_overtime_pay,

    -- Deltas (current - previous)
    COALESCE(c.total_hours, 0)                  - COALESCE(pr.total_hours, 0)                  AS hours_delta,
    COALESCE(c.total_cost, 0)                   - COALESCE(pr.total_cost, 0)                   AS total_cost_delta,
    COALESCE(c.regular_pay, 0)                  - COALESCE(pr.regular_pay, 0)                  AS regular_pay_delta,
    COALESCE(c.discretionary_overtime_pay, 0)   - COALESCE(pr.discretionary_overtime_pay, 0)   AS discretionary_overtime_pay_delta,
    (COALESCE(c.total_cost, 0) - COALESCE(pr.total_cost, 0))
      - (COALESCE(c.regular_pay, 0) - COALESCE(pr.regular_pay, 0))
      - (COALESCE(c.discretionary_overtime_pay, 0) - COALESCE(pr.discretionary_overtime_pay, 0))
        AS other_pay_delta
FROM current_p c
FULL OUTER JOIN previous_p pr
    ON pr.hr_employee_id = c.hr_employee_id
   AND pr.task = c.task;

GRANT SELECT ON hr_payroll_employee_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_employee_comparison IS 'Per-employee per-task snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior is_standard=TRUE check_date. Previous-period values are inferable as current - delta; previous check_date is known from the pay cadence.';
