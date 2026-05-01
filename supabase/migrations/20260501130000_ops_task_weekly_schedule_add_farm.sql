-- ops_task_weekly_schedule — add farm_name
-- =========================================
-- Surfaces ops_task.farm_id as farm_name so the scheduler day-cell
-- renderer can show the farm (e.g. "Cuke", "Lettuce") instead of the
-- ops_task identifier (e.g. "CUKE PH", "Lettuce PH").
--
-- CREATE OR REPLACE VIEW only allows appending columns at the end of
-- the SELECT list — farm_name is added as the final column.

CREATE OR REPLACE VIEW public.ops_task_weekly_schedule
WITH (security_invoker = true) AS
WITH schedule_base AS (
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

    ROUND(
        SUM(COALESCE(
            sb.schedule_total_hours,
            CASE WHEN sb.schedule_stop IS NOT NULL
                 THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
                 ELSE 0 END
        ))::NUMERIC, 2
    )                                                                       AS total_hours,

    CASE WHEN e.overtime_threshold IS NOT NULL
         THEN ROUND((e.overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE NULL END                                                      AS ot_threshold_weekly,

    CASE WHEN e.overtime_threshold IS NOT NULL
         THEN ROUND(
                  SUM(COALESCE(
                      sb.schedule_total_hours,
                      CASE WHEN sb.schedule_stop IS NOT NULL
                           THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
                           ELSE 0 END
                  ))::NUMERIC, 2
              ) > ROUND((e.overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE false END                                                     AS is_over_ot_threshold,

    -- Farm name (ops_task.farm_id → org_farm.id) — the scheduler day-cell
    -- shows this on its first line in muted color.
    t.farm_id                                                               AS farm_name

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
    t.id,
    t.farm_id
ORDER BY
    sb.week_start_date,
    full_name;

GRANT SELECT ON public.ops_task_weekly_schedule TO authenticated;

COMMENT ON VIEW public.ops_task_weekly_schedule IS 'Weekly schedule grid: one row per (employee, task, week) with day-by-day shift strings, weekly totals, OT threshold flag, and farm_name (ops_task.farm_id) for the day-cell renderer.';
