-- ops_task_weekly_schedule
-- ========================
-- Weekly schedule grid: one row per (employee, task, week) with each
-- day's shift formatted as "HH:MM - HH:MM", per-row weekly totals for
-- THAT task, the bi-weekly OT threshold halved, and a text status for
-- row coloring driven by the employee's CUMULATIVE hours across all
-- tasks in the week (not just the row's task).
--
-- Joined employee display fields (full_name, profile_photo_url) are
-- surfaced here so the ag-grid renderer can read them off the row
-- directly without an additional embed.

CREATE OR REPLACE VIEW public.ops_task_weekly_schedule
WITH (security_invoker = true) AS
WITH schedule_base AS (
    -- Planned schedule entries only (no tracker linked).
    -- Derives the task date from start_time and the Sunday-anchored week start date.
    SELECT
        s.hr_employee_id,
        s.ops_task_id,
        s.org_id,
        s.farm_id,
        s.start_time                                                        AS schedule_start,
        s.stop_time                                                         AS schedule_stop,
        s.total_hours                                                       AS schedule_total_hours,
        s.start_time::DATE                                                  AS task_date,
        EXTRACT(DOW FROM s.start_time)::INTEGER                             AS day_of_week,
        (s.start_time::DATE - EXTRACT(DOW FROM s.start_time)::INTEGER)      AS week_start_date
    FROM ops_task_schedule s
    WHERE s.ops_task_tracker_id IS NULL
      AND s.start_time IS NOT NULL
      AND s.is_deleted = false
),
per_task AS (
    SELECT
        sb.org_id,
        sb.week_start_date,
        e.id                                                                AS hr_employee_id,
        -- full_name uses first + last only. Preferred name is intentionally
        -- not used here -- the schedule grid is a payroll/manager view where
        -- legal name matters more than nickname.
        TRIM(e.first_name || ' ' || e.last_name)                            AS full_name,
        e.profile_photo_url,
        e.overtime_threshold,
        t.id                                                                AS task,

        -- Day columns formatted as "HH:MM - HH:MM"; null when employee not scheduled that day
        MAX(CASE WHEN sb.day_of_week = 0
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS sunday,
        MAX(CASE WHEN sb.day_of_week = 1
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS monday,
        MAX(CASE WHEN sb.day_of_week = 2
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS tuesday,
        MAX(CASE WHEN sb.day_of_week = 3
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS wednesday,
        MAX(CASE WHEN sb.day_of_week = 4
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS thursday,
        MAX(CASE WHEN sb.day_of_week = 5
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS friday,
        MAX(CASE WHEN sb.day_of_week = 6
            THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
                 || CASE WHEN sb.schedule_stop IS NOT NULL
                         THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                         ELSE '' END END)                                   AS saturday,

        -- Per-row total: hours this employee has on THIS task in this week.
        -- Uses ops_task_schedule.total_hours when set (already lunch-adjusted)
        -- and falls back to stop-start when not.
        ROUND(
            SUM(COALESCE(
                sb.schedule_total_hours,
                CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
                     ELSE 0 END
            ))::NUMERIC, 2
        )                                                                   AS total_hours
    FROM schedule_base sb
    JOIN hr_employee e  ON e.id = sb.hr_employee_id
    JOIN ops_task    t  ON t.id = sb.ops_task_id
    GROUP BY
        sb.week_start_date, sb.org_id, sb.farm_id,
        e.id, e.first_name, e.last_name, e.profile_photo_url,
        e.overtime_threshold,
        t.id
)
SELECT
    org_id,
    week_start_date,
    hr_employee_id,
    full_name,
    profile_photo_url,
    task,
    sunday, monday, tuesday, wednesday, thursday, friday, saturday,
    total_hours,

    -- Weekly OT threshold = bi-weekly threshold halved; null if not set on employee.
    CASE WHEN overtime_threshold IS NOT NULL
         THEN ROUND((overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE NULL END                                                      AS ot_threshold_weekly,

    -- OT status driven by the employee's CUMULATIVE weekly hours across
    -- every task, not just this row's task. Window-summed over (employee,
    -- week) so an employee split across multiple tasks is evaluated on
    -- their total, not on each task in isolation.
    --   'above'  -> cumulative weekly hours strictly exceed the threshold
    --               (the operator owes overtime pay)
    --   'at'     -> cumulative weekly hours land exactly on the threshold
    --               (no OT yet, but the next minute is overtime)
    --   'below'  -> cumulative weekly hours are strictly under the threshold
    --   NULL     -> no overtime_threshold set on the employee
    CASE
        WHEN overtime_threshold IS NULL THEN NULL
        WHEN ROUND(
                  SUM(total_hours) OVER (
                      PARTITION BY hr_employee_id, week_start_date
                  )::NUMERIC, 2
             ) > ROUND((overtime_threshold / 2.0)::NUMERIC, 2)
            THEN 'above'
        WHEN ROUND(
                  SUM(total_hours) OVER (
                      PARTITION BY hr_employee_id, week_start_date
                  )::NUMERIC, 2
             ) = ROUND((overtime_threshold / 2.0)::NUMERIC, 2)
            THEN 'at'
        ELSE 'below'
    END                                                                     AS ot_status

FROM per_task
ORDER BY
    week_start_date,
    full_name;

GRANT SELECT ON public.ops_task_weekly_schedule TO authenticated;

COMMENT ON VIEW public.ops_task_weekly_schedule IS 'Weekly schedule grid: one row per (employee, task, week) with day-by-day shift strings. total_hours is per-row (this task only); ot_status reflects the employee''s cumulative weekly hours across ALL tasks (''above'' / ''at'' / ''below'' / NULL) so an employee split across multiple tasks is evaluated on their week total. Joined employee display fields (full_name = first + last, profile_photo_url) are pre-flattened for the ag-grid renderer.';
