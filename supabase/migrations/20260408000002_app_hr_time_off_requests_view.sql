CREATE OR REPLACE VIEW app_hr_time_off_requests AS
SELECT
    r.id,
    r.org_id,
    r.hr_employee_id,
    r.start_date,
    r.return_date,
    r.pto_days,
    r.non_pto_days,
    r.sick_leave_days,
    r.request_reason,
    r.denial_reason,
    r.notes,
    r.status,
    r.requested_at,
    r.requested_by,
    r.reviewed_at,
    r.reviewed_by,
    r.is_deleted,
    r.created_at,
    r.updated_at,

    -- Employee profile fields
    e.first_name || ' ' || e.last_name AS full_name,
    e.preferred_name,
    e.profile_photo_url,

    -- Department
    d.name AS department_name,

    -- Work authorization
    wa.name AS work_authorization_name,

    -- Compensation manager
    cm.first_name || ' ' || cm.last_name AS compensation_manager_name,

    -- Requested by name
    req.first_name || ' ' || req.last_name AS requested_by_name,

    -- Reviewed by name
    rev.first_name || ' ' || rev.last_name AS reviewed_by_name,

    -- Compatibility column for loadTableData
    NULL::DATE AS end_date

FROM hr_time_off_request r
JOIN hr_employee e ON e.id = r.hr_employee_id
LEFT JOIN hr_department d ON d.id = e.hr_department_id
LEFT JOIN hr_work_authorization wa ON wa.id = e.hr_work_authorization_id
LEFT JOIN hr_employee cm ON cm.id = e.compensation_manager_id
JOIN hr_employee req ON req.id = r.requested_by
LEFT JOIN hr_employee rev ON rev.id = r.reviewed_by;

GRANT SELECT ON app_hr_time_off_requests TO authenticated;
