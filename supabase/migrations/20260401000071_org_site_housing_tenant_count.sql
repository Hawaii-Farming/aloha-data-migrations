-- org_site_housing_tenant_count
-- =============================
-- Wraps org_site_housing with a derived `tenant_count` column counting
-- active hr_employee assignments and an `available_beds` column when
-- maximum_beds is set.
--
-- "Active" means hr_employee.is_deleted = false AND
-- (end_date IS NULL OR end_date > current_date) — i.e. employees who
-- are still on payroll today, ignoring rows scheduled to leave in the
-- past or already terminated.
--
-- Housing sites with zero tenants still appear (LEFT JOIN), with
-- tenant_count = 0 and available_beds = maximum_beds.

CREATE OR REPLACE VIEW org_site_housing_tenant_count
WITH (security_invoker = true) AS
SELECT
    h.id,
    h.org_id,
    h.maximum_beds,
    h.address,
    h.notes,
    h.created_at,
    h.created_by,
    h.updated_at,
    h.updated_by,
    h.is_deleted,
    COALESCE(t.tenant_count, 0)                       AS tenant_count,
    CASE
      WHEN h.maximum_beds IS NULL THEN NULL
      ELSE GREATEST(h.maximum_beds - COALESCE(t.tenant_count, 0), 0)
    END                                               AS available_beds
FROM org_site_housing h
LEFT JOIN (
    SELECT housing_id, COUNT(*)::int AS tenant_count
    FROM hr_employee
    WHERE housing_id IS NOT NULL
      AND is_deleted = false
      AND (end_date IS NULL OR end_date > current_date)
    GROUP BY housing_id
) t ON t.housing_id = h.id
WHERE h.is_deleted = false;

GRANT SELECT ON org_site_housing_tenant_count TO authenticated;

COMMENT ON VIEW org_site_housing_tenant_count IS 'org_site_housing rows extended with tenant_count (active hr_employee assignments — not deleted, end_date null or in the future) and available_beds (maximum_beds minus tenant_count, clamped to >= 0; null when maximum_beds is unset).';
