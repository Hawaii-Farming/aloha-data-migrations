-- org_site_housing_tenants
-- ========================
-- Lists active tenants per housing site. One row per (housing_id, employee).
-- Pairs with org_site_housing_tenant_count (slot 071) which gives the
-- aggregate counts; this view gives the per-tenant detail.
--
-- "Active" matches the same definition used by the count view:
--   hr_employee.is_deleted = false
--   AND (end_date IS NULL OR end_date > current_date)
--
-- security_invoker = true means the existing hr_employee SELECT policy
-- scopes rows to the caller's org. No separate RLS policy needed.

CREATE OR REPLACE VIEW org_site_housing_tenants
WITH (security_invoker = true) AS
SELECT
    e.housing_id,
    e.org_id,
    e.id                            AS hr_employee_id,
    e.first_name,
    e.last_name,
    e.preferred_name,
    e.gender,
    e.hr_department_id,
    e.start_date,
    e.end_date
FROM hr_employee e
WHERE e.housing_id IS NOT NULL
  AND e.is_deleted = false
  AND (e.end_date IS NULL OR e.end_date > current_date);

GRANT SELECT ON org_site_housing_tenants TO authenticated;

COMMENT ON VIEW org_site_housing_tenants IS 'Active tenants per housing site. One row per (housing_id, employee). Active = hr_employee.is_deleted=false AND (end_date IS NULL OR end_date > current_date). Pairs with org_site_housing_tenant_count for aggregate counts.';
