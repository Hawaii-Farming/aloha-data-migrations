-- Payroll vs planned-schedule comparison with cost attribution by QuickBooks account.
-- One row per (check_date, hr_employee_id, qb_account bucket).
-- Faithfully recreates the legacy `payrollSchedComparison` Apps Script output:
-- columns, math, and edge cases match the legacy hr_ee_payroll_by_tasks tab.

CREATE OR REPLACE VIEW hr_payroll_schedule_comparison AS
WITH payroll_grouped AS (
    SELECT
        p.org_id,
        p.hr_employee_id,
        p.check_date,
        MIN(p.pay_period_start) AS pay_period_start,
        MAX(p.pay_period_end)   AS pay_period_end,
        MAX(p.wc)               AS wc,
        SUM(p.total_hours)                  AS total_hours,
        SUM(p.regular_hours)                AS regular_hours,
        SUM(p.pto_hours)                    AS pto_hours,
        SUM(p.discretionary_overtime_hours) AS discretionary_overtime_hours,
        SUM(p.total_cost)                   AS total_cost,
        SUM(p.regular_pay)                  AS regular_pay,
        SUM(p.discretionary_overtime_pay)   AS discretionary_overtime_pay
    FROM hr_payroll p
    WHERE p.is_deleted = false
    GROUP BY p.org_id, p.hr_employee_id, p.check_date
),
schedule_buckets AS (
    -- Each schedule row = one shift day. Subtract a 0.5 hr unpaid lunch only
    -- when the shift crosses noon (start before 12:00 AND stop after 12:00),
    -- matching the legacy hr_ee_sched_weekly TotalHours convention.
    SELECT
        pg.org_id,
        pg.hr_employee_id,
        pg.check_date,
        COALESCE(NULLIF(TRIM(t.qb_account), ''), d.name) AS qb_account,
        SUM(
            EXTRACT(EPOCH FROM (s.stop_time - s.start_time)) / 3600.0
            - CASE
                WHEN s.start_time::time < TIME '12:00:00'
                 AND s.stop_time::time  > TIME '12:00:00'
                THEN 0.5
                ELSE 0
              END
        )::NUMERIC AS scheduled_hours
    FROM payroll_grouped pg
    JOIN hr_employee e        ON e.id = pg.hr_employee_id
    LEFT JOIN hr_department d ON d.id = e.hr_department_id
    JOIN ops_task_schedule s
        ON s.org_id = pg.org_id
       AND s.hr_employee_id = pg.hr_employee_id
       AND s.ops_task_tracker_id IS NULL
       AND s.is_deleted = false
       AND s.stop_time IS NOT NULL
       AND s.start_time::date BETWEEN pg.pay_period_start AND pg.pay_period_end
    JOIN ops_task t ON t.id = s.ops_task_id
    GROUP BY pg.org_id, pg.hr_employee_id, pg.check_date,
             COALESCE(NULLIF(TRIM(t.qb_account), ''), d.name)
),
schedule_totals AS (
    SELECT
        org_id, hr_employee_id, check_date,
        SUM(scheduled_hours) AS total_scheduled_hours
    FROM schedule_buckets
    GROUP BY org_id, hr_employee_id, check_date
),
split_rows AS (
    -- One row per (payroll, bucket). Ratio = bucket's share of total scheduled
    -- hours. Payroll hours/pay are split by that ratio, matching legacy.
    SELECT
        pg.org_id,
        pg.hr_employee_id,
        pg.check_date,
        pg.wc,
        sb.qb_account,
        sb.scheduled_hours,
        CASE
            WHEN st.total_scheduled_hours > 0
            THEN sb.scheduled_hours / st.total_scheduled_hours
            ELSE 0
        END AS ratio,
        pg.total_hours, pg.regular_hours, pg.pto_hours, pg.discretionary_overtime_hours,
        pg.total_cost,  pg.regular_pay,  pg.discretionary_overtime_pay
    FROM payroll_grouped pg
    JOIN schedule_buckets sb USING (org_id, hr_employee_id, check_date)
    JOIN schedule_totals  st USING (org_id, hr_employee_id, check_date)
    -- Legacy skips split rows where payroll total_cost is 0 (they add noise
    -- without adding signal; no_schedule_rows still emits zero-cost rows).
    WHERE pg.total_cost <> 0
),
no_schedule_rows AS (
    -- One row per payroll record that had no matching planned-schedule entries
    -- in the pay period. Bucket falls back to the employee's department, and
    -- payroll values pass through in full (not split).
    SELECT
        pg.org_id,
        pg.hr_employee_id,
        pg.check_date,
        pg.wc,
        d.name     AS qb_account,
        0::NUMERIC AS scheduled_hours,
        1::NUMERIC AS ratio,
        pg.total_hours, pg.regular_hours, pg.pto_hours, pg.discretionary_overtime_hours,
        pg.total_cost,  pg.regular_pay,  pg.discretionary_overtime_pay
    FROM payroll_grouped pg
    JOIN hr_employee e        ON e.id = pg.hr_employee_id
    LEFT JOIN hr_department d ON d.id = e.hr_department_id
    WHERE NOT EXISTS (
        SELECT 1 FROM schedule_buckets sb
        WHERE sb.org_id = pg.org_id
          AND sb.hr_employee_id = pg.hr_employee_id
          AND sb.check_date = pg.check_date
    )
),
combined AS (
    SELECT * FROM split_rows
    UNION ALL
    SELECT * FROM no_schedule_rows
)
SELECT
    c.org_id,
    c.check_date,
    e.first_name || ' ' || e.last_name   AS full_name,
    (sal.id = 'manager')                 AS is_manager,
    cm.first_name || ' ' || cm.last_name AS compensation_manager,
    wa.name                              AS status,
    c.wc                                 AS workers_compensation_code,
    c.qb_account,
    ROUND(c.scheduled_hours, 2) AS scheduled_hours,
    -- total_hours: scaled bucket hours normally; falls back to pto_hours when
    -- the pay period has no worked hours but PTO was paid; 0 when nothing.
    ROUND(
        CASE
            WHEN c.total_hours > 0 THEN c.total_hours * c.ratio
            WHEN c.pto_hours   > 0 THEN c.pto_hours
            ELSE 0
        END, 2
    ) AS total_hours,
    ROUND(c.regular_hours                * c.ratio, 2) AS regular_hours,
    ROUND(c.discretionary_overtime_hours * c.ratio, 2) AS discretionary_overtime_hours,
    -- total_cost: scaled bucket cost when there are worked hours; otherwise
    -- passes through the full payroll cost (unsplit) — matches legacy.
    ROUND(
        CASE
            WHEN c.total_hours > 0 THEN c.total_cost * c.ratio
            ELSE c.total_cost
        END, 2
    ) AS total_cost,
    ROUND(c.regular_pay                * c.ratio, 2) AS regular_pay,
    ROUND(c.discretionary_overtime_pay * c.ratio, 2) AS discretionary_overtime_pay
FROM combined c
JOIN hr_employee e                 ON e.id = c.hr_employee_id
LEFT JOIN hr_work_authorization wa ON wa.id = e.hr_work_authorization_id
LEFT JOIN hr_employee cm           ON cm.id = e.compensation_manager_id
LEFT JOIN sys_access_level sal     ON sal.id = e.sys_access_level_id;

GRANT SELECT ON hr_payroll_schedule_comparison TO authenticated;
