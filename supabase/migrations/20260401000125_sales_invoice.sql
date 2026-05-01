CREATE TABLE IF NOT EXISTS sales_invoice (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_id             TEXT,
    invoice_number      TEXT NOT NULL,
    invoice_date        DATE NOT NULL,
    customer_name       TEXT NOT NULL,
    customer_group      TEXT,
    product_code        TEXT,
    variety             TEXT,
    grade               TEXT,
    cases               NUMERIC,
    pounds              NUMERIC,
    dollars             NUMERIC NOT NULL,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT sales_invoice_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE sales_invoice IS 'QuickBooks invoice line items (nightly-synced from the invoices spreadsheet today, moving to direct QB API later). One row per line item — a single invoice_number can appear across multiple rows with different product_code/variety/grade combinations. No uniqueness constraint until QB line-item numbers are included in the pull, at which point (org_id, invoice_number, line_number) will be unique.';

COMMENT ON COLUMN sales_invoice.farm_id IS 'Derived from the Farm column in the sheet (e.g. "Cuke" -> cuke, "Lettuce" -> lettuce)';
COMMENT ON COLUMN sales_invoice.invoice_number IS 'QB invoice number; not unique on its own because one invoice spans multiple line items';
COMMENT ON COLUMN sales_invoice.invoice_date IS 'Date the invoice was issued';
COMMENT ON COLUMN sales_invoice.customer_name IS 'Customer display name from QB';
COMMENT ON COLUMN sales_invoice.customer_group IS 'Broader grouping used by sales dashboards (e.g. Safeway Inc., Armstrong Produce, Small)';
COMMENT ON COLUMN sales_invoice.product_code IS 'Short product code as it appears on the invoice line (e.g. OK, OJ, LF, LR)';
COMMENT ON COLUMN sales_invoice.variety IS 'One-letter variety code pulled from the line (K, J, E, L, W, etc.). Free-text to allow future variations';
COMMENT ON COLUMN sales_invoice.grade IS 'Quality grade on the line (e.g. 1, 2)';
COMMENT ON COLUMN sales_invoice.cases IS 'Case count on the invoice line';
COMMENT ON COLUMN sales_invoice.pounds IS 'Weight in pounds on the invoice line';
COMMENT ON COLUMN sales_invoice.dollars IS 'Line total in dollars';

CREATE INDEX idx_sales_invoice_org ON sales_invoice (org_id);
CREATE INDEX idx_sales_invoice_farm ON sales_invoice (farm_id);
CREATE INDEX idx_sales_invoice_date ON sales_invoice (invoice_date);
CREATE INDEX idx_sales_invoice_number ON sales_invoice (invoice_number);
CREATE INDEX idx_sales_invoice_customer ON sales_invoice (customer_name);

-- View exposes derived date parts + applies soft-delete filter. Dashboards query this.
CREATE OR REPLACE VIEW sales_invoice_v
WITH (security_invoker = true) AS
SELECT
    i.*,
    EXTRACT(YEAR    FROM i.invoice_date)::INT AS year,
    EXTRACT(MONTH   FROM i.invoice_date)::INT AS month,
    EXTRACT(ISOYEAR FROM i.invoice_date)::INT AS iso_year,
    EXTRACT(WEEK    FROM i.invoice_date)::INT AS iso_week,
    EXTRACT(DOW     FROM i.invoice_date)::INT AS dow
FROM sales_invoice i
WHERE i.is_deleted = false;

COMMENT ON VIEW sales_invoice_v IS 'sales_invoice with derived year/month/iso_year/iso_week/dow columns and soft-delete filter applied. Dashboards read from this view';
