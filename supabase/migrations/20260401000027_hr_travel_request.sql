CREATE TABLE IF NOT EXISTS hr_travel_request (
    org_id              TEXT NOT NULL REFERENCES org(id),
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hr_employee_id         TEXT NOT NULL,

    -- Travel details
    request_type        TEXT,
    travel_purpose      TEXT,
    travel_from         TEXT,
    travel_to           TEXT,
    travel_start_date   DATE,
    travel_return_date  DATE,

    denial_reason       TEXT,
    notes               TEXT,
    status              TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied')),

    requested_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    requested_by        TEXT NOT NULL,
    reviewed_at         TIMESTAMPTZ,
    reviewed_by         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_hr_travel_request_employee
      FOREIGN KEY (hr_employee_id) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_travel_request_requested_by
      FOREIGN KEY (requested_by) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_travel_request_reviewed_by
      FOREIGN KEY (reviewed_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE hr_travel_request IS 'Employee travel requests with a simple approval workflow. Captures trip details, purpose, and dates alongside a pending, approved, or denied status flow.';

CREATE INDEX idx_hr_travel_request_org_id ON hr_travel_request (org_id);
CREATE INDEX idx_hr_travel_request_employee ON hr_travel_request (hr_employee_id);
CREATE INDEX idx_hr_travel_request_status ON hr_travel_request (org_id, status);
CREATE INDEX idx_hr_travel_request_dates ON hr_travel_request (hr_employee_id, travel_start_date);

COMMENT ON COLUMN hr_travel_request.status IS 'pending, approved, denied';
