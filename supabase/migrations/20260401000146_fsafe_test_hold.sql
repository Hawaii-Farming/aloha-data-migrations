CREATE TABLE IF NOT EXISTS fsafe_test_hold (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL,
    pack_lot_id     UUID NOT NULL REFERENCES pack_lot(id),
    sales_customer_group_id TEXT REFERENCES sales_customer_group(id),
    sales_customer_id       TEXT REFERENCES sales_customer(id),
    fsafe_lab_id    TEXT REFERENCES fsafe_lab(id),
    lab_test_id     TEXT,

    notes           TEXT,

    delivered_to_lab_on DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT fsafe_test_hold_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE fsafe_test_hold IS 'Test-and-hold header. One record per pack lot per lab. If the same lot is sent to a different lab, a separate entry is created. Tracks sample collection, lab submission, and test timeline.';

CREATE INDEX idx_fsafe_test_hold_org      ON fsafe_test_hold (org_id);
CREATE INDEX idx_fsafe_test_hold_farm     ON fsafe_test_hold (farm_id);
CREATE INDEX idx_fsafe_test_hold_lot      ON fsafe_test_hold (pack_lot_id);
CREATE INDEX idx_fsafe_test_hold_customer ON fsafe_test_hold (sales_customer_id);
COMMENT ON COLUMN fsafe_test_hold.sales_customer_id IS 'Pre-filled from the linked sales_po customer; editable';
COMMENT ON COLUMN fsafe_test_hold.sales_customer_group_id IS 'Pre-filled from sales_customer.sales_customer_group_id; editable';
