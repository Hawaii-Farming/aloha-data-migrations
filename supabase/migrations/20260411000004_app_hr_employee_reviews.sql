CREATE OR REPLACE VIEW app_hr_employee_reviews AS
SELECT
    r.id,
    r.org_id,
    r.hr_employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    e.profile_photo_url,
    d.name AS department_name,
    wa.name AS work_authorization_name,
    e.start_date,
    r.review_year,
    r.review_quarter,
    r.review_year || '-Q' || r.review_quarter AS quarter_label,
    r.productivity,
    r.attendance,
    r.quality,
    r.engagement,
    r.average,
    r.notes,
    r.lead_id,
    lead.first_name || ' ' || lead.last_name AS lead_name,
    r.is_locked,
    r.created_at,
    r.updated_at,
    r.created_by,
    r.updated_by,
    r.is_deleted
FROM hr_employee_review r
INNER JOIN hr_employee e
    ON e.id = r.hr_employee_id
LEFT JOIN hr_department d
    ON d.id = e.hr_department_id
LEFT JOIN hr_work_authorization wa
    ON wa.id = e.hr_work_authorization_id
LEFT JOIN hr_employee lead
    ON lead.id = r.lead_id
WHERE r.is_deleted = false;

GRANT SELECT ON app_hr_employee_reviews TO authenticated;
