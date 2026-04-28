-- Drop the helper views the HR list grids no longer use.
-- Time Off and Employee Review query the base tables directly with
-- postgrest embeds for joined display fields. Keeping these views
-- around would just be a parallel surface that drifts. The Scheduler
-- view ops_task_weekly_schedule is still needed (it aggregates daily
-- shift columns that aren't representable as embeds).

DROP VIEW IF EXISTS public.app_hr_time_off_requests;
DROP VIEW IF EXISTS public.app_hr_employee_reviews;
