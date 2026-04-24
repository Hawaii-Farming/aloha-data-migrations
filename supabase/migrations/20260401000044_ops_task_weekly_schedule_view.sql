CREATE OR REPLACE VIEW ops_task_weekly_schedule
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
    e.hr_department_id,
    e.hr_work_authorization_id,
    t.name                                                                  AS task,

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
    e.id,
    e.hr_department_id,
    e.hr_work_authorization_id,
    e.overtime_threshold,
    t.name
ORDER BY
    sb.week_start_date,
    e.id;
