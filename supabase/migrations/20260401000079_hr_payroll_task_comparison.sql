-- hr_payroll_task_comparison
-- ==========================
-- Per-(comp_manager, task, status) snapshot for the most recent
-- is_standard=TRUE HRB check_date, with deltas vs the prior is_standard=TRUE
-- check_date. Same period-anchoring + delta semantics as
-- hr_payroll_employee_comparison, but rolled up: aggregates across employees
-- so each row is one task in a manager's bucket.
--
-- Grouping: org_id, compensation_manager_id, task, status.
-- (Dropped from the employee view: hr_employee_id, workers_compensation_code.)
--
-- Period anchors use is_standard=TRUE dates only, so off-cycle / adjustment
-- runs (is_standard=FALSE) don't shift the current period forward.
--
-- FULL OUTER JOIN so a (manager, task, status) bucket present in only one
-- of the two periods still appears — previous-only rows carry zeros on the
-- current side and negative deltas; current-only rows carry positive deltas.
-- IS NOT DISTINCT FROM matches NULL compensation_manager_id between periods.

CREATE OR REPLACE VIEW hr_payroll_task_comparison
WITH (security_invoker = true) AS
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
    SELECT
        v.org_id,
        v.compensation_manager_id,
        v.task,
        v.status,
        SUM(v.scheduled_hours)               AS scheduled_hours,
        SUM(v.total_hours)                   AS total_hours,
        SUM(v.total_cost)                    AS total_cost,
        SUM(v.regular_pay)                   AS regular_pay,
        SUM(v.discretionary_overtime_hours)  AS discretionary_overtime_hours,
        SUM(v.discretionary_overtime_pay)    AS discretionary_overtime_pay
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.cur_date
    GROUP BY v.org_id, v.compensation_manager_id, v.task, v.status
),
previous_p AS (
    SELECT
        v.org_id,
        v.compensation_manager_id,
        v.task,
        v.status,
        SUM(v.scheduled_hours)               AS scheduled_hours,
        SUM(v.total_hours)                   AS total_hours,
        SUM(v.total_cost)                    AS total_cost,
        SUM(v.regular_pay)                   AS regular_pay,
        SUM(v.discretionary_overtime_hours)  AS discretionary_overtime_hours,
        SUM(v.discretionary_overtime_pay)    AS discretionary_overtime_pay
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.prev_date
    GROUP BY v.org_id, v.compensation_manager_id, v.task, v.status
)
SELECT
    COALESCE(c.org_id, pr.org_id)                                        AS org_id,
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)      AS compensation_manager_id,
    COALESCE(c.task, pr.task)                                            AS task,
    COALESCE(c.status, pr.status)                                        AS status,
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
    ON  pr.org_id                  =                  c.org_id
   AND pr.compensation_manager_id IS NOT DISTINCT FROM c.compensation_manager_id
   AND pr.task                    =                  c.task
   AND pr.status                  =                  c.status;

GRANT SELECT ON hr_payroll_task_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_task_comparison IS 'Per-(comp_manager, task, status) snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior is_standard=TRUE check_date. Sums across employees within each manager bucket. Same period-anchoring and delta semantics as hr_payroll_employee_comparison.';
