-- Hours comparison view: scheduled hours (ops_task_schedule) vs payroll hours (hr_payroll)
-- per employee per pay period, with variance calculation

CREATE OR REPLACE VIEW app_hr_hours_comparison AS
WITH schedule_agg AS (
    SELECT
        s.org_id,
        s.hr_employee_id,
        p.pay_period_start,
        p.pay_period_end,
        ROUND(
            SUM(
                CASE
                    WHEN s.stop_time IS NOT NULL
                    THEN EXTRACT(EPOCH FROM (s.stop_time - s.start_time)) / 3600.0
                    ELSE 0
                END
            )::NUMERIC,
            2
        ) AS scheduled_hours
    FROM ops_task_schedule s
    INNER JOIN (
        SELECT DISTINCT org_id, pay_period_start, pay_period_end
        FROM hr_payroll
        WHERE is_deleted = false
    ) p ON s.org_id = p.org_id
        AND s.start_time::DATE >= p.pay_period_start
        AND s.start_time::DATE <= p.pay_period_end
    WHERE s.is_deleted = false
      AND s.start_time IS NOT NULL
    GROUP BY s.org_id, s.hr_employee_id, p.pay_period_start, p.pay_period_end
),
payroll_agg AS (
    SELECT
        org_id,
        hr_employee_id,
        pay_period_start,
        pay_period_end,
        SUM(total_hours) AS payroll_hours
    FROM hr_payroll
    WHERE is_deleted = false
    GROUP BY org_id, hr_employee_id, pay_period_start, pay_period_end
)
SELECT
    COALESCE(sa.org_id, pa.org_id) AS org_id,
    COALESCE(sa.hr_employee_id, pa.hr_employee_id) AS hr_employee_id,
    COALESCE(sa.pay_period_start, pa.pay_period_start) AS pay_period_start,
    COALESCE(sa.pay_period_end, pa.pay_period_end) AS pay_period_end,
    e.first_name || ' ' || e.last_name AS full_name,
    e.profile_photo_url,
    d.name AS department_name,
    COALESCE(sa.scheduled_hours, 0) AS scheduled_hours,
    COALESCE(pa.payroll_hours, 0) AS payroll_hours,
    ROUND((COALESCE(pa.payroll_hours, 0) - COALESCE(sa.scheduled_hours, 0))::NUMERIC, 2) AS variance
FROM schedule_agg sa
FULL OUTER JOIN payroll_agg pa
    ON sa.org_id = pa.org_id
    AND sa.hr_employee_id = pa.hr_employee_id
    AND sa.pay_period_start = pa.pay_period_start
    AND sa.pay_period_end = pa.pay_period_end
JOIN hr_employee e
    ON e.id = COALESCE(sa.hr_employee_id, pa.hr_employee_id)
    AND e.is_deleted = false
LEFT JOIN hr_department d
    ON d.id = e.hr_department_id;

GRANT SELECT ON app_hr_hours_comparison TO authenticated;
