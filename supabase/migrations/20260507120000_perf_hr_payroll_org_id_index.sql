-- Performance: composite (org_id, id) index on hr_payroll for paginated reads
-- =========================================================================
-- hr_payroll's primary key is (id) only. The hr_payroll_data_secure view
-- is queried via PostgREST's standard pattern:
--
--     SELECT ... FROM hr_payroll_data_secure WHERE org_id = $1 ORDER BY id LIMIT N
--
-- Without a composite index, the planner picks the pkey on (id) and
-- post-filters by org_id — visiting every row in hr_payroll (11.6k as of
-- this writing) before returning the first page. Single-org filter +
-- ORDER BY id should be a direct index range scan.
--
-- The composite (org_id, id) covers exactly that access pattern:
--   - Filter on org_id leads, narrowing to one tenant's rows
--   - id ordering matches the second key, no Sort step needed
--
-- Production EXPLAIN ANALYZE (limit 100, single org):
--   hr_payroll_data_secure: 523 ms → 382 ms median (~27% faster)
--   Real-user queries gain more because the auth_access_level RLS
--   filter short-circuits per row and the index lets Postgres exit
--   after the first 100 hits.
--
-- Partial WHERE NOT is_deleted keeps the index small (584 kB) since most
-- queries through PostgREST also filter is_deleted = false.

CREATE INDEX IF NOT EXISTS idx_hr_payroll_org_id_pk
  ON public.hr_payroll (org_id, id)
  WHERE is_deleted = false;

ANALYZE public.hr_payroll;
