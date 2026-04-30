CREATE TABLE IF NOT EXISTS fsafe_lab_test (
    id       TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT REFERENCES org_farm(id),

    test_methods    JSONB NOT NULL DEFAULT '[]',
    test_description TEXT,

    -- Result configuration
    result_type     TEXT NOT NULL CHECK (result_type IN ('Enum', 'Numeric')),
    enum_options         JSONB,
    enum_pass_options    JSONB,
    minimum_value NUMERIC,
    maximum_value NUMERIC,

    -- ATP configuration
    atp_site_count          INTEGER,

    -- Retest & vector test thresholds
    required_retests        INTEGER NOT NULL DEFAULT 0,
    required_vector_tests   INTEGER NOT NULL DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_fsafe_lab_test UNIQUE (org_id, id)
);

COMMENT ON TABLE fsafe_lab_test IS 'Catalog of EMP test definitions and their result configuration. Defines how results are evaluated and how many retests or vector tests are required on a fail.';

CREATE INDEX idx_fsafe_lab_test_org ON fsafe_lab_test (org_id);

COMMENT ON COLUMN fsafe_lab_test.test_methods IS 'JSON array of available testing methods; fsafe_result.test_method is selected from this list';
COMMENT ON COLUMN fsafe_lab_test.result_type IS 'enum, numeric';
COMMENT ON COLUMN fsafe_lab_test.enum_options IS 'JSON array of allowed result values when result_type is enum (e.g. ["Positive", "Negative"])';
COMMENT ON COLUMN fsafe_lab_test.enum_pass_options IS 'Subset of enum_options that indicate a passing result; used to auto-set fsafe_result.result_pass';
COMMENT ON COLUMN fsafe_lab_test.minimum_value IS 'Numeric result at or above this value passes; used to auto-set fsafe_result.result_pass when result_type is numeric';
COMMENT ON COLUMN fsafe_lab_test.maximum_value IS 'Numeric result at or below this value passes; used to auto-set fsafe_result.result_pass when result_type is numeric';
COMMENT ON COLUMN fsafe_lab_test.atp_site_count IS 'Number of zone_1 sites to randomly select for ATP testing; null means this test is not ATP';
COMMENT ON COLUMN fsafe_lab_test.required_retests IS 'Number of retest results to auto-create in fsafe_result when a result fails';
COMMENT ON COLUMN fsafe_lab_test.required_vector_tests IS 'Number of vector test results to auto-create in fsafe_result when a result fails';
