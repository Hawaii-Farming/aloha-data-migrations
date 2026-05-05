-- qb_invoice + qb_invoice_line
-- ============================
-- Local mirror of QuickBooks Online Invoice data so we can browse, query,
-- and join it without hitting Intuit's API on every request. Pull-only for
-- now -- the sync job overwrites these tables with the latest from QB.
--
-- Two normalized tables (header + line) plus a flat view that joins them
-- back together for spreadsheet-style review (matches the legacy G-Accon
-- export shape).
--
-- Field selection mirrors what the team was extracting via G-Accon:
--   header: Invoice Number, Customer Name, Txn Date
--   lines : Item Name, Qty, Amount, Service Date, Description
--
-- Amounts kept as full-precision numeric (Intuit's authoritative cents).
-- raw_payload stores the full Intuit JSON so we can backfill new columns
-- later without re-pulling from QB.
--
-- RLS: org-scoped read for authenticated users (consistent with other
-- operational tables). Writes are service-role only -- the sync route
-- bypasses RLS via the admin client.

-- ============================================================
-- qb_invoice (header)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.qb_invoice (
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    org_id              TEXT NOT NULL REFERENCES public.org(id),
    qb_id               TEXT NOT NULL,                 -- Intuit's Invoice.Id, unique within a QB company
    qb_doc_number       TEXT,                          -- the human "Invoice Number" shown in QB UI
    qb_customer_id      TEXT,                          -- CustomerRef.value
    qb_customer_name    TEXT,                          -- CustomerRef.name (denormalized for fast filtering)
    txn_date            DATE,                          -- TxnDate
    total_amt           NUMERIC(14, 2),                -- TotalAmt -- full cents
    raw_payload         JSONB NOT NULL,                -- full Invoice JSON from Intuit
    qb_synced_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    PRIMARY KEY (org_id, qb_id),
    UNIQUE (id)                                         -- surface a stable surrogate for FK use from qb_invoice_line
);

COMMENT ON TABLE  public.qb_invoice IS 'Local mirror of QuickBooks Online Invoice headers. (org_id, qb_id) is the source-of-truth PK; id is a surrogate UUID exposed via UNIQUE so qb_invoice_line.qb_invoice_id can FK to it without dragging org_id+qb_id around.';
COMMENT ON COLUMN public.qb_invoice.qb_id            IS 'Intuit Invoice.Id (string). Unique within a QB company; primary key with org_id.';
COMMENT ON COLUMN public.qb_invoice.qb_doc_number    IS 'Human invoice number shown in QB UI (Invoice.DocNumber).';
COMMENT ON COLUMN public.qb_invoice.qb_customer_name IS 'CustomerRef.name copied here for fast filtering; canonical name lives on the QB Customer entity.';
COMMENT ON COLUMN public.qb_invoice.raw_payload      IS 'Full Intuit Invoice JSON. New columns can be backfilled from this without a re-pull.';

CREATE INDEX idx_qb_invoice_org_txn_date  ON public.qb_invoice (org_id, txn_date DESC);
CREATE INDEX idx_qb_invoice_org_customer  ON public.qb_invoice (org_id, qb_customer_id);
CREATE INDEX idx_qb_invoice_doc_number    ON public.qb_invoice (org_id, qb_doc_number);

-- ============================================================
-- qb_invoice_line (line items)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.qb_invoice_line (
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    org_id              TEXT NOT NULL REFERENCES public.org(id),
    qb_invoice_id       UUID NOT NULL REFERENCES public.qb_invoice(id) ON DELETE CASCADE,
    line_num            INTEGER,                       -- Line[].LineNum (1-based ordering within the invoice)
    qb_item_id          TEXT,                          -- SalesItemLineDetail.ItemRef.value
    qb_item_name        TEXT,                          -- SalesItemLineDetail.ItemRef.name
    description         TEXT,                          -- Line[].Description
    qty                 NUMERIC(14, 4),                -- SalesItemLineDetail.Qty (some lines fractional)
    amount              NUMERIC(14, 2),                -- Line[].Amount -- full cents
    service_date        DATE,                          -- SalesItemLineDetail.ServiceDate -- when service was actually delivered
    raw_payload         JSONB NOT NULL,                -- full line JSON from Intuit

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted          BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE  public.qb_invoice_line IS 'Local mirror of QuickBooks Online Invoice line items. One row per line on each invoice.';
COMMENT ON COLUMN public.qb_invoice_line.line_num     IS 'Line.LineNum from Intuit (1-based). Preserve to maintain print order.';
COMMENT ON COLUMN public.qb_invoice_line.service_date IS 'When the goods/service on this line were delivered (Line[].SalesItemLineDetail.ServiceDate). Distinct from the invoice TxnDate.';

CREATE INDEX idx_qb_invoice_line_invoice ON public.qb_invoice_line (qb_invoice_id);
CREATE INDEX idx_qb_invoice_line_item    ON public.qb_invoice_line (org_id, qb_item_id);
CREATE INDEX idx_qb_invoice_line_service ON public.qb_invoice_line (org_id, service_date DESC);

-- ============================================================
-- qb_invoice_flat (header + lines joined for spreadsheet-style browsing)
-- ============================================================
CREATE OR REPLACE VIEW public.qb_invoice_flat
WITH (security_invoker = true) AS
SELECT
    h.org_id,
    h.qb_id              AS qb_invoice_id,
    h.qb_doc_number      AS invoice_number,
    h.qb_customer_id,
    h.qb_customer_name   AS customer_name,
    h.txn_date,
    h.total_amt          AS invoice_total,
    l.line_num,
    l.qb_item_id,
    l.qb_item_name       AS item_name,
    l.description,
    l.qty,
    l.amount             AS line_amount,
    l.service_date,
    h.qb_synced_at
FROM public.qb_invoice h
LEFT JOIN public.qb_invoice_line l ON l.qb_invoice_id = h.id
WHERE h.is_deleted = false
  AND (l.is_deleted IS NULL OR l.is_deleted = false);

COMMENT ON VIEW public.qb_invoice_flat IS 'One row per (invoice line) for spreadsheet-style review. Header fields (invoice number, customer, txn date, total) repeat across an invoice''s line rows. Excludes soft-deleted rows. Mirrors the legacy G-Accon export shape.';

GRANT SELECT ON public.qb_invoice_flat TO authenticated;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.qb_invoice      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qb_invoice_line ENABLE ROW LEVEL SECURITY;

CREATE POLICY "qb_invoice_read" ON public.qb_invoice
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "qb_invoice_line_read" ON public.qb_invoice_line
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

-- No INSERT/UPDATE/DELETE policies -- the sync route writes via the
-- service-role client, which bypasses RLS.

GRANT SELECT ON public.qb_invoice      TO authenticated;
GRANT SELECT ON public.qb_invoice_line TO authenticated;
