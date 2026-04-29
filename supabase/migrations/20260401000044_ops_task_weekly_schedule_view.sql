-- ops_task_weekly_schedule
-- ========================
-- Weekly schedule grid: one row per (employee, task, week) with each
-- day's shift formatted as "HH:MM - HH:MM", weekly totals, and the
-- bi-weekly OT threshold halved + the over-threshold flag.
--
-- Joined employee display fields (full_name, profile_photo_url,
-- department_name, work_authorization_name) are surfaced here so the
-- ag-grid renderer can read them off the row directly without an
-- additional embed.

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
)
SELECT
    sb.org_id,
    sb.week_start_date,
    e.id                                                                    AS hr_employee_id,
    COALESCE(NULLIF(e.preferred_name, ''),
             TRIM(e.first_name || ' ' || e.last_name))                      AS full_name,
    e.profile_photo_url,
    e.hr_department_id,
    e.hr_department_id                                                      AS department_name,
    e.hr_work_authorization_id,
    e.hr_work_authorization_id                                              AS work_authorization_name,
    t.id                                                                    AS task,

    -- Day columns — formatted as "HH:MM - HH:MM"; null when employee is not scheduled that day
    MAX(CASE WHEN sb.day_of_week = 0
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS sunday,
    MAX(CASE WHEN sb.day_of_week = 1
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS monday,
    MAX(CASE WHEN sb.day_of_week = 2
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS tuesday,
    MAX(CASE WHEN sb.day_of_week = 3
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS wednesday,
    MAX(CASE WHEN sb.day_of_week = 4
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS thursday,
    MAX(CASE WHEN sb.day_of_week = 5
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS friday,
    MAX(CASE WHEN sb.day_of_week = 6
        THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI')
                     ELSE '' END END)                                       AS saturday,

    -- Total planned hours for the week — uses ops_task_schedule.total_hours
    -- (captured from the sheet's daily Hours column which already has the
    -- 30-min lunch deduction). Falls back to stop-start only when the
    -- lunch-adjusted value isn't available.
    ROUND(
        SUM(COALESCE(
            sb.schedule_total_hours,
            CASE WHEN sb.schedule_stop IS NOT NULL
                 THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
                 ELSE 0 END
        ))::NUMERIC, 2
    )                                                                       AS total_hours,

    -- Weekly OT threshold — the bi-weekly threshold halved; null if not set on employee
    CASE WHEN e.overtime_threshold IS NOT NULL
         THEN ROUND((e.overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE NULL END                                                      AS ot_threshold_weekly,

    -- OT flag — true when total planned weekly hours exceed the weekly threshold
    CASE WHEN e.overtime_threshold IS NOT NULL
         THEN ROUND(
                  SUM(COALESCE(
                      sb.schedule_total_hours,
                      CASE WHEN sb.schedule_stop IS NOT NULL
                           THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
                           ELSE 0 END
                  ))::NUMERIC, 2
              ) > ROUND((e.overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE false END                                                     AS is_over_ot_threshold

FROM schedule_base sb
JOIN hr_employee e  ON e.id = sb.hr_employee_id
JOIN ops_task    t  ON t.id = sb.ops_task_id
GROUP BY
    sb.week_start_date,
    sb.org_id,
    sb.farm_id,
    e.id, e.preferred_name, e.first_name, e.last_name, e.profile_photo_url,
    e.hr_department_id,
    e.hr_work_authorization_id,
    e.overtime_threshold,
    t.id
ORDER BY
    sb.week_start_date,
    full_name;

GRANT SELECT ON public.ops_task_weekly_schedule TO authenticated;

COMMENT ON VIEW public.ops_task_weekly_schedule IS 'Weekly schedule grid: one row per (employee, task, week) with day-by-day shift strings, weekly totals, and the OT threshold flag. Joined employee display fields (full_name, profile_photo_url, department_name, work_authorization_name) are pre-flattened for the ag-grid renderer.';
