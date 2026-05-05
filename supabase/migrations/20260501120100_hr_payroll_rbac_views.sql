-- hr_payroll_rbac_views
-- =====================
-- Three views, all WITH (security_invoker = true), all gated by the
-- helpers in 20260501120000_hr_payroll_rbac_helpers.sql:
--
--   1. hr_payroll_employee_comparison  (rewrite of 20260401000073)
--   2. hr_payroll_task_comparison       (rewrite — definition pulled from
--                                        the hosted DB; not previously in
--                                        version control)
--   3. hr_payroll_data_secure           (NEW wrapper over hr_payroll for
--                                        the Payroll Data sub-module)
--
-- Visibility matrix enforced by the WHERE / CASE clauses below:
--   Owner / Admin   - all rows, all columns
--   Manager         - rows where the comp manager is the caller (plus self
--                     where the view exposes hr_employee_id), all columns
--   Team Lead       - all rows, hours columns visible, dollar columns NULL
--   Employee        - blocked at the sidebar layer (nav-gate migration);
--                     direct PostgREST hits return zero rows because their
--                     access level matches none of the WHERE branches
--
-- security_invoker = true keeps the existing org-isolation RLS on
-- hr_payroll / hr_employee in force; this layer SUPPLEMENTS it.
--
-- DROP first because column lists / order changed vs. the previous
-- definitions (CASE-wrapped $ columns) and CREATE OR REPLACE refuses
-- to rename columns. Idempotent on fresh DBs.

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
    COALESCE(c.compensation_manager_id, pr.compensation_manager_id)      AS compensation_manager_id,
    COALESCE(c.task, pr.task)                                            AS task,
    COALESCE(c.status, pr.status)                                        AS status,
    COALESCE(c.workers_compensation_code, pr.workers_compensation_code)  AS workers_compensation_code,
    (SELECT cur_date FROM periods)                                       AS check_date,

    -- Hours (always visible) -- rounded to whole hours for display.
    ROUND(COALESCE(c.scheduled_hours, 0))                                AS scheduled_hours,
    ROUND(COALESCE(c.total_hours, 0))                                    AS total_hours,
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
--    Source: pg_get_viewdef on hosted DB (not previously version-controlled).
--    Per-task aggregate (no hr_employee_id column) — Manager scope is
--    compensation_manager only, no self branch.
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
    COALESCE(c.task, pr.task)                                           AS task,
    COALESCE(c.status, pr.status)                                       AS status,
    (SELECT periods.cur_date FROM periods)                              AS check_date,

    -- Hours (always visible) -- rounded to whole hours for display.
    ROUND(COALESCE(c.scheduled_hours, 0::numeric))                      AS scheduled_hours,
    ROUND(COALESCE(c.total_hours, 0::numeric))                          AS total_hours,
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
WHERE
    public.auth_access_level(COALESCE(c.org_id, pr.org_id)) IN ('Owner', 'Admin', 'Team Lead')
    OR (
        public.auth_access_level(COALESCE(c.org_id, pr.org_id)) = 'Manager'
        AND COALESCE(c.compensation_manager_id, pr.compensation_manager_id)
              = public.auth_employee_id(COALESCE(c.org_id, pr.org_id))
    );

GRANT SELECT ON hr_payroll_task_comparison TO authenticated;

COMMENT ON VIEW hr_payroll_task_comparison IS 'Per-task (no employee dimension) snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior period. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees only rows where they are the compensation manager; Team Lead has $ columns NULL-masked.';

----------------------------------------------------------------------
-- 3. hr_payroll_data_secure  (NEW)
--    Wrapping view over hr_payroll for the Payroll Data sub-module.
--    Row scope + dollar masking applied at the DB layer so PostgREST
--    direct calls and CSV exports honor the same matrix as the grids.
----------------------------------------------------------------------
CREATE OR REPLACE VIEW public.hr_payroll_data_secure
WITH (security_invoker = true) AS
SELECT
    id, org_id, hr_employee_id, payroll_id,
    pay_period_start, pay_period_end, check_date, invoice_number,
    payroll_processor, is_standard,
    employee_name, hr_department_id, hr_work_authorization_id, wc, pay_structure,
    overtime_threshold,

    -- Hours (always visible)
    regular_hours, overtime_hours, discretionary_overtime_hours,
    holiday_hours, pto_hours, sick_hours, funeral_hours,
    total_hours, pto_hours_accrued,

    -- Dollars (NULL for Team Lead)
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE hourly_rate END AS hourly_rate,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE regular_pay END AS regular_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE overtime_pay END AS overtime_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE discretionary_overtime_pay END AS discretionary_overtime_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE holiday_pay END AS holiday_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE pto_pay END AS pto_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE sick_pay END AS sick_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE funeral_pay END AS funeral_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE other_pay END AS other_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE bonus_pay END AS bonus_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE auto_allowance END AS auto_allowance,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE per_diem END AS per_diem,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE salary END AS salary,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE gross_wage END AS gross_wage,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE fit END AS fit,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE sit END AS sit,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE social_security END AS social_security,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE medicare END AS medicare,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE comp_plus END AS comp_plus,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE hds_dental END AS hds_dental,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE pre_tax_401k END AS pre_tax_401k,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE auto_deduction END AS auto_deduction,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE child_support END AS child_support,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE program_fees END AS program_fees,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE net_pay END AS net_pay,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE labor_tax END AS labor_tax,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE other_tax END AS other_tax,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE workers_compensation END AS workers_compensation,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE health_benefits END AS health_benefits,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE other_health_charges END AS other_health_charges,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE admin_fees END AS admin_fees,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE hawaii_get END AS hawaii_get,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE other_charges END AS other_charges,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE tdi END AS tdi,
    CASE WHEN public.auth_access_level(org_id) = 'Team Lead' THEN NULL ELSE total_cost END AS total_cost,

    created_at, created_by, updated_at, updated_by, is_deleted
FROM public.hr_payroll
WHERE
    is_deleted = false
    AND (
        public.auth_access_level(org_id) IN ('Owner', 'Admin', 'Team Lead')
        OR (
            public.auth_access_level(org_id) = 'Manager'
            AND (
                hr_employee_id = public.auth_employee_id(org_id)
                OR EXISTS (
                    SELECT 1 FROM public.hr_employee e
                    WHERE e.id = hr_payroll.hr_employee_id
                      AND e.compensation_manager_id = public.auth_employee_id(org_id)
                )
            )
        )
    );

GRANT SELECT ON public.hr_payroll_data_secure TO authenticated;

COMMENT ON VIEW public.hr_payroll_data_secure IS
  'RBAC-gated wrapper over hr_payroll for the Payroll Data sub-module: row scope per access level (Owner/Admin/Team Lead see all; Manager sees direct reports + self), $ columns NULL for Team Lead. Reads via security_invoker so existing org-isolation RLS still applies. Frontend (hr-payroll-data.config.tsx views.list) reads this instead of the base table.';
