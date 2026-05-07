-- Performance: drop unused indexes + add covering index for payroll views
-- =========================================================================
-- Two unrelated wins bundled because both reduce DB latency:
--
-- 1. Drop six non-unique indexes that have not served a single read
--    since the last stats reset (idx_scan = 0 in pg_stat_user_indexes).
--    Unique constraints and primary keys are intentionally NOT dropped
--    even when unused for reads — they enforce data integrity. Dropped
--    indexes are easy to re-add if a future query plan benefits.
--
--    Source: live audit on 2026-05-07 against the production hosted DB:
--      SELECT indexrelname, pg_relation_size(indexrelid)
--      FROM pg_stat_user_indexes
--      WHERE schemaname='public' AND idx_scan=0 AND ...
--
--    Each of the six was non-unique, idle, and on a column for which
--    the table has another index covering primary access patterns.
--
-- 2. Add a covering index on hr_payroll(payroll_processor, check_date)
--    that is the actual filter used by both CTEs inside hr_payroll_by_task
--    and the periods CTE inside hr_payroll_employee_comparison. Existing
--    hr_payroll indexes all start with org_id, but the view bodies
--    don't filter on org_id (RLS does that later), so the planner falls
--    back to a sequential scan on a 11.6k-row table for every paginated
--    fetch. With this partial index the CTE plan switches to an index
--    scan, and the view's mean exec time (currently ~860ms in
--    pg_stat_statements) should drop substantially.
--
-- Both operations are reversible; no data is mutated.

-- 1. Drop indexes idle since last pg_stat reset.
DROP INDEX IF EXISTS public.idx_grow_monitoring_result_point;
DROP INDEX IF EXISTS public.idx_sales_invoice_number;
DROP INDEX IF EXISTS public.idx_sales_invoice_customer;
DROP INDEX IF EXISTS public.idx_edi_qb_invoice_line_service;
DROP INDEX IF EXISTS public.idx_fin_expense_txn_date;
DROP INDEX IF EXISTS public.idx_fin_expense_org;

-- 2. Covering index for the hot payroll view CTEs.
CREATE INDEX IF NOT EXISTS idx_hr_payroll_processor_check_date
  ON public.hr_payroll (payroll_processor, check_date)
  WHERE is_deleted = false;

-- 3. Refresh stats so the planner sees the new index immediately.
ANALYZE public.hr_payroll;
