CREATE TABLE IF NOT EXISTS fsafe_test_hold_po (
    org_id              TEXT NOT NULL REFERENCES org(id),
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name             TEXT NOT NULL REFERENCES org_farm(name),
    fsafe_test_hold_id  UUID NOT NULL REFERENCES fsafe_test_hold(id),
    sales_po_id         UUID NOT NULL REFERENCES sales_po(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_fsafe_test_hold_po UNIQUE (fsafe_test_hold_id, sales_po_id)
);

COMMENT ON TABLE fsafe_test_hold_po IS 'Links a test-and-hold record to one or more sales purchase orders.';

CREATE INDEX idx_fsafe_test_hold_po_org       ON fsafe_test_hold_po (org_id);
CREATE INDEX idx_fsafe_test_hold_po_test_hold ON fsafe_test_hold_po (fsafe_test_hold_id);
CREATE INDEX idx_fsafe_test_hold_po_sales_po  ON fsafe_test_hold_po (sales_po_id);

