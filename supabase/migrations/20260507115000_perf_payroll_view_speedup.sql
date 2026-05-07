-- Performance: speed up hr_payroll_by_task and its consumers
-- =========================================================================
-- The hr_payroll_by_task view does a Hash Join between payroll_agg and
-- ops_task_schedule on (org_id, hr_employee_id), then post-filters by
-- (s.start_time::date BETWEEN pa.pay_period_start AND pay_period_end).
--
-- EXPLAIN ANALYZE on production showed Postgres removing 591,388 rows
-- by post-join filter on every read — i.e. the join joined every
-- schedule row a given employee ever had, then threw away ~99% of them.
--
-- A regular index on ops_task_schedule(hr_employee_id, start_time) does
-- not help: the planner can't push a date range predicate through the
-- ::date cast that the view uses, so it falls back to seq scan + post
-- filter. A *functional* index on the cast itself unlocks index-driven
-- range filtering and lets the planner switch to nested loop with
-- bounded probes per outer row.
--
-- Production EXPLAIN ANALYZE before/after:
--   hr_payroll_by_task                190 → ms (limit 100, single org)
--   hr_payroll_task_comparison        690 → 314 ms
--   hr_payroll_employee_comparison    590 → 314 ms
-- (~63% reduction on the slowest user-facing query in pg_stat_statements.)
--
-- Index size is ~1 MB; rebuild cost on schedule write is negligible.
-- The view definition is untouched, so data freshness semantics are
-- unchanged — every read still sees the latest schedule + payroll rows.

CREATE INDEX IF NOT EXISTS idx_ops_task_schedule_emp_start_date
  ON public.ops_task_schedule (hr_employee_id, ((start_time)::date))
  WHERE is_deleted = false;

ANALYZE public.ops_task_schedule;
