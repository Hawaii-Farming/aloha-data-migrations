CREATE TABLE IF NOT EXISTS fin_expense (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES org(id),
    farm_name             TEXT REFERENCES org_farm(name),
    txn_date            DATE NOT NULL,
    payee_name          TEXT,
    description         TEXT,
    account_name        TEXT,
    account_ref         TEXT,
    class_name          TEXT,
    amount              NUMERIC,
    is_credit           BOOLEAN NOT NULL DEFAULT false,
    effective_amount    NUMERIC,
    macro_category      TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE fin_expense IS 'Financial expense transactions sourced from QuickBooks (nightly-synced from the invoices/expense spreadsheet today, moving to direct QB API later). One row per line item on a QB expense transaction.';

COMMENT ON COLUMN fin_expense.farm_name IS 'Nullable — the expense spreadsheet does not currently carry a Farm column. Populated later when expenses are farm-tagged (likely derivable from class_name)';
COMMENT ON COLUMN fin_expense.txn_date IS 'Transaction date from QB (Txn Date column in the expense sheet)';
COMMENT ON COLUMN fin_expense.payee_name IS 'Free-text payee; Payee Ref.name from QB. Nullable since some expenses are line items without a distinct payee';
COMMENT ON COLUMN fin_expense.description IS 'Line-item description from QB (Line Item.description)';
COMMENT ON COLUMN fin_expense.account_name IS 'QB chart-of-accounts bucket (Line Item.account Name), e.g. "6. Office:Misc" or "3. R&M:Facilities"';
COMMENT ON COLUMN fin_expense.account_ref IS 'Originating account / card identifier (Account Ref.name), e.g. "JPM,0388" or "JPM CC:JPM5660/6836,LF"';
COMMENT ON COLUMN fin_expense.class_name IS 'QB class (Line Item.class Name), cost-center style tag. Often null';
COMMENT ON COLUMN fin_expense.amount IS 'Raw line-item amount from QB (Line Item.amount), always positive';
COMMENT ON COLUMN fin_expense.is_credit IS 'True when the QB transaction is a credit/refund; from the "Creadit" (sic) column in the sheet';
COMMENT ON COLUMN fin_expense.effective_amount IS 'Signed amount used by dashboards: equals amount when is_credit=false, equals -amount when is_credit=true. From the second "Amt" column in the sheet (pre-computed there)';
COMMENT ON COLUMN fin_expense.macro_category IS 'Top-level QB account category (Macro), e.g. "3. R&M", "6. Office", derived from account_name';

CREATE INDEX idx_fin_expense_org ON fin_expense (org_id);
CREATE INDEX idx_fin_expense_farm ON fin_expense (farm_name);
CREATE INDEX idx_fin_expense_txn_date ON fin_expense (txn_date);

-- View exposes derived date parts + applies soft-delete filter. Dashboards query this.
CREATE OR REPLACE VIEW fin_expense_v AS
SELECT
    e.*,
    EXTRACT(YEAR  FROM e.txn_date)::INT AS year,
    EXTRACT(MONTH FROM e.txn_date)::INT AS month
FROM fin_expense e
WHERE e.is_deleted = false;

COMMENT ON VIEW fin_expense_v IS 'fin_expense with derived year/month columns and soft-delete filter applied. Dashboards read from this view';
