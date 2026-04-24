CREATE TABLE IF NOT EXISTS fsafe_result (
    org_id          TEXT NOT NULL REFERENCES org(id),
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name         TEXT NOT NULL REFERENCES org_farm(name),
    site_id         TEXT REFERENCES org_site(id),
    fsafe_test_hold_id  UUID REFERENCES fsafe_test_hold(id),
    fsafe_lab_name    TEXT REFERENCES fsafe_lab(name),
    fsafe_lab_test_id   TEXT NOT NULL REFERENCES fsafe_lab_test(id),
    test_method             TEXT,
    initial_retest_vector   TEXT CHECK (initial_retest_vector IN ('initial', 'retest', 'vector')),
    status                  TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed')),

    result_enum     TEXT,
    result_numeric  NUMERIC,
    result_pass     BOOLEAN,
    fail_code       TEXT,

    fsafe_result_id_original UUID REFERENCES fsafe_result(id),

    notes           TEXT,

    sampled_at      TIMESTAMPTZ,
    sampled_by      TEXT,
    started_at TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    verified_at     TIMESTAMPTZ,
    verified_by     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_fsafe_result_sampled_by
      FOREIGN KEY (sampled_by) REFERENCES hr_employee(id),
    CONSTRAINT fk_fsafe_result_verified_by
      FOREIGN KEY (verified_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE fsafe_result IS 'Unified food safety test results table. Result type is derived from existing fields: EMP (site_id set, fsafe_test_hold_id null, zone != water), Test-and-Hold (fsafe_test_hold_id set), Water (site_id set, zone = water). Retests and vector tests link back to the original via fsafe_result_id_original.';

CREATE INDEX idx_fsafe_result_org       ON fsafe_result (org_id);
CREATE INDEX idx_fsafe_result_lab       ON fsafe_result (fsafe_lab_name);
CREATE INDEX idx_fsafe_result_site      ON fsafe_result (site_id);
CREATE INDEX idx_fsafe_result_test      ON fsafe_result (fsafe_lab_test_id);
CREATE INDEX idx_fsafe_result_test_hold ON fsafe_result (fsafe_test_hold_id);
CREATE INDEX idx_fsafe_result_original  ON fsafe_result (fsafe_result_id_original);
CREATE INDEX idx_fsafe_result_status    ON fsafe_result (org_id, status);

COMMENT ON COLUMN fsafe_result.initial_retest_vector IS 'initial, retest, vector';
COMMENT ON COLUMN fsafe_result.status IS 'pending, in_progress, completed';
COMMENT ON COLUMN fsafe_result.site_id IS 'Food safety site (org_site where category = food_safety or zone = water); set for EMP and water results, null for test-and-hold';
COMMENT ON COLUMN fsafe_result.fsafe_lab_name IS 'Pre-filled from fsafe_test_hold.fsafe_lab_name for test-and-hold results; editable';
COMMENT ON COLUMN fsafe_result.test_method IS 'Pre-filled from fsafe_lab_test.test_methods; editable';
COMMENT ON COLUMN fsafe_result.result_pass IS 'Auto-set by evaluating result against fsafe_lab_test pass/fail criteria';
COMMENT ON COLUMN fsafe_result.fsafe_result_id_original IS 'Sourced from the original fsafe_result when initial_retest_vector is retest or vector';

