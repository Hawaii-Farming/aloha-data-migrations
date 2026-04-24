CREATE TABLE IF NOT EXISTS sales_po (
    org_id                          TEXT NOT NULL REFERENCES org(id),
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_customer_group_id         TEXT REFERENCES sales_customer_group(id),
    sales_customer_id               TEXT NOT NULL REFERENCES sales_customer(id),
    sales_fob_id                    TEXT REFERENCES sales_fob(id),

    po_number           TEXT,
    order_date                      DATE NOT NULL,
    invoice_date                    DATE,
    recurring_frequency             TEXT CHECK (recurring_frequency IN ('weekly', 'biweekly', 'monthly')),
    notes                           TEXT,

    status                          TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'fulfilled', 'unfulfilled', 'past_due')),

    approved_at                     TIMESTAMPTZ,
    approved_by                     TEXT,
    qb_uploaded_at                  TIMESTAMPTZ,
    qb_uploaded_by                  TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                       BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_sales_po_approved_by
      FOREIGN KEY (approved_by) REFERENCES hr_employee(id),
    CONSTRAINT fk_sales_po_qb_uploaded_by
      FOREIGN KEY (qb_uploaded_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE sales_po IS 'Customer order header. One row per order. Tracks customer, FOB, dates, approval workflow, and optional recurring frequency for standing orders.';

CREATE INDEX idx_sales_po_org_id   ON sales_po (org_id);
CREATE INDEX idx_sales_po_customer ON sales_po (sales_customer_id);
CREATE INDEX idx_sales_po_status   ON sales_po (org_id, status);

COMMENT ON COLUMN sales_po.recurring_frequency IS 'weekly, biweekly, monthly; null means not recurring; auto-creates a new order after status is marked fulfilled';
COMMENT ON COLUMN sales_po.status IS 'draft → approved → fulfilled/unfulfilled; auto-set to past_due when order_date passes without fulfillment; unfulfilled means product was unavailable';
COMMENT ON COLUMN sales_po.sales_customer_group_id IS 'Auto-set from sales_customer.sales_customer_group_id; read-only';
COMMENT ON COLUMN sales_po.sales_fob_id IS 'Auto-set from sales_customer.sales_fob_id; read-only';
