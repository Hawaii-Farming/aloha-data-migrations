-- hr_payroll_employee_comparison -- one row per employee (drop task grouping)
-- ===========================================================================
-- The frontend Employee comparison grid
-- (app/components/ag-grid/payroll-comparison-list-view.tsx, byEmployeeColDefs)
-- expects one row per employee with no `task` column. The view however was
-- still emitting one row per (employee, task) -- inflating row counts and
-- showing duplicate employees in the grid. Aggregate across tasks: SUM the
-- numerical columns, MAX the (employee-scoped, task-invariant) status /
-- workers_compensation_code / compensation_manager_id columns, and drop
-- task from both the SELECT list and the FULL OUTER JOIN key.
--
-- 20260501120100_hr_payroll_rbac_views.sql has been edited in place so a
-- fresh `supabase db reset` produces this shape directly; this migration
-- carries the DROP + CREATE for the live dev + prod DBs.

DROP VIEW IF EXISTS public.hr_payroll_employee_comparison CASCADE;

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
    SELECT
        v.org_id,
        v.hr_employee_id,
        MAX(v.compensation_manager_id)     AS compensation_manager_id,
        MAX(v.status)                      AS status,
        MAX(v.workers_compensation_code)   AS workers_compensation_code,
        SUM(v.scheduled_hours)             AS scheduled_hours,
        SUM(v.total_hours)                 AS total_hours,
        SUM(v.total_cost)                  AS total_cost,
        SUM(v.regular_pay)                 AS regular_pay,
        SUM(v.discretionary_overtime_hours) AS discretionary_overtime_hours,
        SUM(v.discretionary_overtime_pay)  AS discretionary_overtime_pay
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.cur_date
    GROUP BY v.org_id, v.hr_employee_id
),
previous_p AS (
    SELECT
        v.org_id,
        v.hr_employee_id,
        MAX(v.compensation_manager_id)     AS compensation_manager_id,
        MAX(v.status)                      AS status,
        MAX(v.workers_compensation_code)   AS workers_compensation_code,
        SUM(v.scheduled_hours)             AS scheduled_hours,
        SUM(v.total_hours)                 AS total_hours,
        SUM(v.total_cost)                  AS total_cost,
        SUM(v.regular_pay)                 AS regular_pay,
        SUM(v.discretionary_overtime_hours) AS discretionary_overtime_hours,
        SUM(v.discretionary_overtime_pay)  AS discretionary_overtime_pay
    FROM hr_payroll_by_task v, periods p
    WHERE v.check_date = p.prev_date
    GROUP BY v.org_id, v.hr_employee_id
)
SELECT
    COALESCE(c.org_id, pr.org_id)                                        AS org_id,
    COALESCE(c.hr_employee_id, pr.hr_employee_id)                        AS hr_employee_id,
    TRIM(e.first_name || ' ' || e.last_name)                             AS employee_full_name,
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)      AS compensation_manager_id,
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
    ON pr.org_id         = c.org_id
   AND pr.hr_employee_id = c.hr_employee_id
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

GRANT SELECT ON public.hr_payroll_employee_comparison TO authenticated;

COMMENT ON VIEW public.hr_payroll_employee_comparison IS
    'Per-employee snapshot (one row per employee, aggregated across tasks) for the most recent is_standard=TRUE HRB check_date with deltas vs the prior is_standard=TRUE check_date. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees direct reports + self; Team Lead has $ columns NULL-masked. Org isolation via security_invoker.';
