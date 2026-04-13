CREATE TABLE IF NOT EXISTS hr_time_off_request (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    hr_employee_id  TEXT NOT NULL,

    start_date      DATE NOT NULL,
    return_date     DATE,
    non_pto_days      NUMERIC,
    pto_days        NUMERIC,
    sick_leave_days NUMERIC,
    request_reason  TEXT,
    denial_reason   TEXT,
    notes           TEXT,
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied')),

    requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    requested_by    TEXT NOT NULL,
    reviewed_at     TIMESTAMPTZ,
    reviewed_by     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_hr_time_off_request_employee
      FOREIGN KEY (hr_employee_id) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_time_off_request_requested_by
      FOREIGN KEY (requested_by) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_time_off_request_reviewed_by
      FOREIGN KEY (reviewed_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE hr_time_off_request IS 'Employee time off requests with PTO and sick leave breakdown and a simple approval workflow.';

CREATE INDEX idx_hr_time_off_request_org_id ON hr_time_off_request (org_id);
CREATE INDEX idx_hr_time_off_request_employee ON hr_time_off_request (hr_employee_id);
CREATE INDEX idx_hr_time_off_request_status ON hr_time_off_request (org_id, status);
CREATE INDEX idx_hr_time_off_request_dates ON hr_time_off_request (hr_employee_id, start_date);

COMMENT ON COLUMN hr_time_off_request.non_pto_days IS 'Days not charged to PTO or sick leave (e.g. unpaid leave, personal days)';
COMMENT ON COLUMN hr_time_off_request.status IS 'pending, approved, denied';
COMMENT ON COLUMN hr_time_off_request.requested_by IS 'Auto-set to the logged-in employee when the request is created';

-- RLS policies
ALTER TABLE hr_time_off_request ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_time_off_request_read" ON public.hr_time_off_request
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.hr_employee e
    WHERE e.org_id = hr_time_off_request.org_id
      AND e.user_id = auth.uid()
      AND e.is_deleted = false
  ));

CREATE POLICY "hr_time_off_request_write" ON public.hr_time_off_request
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.hr_employee e
    WHERE e.org_id = hr_time_off_request.org_id
      AND e.user_id = auth.uid()
      AND e.is_deleted = false
  ));

CREATE POLICY "hr_time_off_request_update" ON public.hr_time_off_request
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.hr_employee e
    WHERE e.org_id = hr_time_off_request.org_id
      AND e.user_id = auth.uid()
      AND e.is_deleted = false
  ));

GRANT SELECT, INSERT, UPDATE ON public.hr_time_off_request TO authenticated;

-- App view
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
