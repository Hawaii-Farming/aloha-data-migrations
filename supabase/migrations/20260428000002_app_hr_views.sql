-- Joined views for the HR sub-modules
-- ====================================
-- The HR list grids (Scheduler / Time Off / Employee Review) want a single
-- denormalized row per record carrying joined employee + department info.
-- Rather than push joins into the loader on every page request, these views
-- pre-join the FKs so the frontend can `.select('*')` and render directly.
--
-- All three are security_invoker so per-table RLS still gates the rows.
-- Joined display fields use COALESCE(preferred_name, first_name || ' ' || last_name)
-- so employees without a preferred name still show a usable label.

-- ============================================================
-- ops_task_weekly_schedule (rebuilt with employee display fields)
-- ============================================================
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
    MAX(CASE WHEN sb.day_of_week = 0 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS sunday,
    MAX(CASE WHEN sb.day_of_week = 1 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS monday,
    MAX(CASE WHEN sb.day_of_week = 2 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS tuesday,
    MAX(CASE WHEN sb.day_of_week = 3 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS wednesday,
    MAX(CASE WHEN sb.day_of_week = 4 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS thursday,
    MAX(CASE WHEN sb.day_of_week = 5 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS friday,
    MAX(CASE WHEN sb.day_of_week = 6 THEN TO_CHAR(sb.schedule_start AT TIME ZONE 'UTC', 'HH24:MI')
             || CASE WHEN sb.schedule_stop IS NOT NULL THEN ' - ' || TO_CHAR(sb.schedule_stop AT TIME ZONE 'UTC', 'HH24:MI') ELSE '' END END) AS saturday,
    ROUND(SUM(COALESCE(sb.schedule_total_hours,
        CASE WHEN sb.schedule_stop IS NOT NULL
             THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
             ELSE 0 END))::NUMERIC, 2)                                      AS total_hours,
    CASE WHEN e.overtime_threshold IS NOT NULL
         THEN ROUND((e.overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE NULL END                                                      AS ot_threshold_weekly,
    CASE WHEN e.overtime_threshold IS NOT NULL
         THEN ROUND(SUM(COALESCE(sb.schedule_total_hours,
                CASE WHEN sb.schedule_stop IS NOT NULL
                     THEN EXTRACT(EPOCH FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0
                     ELSE 0 END))::NUMERIC, 2)
              > ROUND((e.overtime_threshold / 2.0)::NUMERIC, 2)
         ELSE false END                                                     AS is_over_ot_threshold
FROM schedule_base sb
JOIN hr_employee e  ON e.id = sb.hr_employee_id
JOIN ops_task    t  ON t.id = sb.ops_task_id
GROUP BY
    sb.week_start_date, sb.org_id, sb.farm_id,
    e.id, e.preferred_name, e.first_name, e.last_name, e.profile_photo_url,
    e.hr_department_id, e.hr_work_authorization_id, e.overtime_threshold,
    t.id
ORDER BY sb.week_start_date, full_name;

GRANT SELECT ON public.ops_task_weekly_schedule TO authenticated;

COMMENT ON VIEW public.ops_task_weekly_schedule IS 'Weekly schedule grid: one row per (employee, task, week) with day-by-day shift strings, weekly totals, and the OT threshold flag. Joined employee display fields included for the grid renderer.';

-- ============================================================
-- app_hr_time_off_requests
-- ============================================================
CREATE OR REPLACE VIEW public.app_hr_time_off_requests
WITH (security_invoker = true) AS
SELECT
    r.*,
    COALESCE(NULLIF(e.preferred_name, ''),
             TRIM(e.first_name || ' ' || e.last_name))                      AS full_name,
    e.profile_photo_url,
    e.hr_department_id                                                      AS department_name,
    e.hr_work_authorization_id                                              AS work_authorization_name,
    e.compensation_manager_id,
    COALESCE(NULLIF(req.preferred_name, ''),
             TRIM(req.first_name || ' ' || req.last_name))                  AS requested_by_name,
    COALESCE(NULLIF(rev.preferred_name, ''),
             TRIM(rev.first_name || ' ' || rev.last_name))                  AS reviewed_by_name
FROM hr_time_off_request r
JOIN hr_employee e   ON e.id = r.hr_employee_id
LEFT JOIN hr_employee req ON req.id = r.requested_by
LEFT JOIN hr_employee rev ON rev.id = r.reviewed_by
WHERE r.is_deleted = false;

GRANT SELECT ON public.app_hr_time_off_requests TO authenticated;

COMMENT ON VIEW public.app_hr_time_off_requests IS 'Time-off request grid: every hr_time_off_request row joined with the subject employee (full_name, profile photo, department, work auth, comp manager) and the requester/reviewer display names.';

-- ============================================================
-- app_hr_employee_reviews
-- ============================================================
CREATE OR REPLACE VIEW public.app_hr_employee_reviews
WITH (security_invoker = true) AS
SELECT
    r.*,
    COALESCE(NULLIF(e.preferred_name, ''),
             TRIM(e.first_name || ' ' || e.last_name))                      AS full_name,
    e.profile_photo_url,
    e.hr_department_id                                                      AS department_name,
    e.start_date,
    'Q' || r.review_quarter || ' ' || r.review_year                         AS quarter_label,
    COALESCE(NULLIF(lead.preferred_name, ''),
             TRIM(lead.first_name || ' ' || lead.last_name))                AS lead_name
FROM hr_employee_review r
JOIN hr_employee e         ON e.id = r.hr_employee_id
LEFT JOIN hr_employee lead ON lead.id = r.lead_id
WHERE r.is_deleted = false;

GRANT SELECT ON public.app_hr_employee_reviews TO authenticated;

COMMENT ON VIEW public.app_hr_employee_reviews IS 'Employee review grid: every hr_employee_review row joined with the subject employee (full_name, profile photo, department, start_date) and the review lead display name. quarter_label is "Q<n> <year>".';
