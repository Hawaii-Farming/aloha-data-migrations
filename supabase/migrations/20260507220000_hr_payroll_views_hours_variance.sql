-- hr_payroll_views — hours_variance column
-- =========================================
-- Adds hours_variance (= scheduled_hours - total_hours) to both
-- comparison views, positioned right after total_hours. The original
-- definitions in 20260501120100_hr_payroll_rbac_views.sql were edited
-- in place to include this column, but `supabase db push` skips
-- already-applied migration files, so the live DB stayed at the prior
-- column list. This patch re-runs the DROP + CREATE so the live DB
-- catches up. Safe (idempotent) on a fresh rebuild — the prior
-- migration creates the view with hours_variance already, this one
-- drops and recreates with the same DDL.

DROP VIEW IF EXISTS public.hr_payroll_employee_comparison CASCADE;
DROP VIEW IF EXISTS public.hr_payroll_task_comparison CASCADE;

----------------------------------------------------------------------
-- 1. hr_payroll_employee_comparison
----------------------------------------------------------------------
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
    TRIM(e.first_name || ' ' || e.last_name)                             AS employee_full_name,
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)      AS compensation_manager_id,
    COALESCE(c.task, pr.task)                                            AS task,
    COALESCE(c.status, pr.status)                                        AS status,
    COALESCE(c.workers_compensation_code, pr.workers_compensation_code)  AS workers_compensation_code,
    (SELECT cur_date FROM periods)                                       AS check_date,

    -- Hours (always visible) -- rounded to whole hours for display.
    ROUND(COALESCE(c.scheduled_hours, 0))                                AS scheduled_hours,
    ROUND(COALESCE(c.total_hours, 0))                                    AS total_hours,
    ROUND(COALESCE(c.scheduled_hours, 0) - COALESCE(c.total_hours, 0))   AS hours_variance,
    ROUND(COALESCE(c.discretionary_overtime_hours, 0))                   AS discretionary_overtime_hours,
    ROUND(COALESCE(c.total_hours, 0) - COALESCE(pr.total_hours, 0))      AS hours_delta,

    -- Dollars (NULL for Team Lead) -- rounded to whole dollars for display.
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.total_cost, 0))
    END AS total_cost,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.regular_pay, 0))
    END AS regular_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.discretionary_overtime_pay, 0))
    END AS discretionary_overtime_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.total_cost, 0) - COALESCE(pr.total_cost, 0))
    END AS total_cost_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.regular_pay, 0) - COALESCE(pr.regular_pay, 0))
    END AS regular_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.discretionary_overtime_pay, 0) - COALESCE(pr.discretionary_overtime_pay, 0))
    END AS discretionary_overtime_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(
              (COALESCE(c.total_cost, 0) - COALESCE(pr.total_cost, 0))
            - (COALESCE(c.regular_pay, 0) - COALESCE(pr.regular_pay, 0))
            - (COALESCE(c.discretionary_overtime_pay, 0) - COALESCE(pr.discretionary_overtime_pay, 0))
         )
    END AS other_pay_delta
FROM current_p c
FULL OUTER JOIN previous_p pr
    ON pr.hr_employee_id = c.hr_employee_id
   AND pr.task = c.task
LEFT JOIN public.hr_employee e
    ON e.org_id = COALESCE(c.org_id, pr.org_id)
   AND e.id     = COALESCE(c.hr_employee_id, pr.hr_employee_id)
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

----------------------------------------------------------------------
-- 2. hr_payroll_task_comparison
----------------------------------------------------------------------
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
    m.preferred_name                                                    AS compensation_manager_alias,
    COALESCE(c.task, pr.task)                                           AS task,
    COALESCE(c.status, pr.status)                                       AS status,
    (SELECT periods.cur_date FROM periods)                              AS check_date,

    -- Hours (always visible) -- rounded to whole hours for display.
    ROUND(COALESCE(c.scheduled_hours, 0::numeric))                      AS scheduled_hours,
    ROUND(COALESCE(c.total_hours, 0::numeric))                          AS total_hours,
    ROUND(COALESCE(c.scheduled_hours, 0::numeric) - COALESCE(c.total_hours, 0::numeric)) AS hours_variance,
    ROUND(COALESCE(c.discretionary_overtime_hours, 0::numeric))         AS discretionary_overtime_hours,
    ROUND(COALESCE(c.total_hours, 0::numeric) - COALESCE(pr.total_hours, 0::numeric)) AS hours_delta,

    -- Dollars (NULL for Team Lead) -- rounded to whole dollars for display.
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.total_cost, 0::numeric))
    END AS total_cost,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.regular_pay, 0::numeric))
    END AS regular_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.discretionary_overtime_pay, 0::numeric))
    END AS discretionary_overtime_pay,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.total_cost, 0::numeric) - COALESCE(pr.total_cost, 0::numeric))
    END AS total_cost_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.regular_pay, 0::numeric) - COALESCE(pr.regular_pay, 0::numeric))
    END AS regular_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(COALESCE(c.discretionary_overtime_pay, 0::numeric) - COALESCE(pr.discretionary_overtime_pay, 0::numeric))
    END AS discretionary_overtime_pay_delta,
    CASE WHEN public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Team Lead'
         THEN NULL
         ELSE ROUND(
              (COALESCE(c.total_cost, 0::numeric) - COALESCE(pr.total_cost, 0::numeric))
            - (COALESCE(c.regular_pay, 0::numeric) - COALESCE(pr.regular_pay, 0::numeric))
            - (COALESCE(c.discretionary_overtime_pay, 0::numeric) - COALESCE(pr.discretionary_overtime_pay, 0::numeric))
         )
    END AS other_pay_delta
FROM current_p c
FULL JOIN previous_p pr
    ON pr.org_id = c.org_id
   AND NOT pr.compensation_manager_id IS DISTINCT FROM c.compensation_manager_id
   AND pr.task = c.task
   AND pr.status = c.status
LEFT JOIN public.hr_employee m
    ON m.org_id = COALESCE(c.org_id, pr.org_id)
   AND m.id     = COALESCE(c.compensation_manager_id, pr.compensation_manager_id)
WHERE
    public.auth_access_level(COALESCE(c.org_id, pr.org_id)) IN ('Owner', 'Admin', 'Team Lead')
    OR (
        public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Manager'
        AND COALESCE(c.compensation_manager_id, pr.compensation_manager_id)
              = public.auth_employee_id(COALESCE(c.org_id, pr.org_id))
    );

GRANT SELECT ON hr_payroll_task_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_task_comparison IS 'Per-task (no employee dimension) snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior period. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees only rows where they are the compensation manager; Team Lead has $ columns NULL-masked.';
