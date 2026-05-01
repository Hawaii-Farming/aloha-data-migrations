CREATE TABLE IF NOT EXISTS fsafe_test_hold_po (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT NOT NULL,
    fsafe_test_hold_id  UUID NOT NULL REFERENCES fsafe_test_hold(id),
    sales_po_id         UUID NOT NULL REFERENCES sales_po(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_fsafe_test_hold_po UNIQUE (fsafe_test_hold_id, sales_po_id),
    CONSTRAINT fsafe_test_hold_po_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE fsafe_test_hold_po IS 'Links a test-and-hold record to one or more sales purchase orders.';

CREATE INDEX idx_fsafe_test_hold_po_org       ON fsafe_test_hold_po (org_id);
CREATE INDEX idx_fsafe_test_hold_po_test_hold ON fsafe_test_hold_po (fsafe_test_hold_id);
CREATE INDEX idx_fsafe_test_hold_po_sales_po  ON fsafe_test_hold_po (sales_po_id);

