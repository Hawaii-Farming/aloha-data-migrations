-- edi_qb_expense + edi_qb_expense_line
-- =====================================
-- Local mirror of QuickBooks Online Purchase entities ("Expense" in the
-- QB UI). Pull-only -- the sync job
-- (gsheets/migrations/20260401000039_edi_qb_expense.py) overwrites these
-- tables with the latest from QB on every run.
--
-- Two normalized tables (header + line) plus a summary view that joins
-- them back together for spreadsheet-style review.
--
-- Same `edi_qb_` module prefix and slim-schema choices as edi_qb_invoice:
--   * No surrogate UUID id -- (org_id, id) is enough where id = Purchase.Id.
--   * No created_*/updated_*/is_deleted audit columns -- we aren't the
--     source of truth; rows get wiped + reinserted on every sync.
--     synced_at carries provenance.
--   * No raw_payload archive -- re-pull from QB if a new column is needed.
--
-- Field selection mirrors what the team was extracting via G-Accon:
--   header: Account Ref Name (bank/CC paid from), Credit, Payee Ref Name, Txn Date
--   lines : Account Name (categorization), Class Name, Description, Amount

-- ============================================================
-- edi_qb_expense (header)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.edi_qb_expense (
    org_id        TEXT NOT NULL REFERENCES public.org(id),
    id            TEXT NOT NULL,                   -- Intuit Purchase.Id
    payee_name    TEXT,                            -- PayeeRef.name (vendor / payee)
    account_name  TEXT,                            -- AccountRef.name (the bank / credit-card account paid from)
    is_credit     BOOLEAN NOT NULL DEFAULT false,  -- Purchase.Credit -- true means refund / credit memo
    transaction_date      DATE,                            -- TxnDate
    sync_token    TEXT,                            -- Intuit's optimistic-concurrency version. Required when sending updates back to QB; QB rejects PUT without a current SyncToken.
    synced_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (org_id, id)
);

COMMENT ON TABLE  public.edi_qb_expense IS 'Local mirror of QuickBooks Online Purchase headers (expenses paid by cash / check / credit card). (org_id, id) is the source-of-truth PK; id holds the Intuit Purchase.Id directly.';
COMMENT ON COLUMN public.edi_qb_expense.id           IS 'Intuit Purchase.Id (string). Unique within a QB company; primary key with org_id.';
COMMENT ON COLUMN public.edi_qb_expense.account_name IS 'Bank / credit-card account the purchase was paid FROM (Purchase.AccountRef.name). Distinct from edi_qb_expense_line.account_name which is the line-level categorization account.';
COMMENT ON COLUMN public.edi_qb_expense.is_credit    IS 'Purchase.Credit. True = refund / vendor credit reducing AP balance. False = normal outflow.';
COMMENT ON COLUMN public.edi_qb_expense.sync_token   IS 'Intuit SyncToken -- optimistic-concurrency version. When pushing updates back to QB the request must include the current SyncToken; QB returns 400 "Stale Object Error" otherwise. Increments on every successful update; refreshed on every pull.';
COMMENT ON COLUMN public.edi_qb_expense.synced_at    IS 'Wall-clock time of the last successful upsert from the QB API.';

CREATE INDEX idx_edi_qb_expense_org_transaction_date  ON public.edi_qb_expense (org_id, transaction_date DESC);
CREATE INDEX idx_edi_qb_expense_org_payee     ON public.edi_qb_expense (org_id, payee_name);

-- ============================================================
-- edi_qb_expense_line (line items)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.edi_qb_expense_line (
    org_id        TEXT NOT NULL REFERENCES public.org(id),
    expense_id    TEXT NOT NULL,                   -- parent Intuit Purchase.Id
    line_num      INTEGER NOT NULL,                -- Line[].LineNum (1-based)
    account_name  TEXT,                            -- AccountBasedExpenseLineDetail.AccountRef.name (the categorization account)
    class_name    TEXT,                            -- AccountBasedExpenseLineDetail.ClassRef.name (QB Class -- often farm-level tagging)
    description   TEXT,                            -- Line[].Description
    amount        NUMERIC(14, 2),                  -- Line[].Amount -- full cents

    PRIMARY KEY (org_id, expense_id, line_num),
    FOREIGN KEY (org_id, expense_id)
      REFERENCES public.edi_qb_expense (org_id, id)
      ON DELETE CASCADE
);

COMMENT ON TABLE  public.edi_qb_expense_line IS 'Local mirror of QuickBooks Online Purchase line items. One row per (org_id, expense_id, line_num). Captures both AccountBasedExpenseLineDetail and ItemBasedExpenseLineDetail line types -- whichever provides the AccountRef gets surfaced as account_name.';
COMMENT ON COLUMN public.edi_qb_expense_line.line_num     IS 'Line.LineNum from Intuit (1-based). Preserve to maintain ordering.';
COMMENT ON COLUMN public.edi_qb_expense_line.account_name IS 'Line-level categorization account (e.g. ''Repairs & Maintenance''). Distinct from edi_qb_expense.account_name which is the funding account.';
COMMENT ON COLUMN public.edi_qb_expense_line.class_name   IS 'QB Class tag on the line. Typically used for farm-level (Cuke / Lettuce) cost allocation.';

CREATE INDEX idx_edi_qb_expense_line_account ON public.edi_qb_expense_line (org_id, account_name);
CREATE INDEX idx_edi_qb_expense_line_class   ON public.edi_qb_expense_line (org_id, class_name);

-- ============================================================
-- edi_qb_expense_summary (header + lines, flat for spreadsheet-style browsing)
-- ============================================================
CREATE OR REPLACE VIEW public.edi_qb_expense_summary
WITH (security_invoker = true) AS
SELECT
    h.org_id,
    h.payee_name,
    h.account_name      AS funding_account,
    h.is_credit,
    h.transaction_date,
    l.line_num,
    l.account_name      AS expense_account,
    l.class_name,
    l.description,
    l.amount
FROM public.edi_qb_expense h
LEFT JOIN public.edi_qb_expense_line l
  ON l.org_id = h.org_id
 AND l.expense_id = h.id;

COMMENT ON VIEW public.edi_qb_expense_summary IS 'One row per (expense line) for spreadsheet-style review. Header fields (payee_name, funding_account, transaction_date, is_credit) repeat across each expense''s line rows. funding_account = bank/CC paid from; expense_account = the categorization account on the line. Mirrors the legacy G-Accon export shape.';

GRANT SELECT ON public.edi_qb_expense_summary TO authenticated;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.edi_qb_expense      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.edi_qb_expense_line ENABLE ROW LEVEL SECURITY;

CREATE POLICY "edi_qb_expense_read" ON public.edi_qb_expense
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "edi_qb_expense_line_read" ON public.edi_qb_expense_line
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.edi_qb_expense      TO authenticated;
GRANT SELECT ON public.edi_qb_expense_line TO authenticated;
