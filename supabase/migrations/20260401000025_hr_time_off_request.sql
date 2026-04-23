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

-- --------------------------------------------------------------------
-- RLS: any authenticated user in the same org can read + insert/update.
-- Granular CRUD (can_edit / can_delete / can_verify) is enforced in the
-- app layer via hr_module_access; there is no DELETE grant (soft delete
-- via is_deleted = true).
-- --------------------------------------------------------------------
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
