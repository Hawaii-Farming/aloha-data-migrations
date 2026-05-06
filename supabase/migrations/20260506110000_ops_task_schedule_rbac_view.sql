-- ops_task_weekly_schedule — RBAC row-scope
-- =========================================
-- Layers an access-level WHERE clause on top of the wall-clock view
-- shipped in 20260501140000_ops_task_schedule_wallclock.sql. Owner /
-- Admin retain full org visibility; Manager / Team Lead see only
-- their own row plus direct reports (hr_employee.team_lead_id =
-- auth_employee_id(org_id)); Employee tier sees nothing (the nav
-- gate in 20260506110200_ops_task_schedule_nav_gate.sql also hides
-- the Scheduler entry from the sidebar).
--
-- Reuses public.auth_employee_id(TEXT) and public.auth_access_level(TEXT)
-- SECURITY DEFINER STABLE helpers from 20260501120000_hr_payroll_rbac_helpers.sql.
--
-- security_invoker = true is preserved — base-table org RLS still
-- applies (org_id IN get_user_org_ids()).

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
      AND (
        -- Owner / Admin: full org visibility (org RLS still applies via security_invoker)
        public.auth_access_level(s.org_id) IN ('Owner', 'Admin')
        -- Manager / Team Lead: self + direct reports
        OR (
            public.auth_access_level(s.org_id) IN ('Manager', 'Team Lead')
            AND (
                s.hr_employee_id = public.auth_employee_id(s.org_id)
                OR EXISTS (
                    SELECT 1 FROM public.hr_employee e
                    WHERE e.id = s.hr_employee_id
                      AND e.org_id = s.org_id
                      AND e.team_lead_id = public.auth_employee_id(s.org_id)
                      AND e.is_deleted = false
                )
            )
        )
        -- Employee tier matches no branch -> empty result set
      )
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
    'wall-clock TIMESTAMP columns directly — no time zone conversion. '
    'RBAC-gated: Owner/Admin see all org rows; Manager/Team Lead see '
    'self + direct reports (hr_employee.team_lead_id = self); '
    'Employee tier returns no rows.';
