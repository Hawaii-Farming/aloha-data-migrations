CREATE OR REPLACE VIEW app_hr_housing AS
SELECT
    s.id,
    s.org_id,
    s.name,
    s.max_beds,
    COUNT(e.id) FILTER (WHERE e.is_deleted = false) AS tenant_count,
    s.max_beds - COUNT(e.id) FILTER (WHERE e.is_deleted = false) AS available_beds,
    s.notes,
    s.is_active
FROM org_site s
INNER JOIN org_site_category c
    ON c.id = s.org_site_category_id
    AND c.category_name = 'housing'
    AND c.sub_category_name IS NULL
LEFT JOIN hr_employee e
    ON e.site_id = s.id
WHERE s.is_deleted = false
GROUP BY s.id, s.org_id, s.name, s.max_beds, s.notes, s.is_active;

GRANT SELECT ON app_hr_housing TO authenticated;
