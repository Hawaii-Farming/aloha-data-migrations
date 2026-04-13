CREATE TABLE IF NOT EXISTS hr_employee_review (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    hr_employee_id      TEXT NOT NULL,
    review_year         INTEGER NOT NULL,
    review_quarter      INTEGER NOT NULL CHECK (review_quarter BETWEEN 1 AND 4),
    productivity        INTEGER NOT NULL CHECK (productivity BETWEEN 1 AND 3),
    attendance          INTEGER NOT NULL CHECK (attendance BETWEEN 1 AND 3),
    quality             INTEGER NOT NULL CHECK (quality BETWEEN 1 AND 3),
    engagement          INTEGER NOT NULL CHECK (engagement BETWEEN 1 AND 3),
    average             NUMERIC GENERATED ALWAYS AS (
                            (productivity + attendance + quality + engagement) / 4.0
                        ) STORED,
    notes               TEXT,
    lead_id             TEXT,
    is_locked           BOOLEAN NOT NULL DEFAULT false,
    created_by          TEXT REFERENCES hr_employee(id),
    updated_by          TEXT REFERENCES hr_employee(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_hr_employee_review_quarter
        UNIQUE (org_id, hr_employee_id, review_year, review_quarter),
    CONSTRAINT fk_hr_employee_review_employee
        FOREIGN KEY (hr_employee_id) REFERENCES hr_employee(id),
    CONSTRAINT fk_hr_employee_review_lead
        FOREIGN KEY (lead_id) REFERENCES hr_employee(id)
);

ALTER TABLE hr_employee_review ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_employee_review_read" ON hr_employee_review
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM hr_employee e
        WHERE e.org_id = hr_employee_review.org_id
          AND e.user_id = auth.uid()
          AND e.is_deleted = false
    ));

CREATE POLICY "hr_employee_review_insert" ON hr_employee_review
    FOR INSERT TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM hr_employee e
        WHERE e.org_id = hr_employee_review.org_id
          AND e.user_id = auth.uid()
          AND e.is_deleted = false
    ));

CREATE POLICY "hr_employee_review_update" ON hr_employee_review
    FOR UPDATE TO authenticated
    USING (EXISTS (
        SELECT 1 FROM hr_employee e
        WHERE e.org_id = hr_employee_review.org_id
          AND e.user_id = auth.uid()
          AND e.is_deleted = false
    ));

GRANT SELECT, INSERT, UPDATE ON hr_employee_review TO authenticated;

CREATE INDEX idx_hr_employee_review_org ON hr_employee_review (org_id);
CREATE INDEX idx_hr_employee_review_employee ON hr_employee_review (hr_employee_id);
CREATE INDEX idx_hr_employee_review_period ON hr_employee_review (org_id, review_year, review_quarter);
