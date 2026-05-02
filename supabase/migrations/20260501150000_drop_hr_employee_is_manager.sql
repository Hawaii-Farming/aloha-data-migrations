-- drop hr_employee.is_manager
-- ===========================
-- The is_manager boolean is duplicative with sys_access_level_id = 'Manager'
-- and is read by nothing in the frontend. Drop it.
--
-- Cascade chain:
--   hr_employee.is_manager
--     <- hr_payroll_by_task              (selects e.is_manager)
--          <- hr_payroll_employee_comparison  (SELECT v.* from hr_payroll_by_task)
--          <- hr_payroll_task_comparison       (does not project is_manager but
--                                              gets dropped if its source view is)
--
-- We DROP the column with CASCADE (which drops hr_payroll_by_task and the two
-- comparison views), then recreate them at their current definitions minus
-- the is_manager column. hr_payroll_data_secure does not depend on this chain
-- and is left untouched.

ALTER TABLE hr_employee DROP COLUMN IF EXISTS is_manager CASCADE;

-- ----------------------------------------------------------------------
-- hr_payroll_by_task  (was 20260401000072 — now without is_manager)
-- ----------------------------------------------------------------------
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
      AND p.payroll_processor = 'HRB'
    GROUP BY 1,2,3,4,5,6,7,8
),
sched_by_acct AS (
    SELECT
        pa.hr_employee_id,
        pa.check_date,
        COALESCE(t.qb_account, pa.hr_department_id) AS acct,
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
    e.compensation_manager_id,
    a.hr_work_authorization_id                          AS status,
    a.wc                                                AS workers_compensation_code,
    a.acct                                              AS task,
    ROUND(a.scheduled_hours::numeric, 2)                AS scheduled_hours,
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

-- ----------------------------------------------------------------------
-- hr_payroll_employee_comparison  (RBAC version from 20260501120100)
-- ----------------------------------------------------------------------
CREATE OR REPLACE VIEW public.hr_payroll_employee_comparison
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

    COALESCE(c.scheduled_hours, 0)                                       AS scheduled_hours,
    COALESCE(c.total_hours, 0)                                           AS total_hours,
    COALESCE(c.discretionary_overtime_hours, 0)                          AS discretionary_overtime_hours,
    COALESCE(c.total_hours, 0) - COALESCE(pr.total_hours, 0)             AS hours_delta,

    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.total_cost, 0)
    END AS total_cost,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.regular_pay, 0)
    END AS regular_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.discretionary_overtime_pay, 0)
    END AS discretionary_overtime_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.total_cost, 0) - COALESCE(pr.total_cost, 0)
    END AS total_cost_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.regular_pay, 0) - COALESCE(pr.regular_pay, 0)
    END AS regular_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.discretionary_overtime_pay, 0) - COALESCE(pr.discretionary_overtime_pay, 0)
    END AS discretionary_overtime_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE (COALESCE(c.total_cost, 0) - COALESCE(pr.total_cost, 0))
            - (COALESCE(c.regular_pay, 0) - COALESCE(pr.regular_pay, 0))
            - (COALESCE(c.discretionary_overtime_pay, 0) - COALESCE(pr.discretionary_overtime_pay, 0))
    END AS other_pay_delta
FROM current_p c
FULL OUTER JOIN previous_p pr
    ON pr.hr_employee_id = c.hr_employee_id
   AND pr.task = c.task
WHERE
    public.auth_access_level(COALESCE(c.org_id, pr.org_id)) IN ('Owner', 'Admin', 'Team Lead')
    OR (
        public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Manager'
        AND (
            COALESCE(c.compensation_manager_id, pr.compensation_manager_id)
              = public.auth_employee_id(COALESCE(c.org_id, pr.org_id))
            OR COALESCE(c.hr_employee_id, pr.hr_employee_id)
              = public.auth_employee_id(COALESCE(c.org_id, pr.org_id))
        )
    );

GRANT SELECT ON hr_payroll_employee_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_employee_comparison IS 'Per-employee per-task snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior is_standard=TRUE check_date. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees direct reports + self; Team Lead has $ columns NULL-masked. Org isolation via security_invoker.';

-- ----------------------------------------------------------------------
-- hr_payroll_task_comparison  (RBAC version from 20260501120100)
-- ----------------------------------------------------------------------
CREATE OR REPLACE VIEW public.hr_payroll_task_comparison
WITH (security_invoker = true) AS
WITH standard_dates AS (
    SELECT DISTINCT hr_payroll.check_date
    FROM hr_payroll
    WHERE hr_payroll.is_standard = true
      AND hr_payroll.payroll_processor = 'HRB'::text
      AND NOT hr_payroll.is_deleted
),
ranked_dates AS (
    SELECT standard_dates.check_date,
           dense_rank() OVER (ORDER BY standard_dates.check_date DESC) AS rnk
    FROM standard_dates
),
periods AS (
    SELECT max(ranked_dates.check_date) FILTER (WHERE ranked_dates.rnk = 1) AS cur_date,
           max(ranked_dates.check_date) FILTER (WHERE ranked_dates.rnk = 2) AS prev_date
    FROM ranked_dates
),
current_p AS (
    SELECT v.org_id,
           v.compensation_manager_id,
           v.task,
           v.status,
           sum(v.scheduled_hours) AS scheduled_hours,
           sum(v.total_hours) AS total_hours,
           sum(v.total_cost) AS total_cost,
           sum(v.regular_pay) AS regular_pay,
           sum(v.discretionary_overtime_hours) AS discretionary_overtime_hours,
           sum(v.discretionary_overtime_pay) AS discretionary_overtime_pay
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.cur_date
    GROUP BY v.org_id, v.compensation_manager_id, v.task, v.status
),
previous_p AS (
    SELECT v.org_id,
           v.compensation_manager_id,
           v.task,
           v.status,
           sum(v.scheduled_hours) AS scheduled_hours,
           sum(v.total_hours) AS total_hours,
           sum(v.total_cost) AS total_cost,
           sum(v.regular_pay) AS regular_pay,
           sum(v.discretionary_overtime_hours) AS discretionary_overtime_hours,
           sum(v.discretionary_overtime_pay) AS discretionary_overtime_pay
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.prev_date
    GROUP BY v.org_id, v.compensation_manager_id, v.task, v.status
)
SELECT
    COALESCE(c.org_id, pr.org_id)                                       AS org_id,
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)     AS compensation_manager_id,
    COALESCE(c.task, pr.task)                                           AS task,
    COALESCE(c.status, pr.status)                                       AS status,
    (SELECT periods.cur_date FROM periods)                              AS check_date,

    COALESCE(c.scheduled_hours, 0::numeric)                             AS scheduled_hours,
    COALESCE(c.total_hours, 0::numeric)                                 AS total_hours,
    COALESCE(c.discretionary_overtime_hours, 0::numeric)                AS discretionary_overtime_hours,
    COALESCE(c.total_hours, 0::numeric) - COALESCE(pr.total_hours, 0::numeric) AS hours_delta,

    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.total_cost, 0::numeric)
    END AS total_cost,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.regular_pay, 0::numeric)
    END AS regular_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.discretionary_overtime_pay, 0::numeric)
    END AS discretionary_overtime_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.total_cost, 0::numeric) - COALESCE(pr.total_cost, 0::numeric)
    END AS total_cost_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.regular_pay, 0::numeric) - COALESCE(pr.regular_pay, 0::numeric)
    END AS regular_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE COALESCE(c.discretionary_overtime_pay, 0::numeric) - COALESCE(pr.discretionary_overtime_pay, 0::numeric)
    END AS discretionary_overtime_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE (COALESCE(c.total_cost, 0::numeric) - COALESCE(pr.total_cost, 0::numeric))
            - (COALESCE(c.regular_pay, 0::numeric) - COALESCE(pr.regular_pay, 0::numeric))
            - (COALESCE(c.discretionary_overtime_pay, 0::numeric) - COALESCE(pr.discretionary_overtime_pay, 0::numeric))
    END AS other_pay_delta
FROM current_p c
FULL JOIN previous_p pr
    ON pr.org_id = c.org_id
   AND NOT pr.compensation_manager_id IS DISTINCT FROM c.compensation_manager_id
   AND pr.task = c.task
   AND pr.status = c.status
WHERE
    public.auth_access_level(COALESCE(c.org_id, pr.org_id)) IN ('Owner', 'Admin', 'Team Lead')
    OR (
        public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Manager'
        AND COALESCE(c.compensation_manager_id, pr.compensation_manager_id)
              = public.auth_employee_id(COALESCE(c.org_id, pr.org_id))
    );

GRANT SELECT ON hr_payroll_task_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_task_comparison IS 'Per-task (no employee dimension) snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior period. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees only rows where they are the compensation manager; Team Lead has $ columns NULL-masked.';
