-- Revert: ops_task_weekly_schedule RBAC view rewrite
-- ====================================================
-- Restores the wall-clock view definition (no RBAC predicate) shipped
-- in 20260501140000_ops_task_schedule_wallclock.sql. Pairs with the
-- policy and nav-gate reverts shipped alongside this migration.
--
-- Rationale: product decision to drop scheduler RBAC; binary
-- requireSubModuleAccess gate is sufficient.

DROP VIEW IF EXISTS public.ops_task_weekly_schedule;

CREATE VIEW public.ops_task_weekly_schedule
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
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
                     ELSE '' END END)                                       AS sunday,
    MAX(CASE WHEN sb.day_of_week = 1
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
                     ELSE '' END END)                                       AS monday,
    MAX(CASE WHEN sb.day_of_week = 2
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
                     ELSE '' END END)                                       AS tuesday,
    MAX(CASE WHEN sb.day_of_week = 3
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
                     ELSE '' END END)                                       AS wednesday,
    MAX(CASE WHEN sb.day_of_week = 4
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
                     ELSE '' END END)                                       AS thursday,
    MAX(CASE WHEN sb.day_of_week = 5
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
                     ELSE '' END END)                                       AS friday,
    MAX(CASE WHEN sb.day_of_week = 6
        THEN TO_CHAR(sb.schedule_start, 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN ' - ' || TO_CHAR(sb.schedule_stop, 'HH24:MI')
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

COMMENT ON VIEW public.ops_task_weekly_schedule IS
    'Weekly schedule grid: one row per (employee, task, week) with '
    'day-by-day shift strings, weekly totals, OT threshold flag, and '
    'farm_name (ops_task.farm_id) for the day-cell renderer. Sources '
    'wall-clock TIMESTAMP columns directly — no time zone conversion.';
