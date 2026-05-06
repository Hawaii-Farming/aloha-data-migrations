-- edi_qb_invoice + edi_qb_invoice_line
-- ====================================
-- Local mirror of QuickBooks Online Invoice data so we can browse, query,
-- and join it without hitting Intuit's API on every request. Pull-only --
-- the sync job (gsheets/migrations/20260401000038_edi_qb_invoice.py)
-- overwrites these tables with the latest from QB on every run.
--
-- Two normalized tables (header + line) plus a flat view that joins them
-- back together for spreadsheet-style review (matches the legacy G-Accon
-- export shape).
--
-- The `edi_qb_` prefix groups this with the rest of the EDI integration
-- surface (SPS Commerce 850 / 856 / 810). QuickBooks isn't EDI in the
-- strict trading-partner sense, but it lives on the same "data exchange
-- with an external system" axis, so it's treated as the QB sub-module of
-- EDI for module-organization purposes.
--
-- Schema choices, in plain English:
--   * No surrogate UUID `id` -- the QB Invoice Id is unique within the
--     QB company and (org_id, id) is enough to identify a row.
--   * No created_at / created_by / updated_at / updated_by / is_deleted.
--     We aren't the source of truth; rows are wiped + reinserted every
--     sync. `synced_at` is enough provenance.
--   * Dropped the `qb_` prefix on most columns since the table name
--     already says "qb".
--   * No raw_payload archive -- if we need a field we don't currently
--     mirror, the sync script can re-pull from QB. Keeps row size small
--     and the schema readable.
--
-- Field selection mirrors what the team was extracting via G-Accon:
--   header: Invoice Number, Customer Name, Invoice Date (TxnDate)
--   lines : Item Name, Qty, Amount, Service Date, Description
--
-- RLS: org-scoped read for authenticated users. Writes are service-role
-- only -- the sync script bypasses RLS via the admin-key client.

-- ============================================================
-- edi_qb_invoice (header)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.edi_qb_invoice (
    org_id          TEXT NOT NULL REFERENCES public.org(id),
    id              TEXT NOT NULL,                   -- Intuit Invoice.Id
    invoice_number  TEXT,                            -- DocNumber (the human "20177" shown in QB UI)
    customer_id     TEXT,                            -- CustomerRef.value
    customer_name   TEXT,                            -- CustomerRef.name (denormalized for fast filtering)
    invoice_date    DATE,                            -- TxnDate
    total_amount    NUMERIC(14, 2),                  -- TotalAmt -- full cents (named total_amount to disambiguate from line.amount)
    sync_token      TEXT,                            -- Intuit's optimistic-concurrency version. Required when sending updates back to QB; QB rejects PUT without a current SyncToken.
    synced_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (org_id, id)
);

COMMENT ON TABLE  public.edi_qb_invoice IS 'Local mirror of QuickBooks Online Invoice headers. (org_id, id) is the source-of-truth PK; id holds the Intuit Invoice.Id directly (no surrogate UUID).';
COMMENT ON COLUMN public.edi_qb_invoice.id              IS 'Intuit Invoice.Id (string). Unique within a QB company; primary key with org_id.';
COMMENT ON COLUMN public.edi_qb_invoice.invoice_number  IS 'Human invoice number shown in QB UI (Invoice.DocNumber). Not unique on its own; can be missing on auto-numbered drafts.';
COMMENT ON COLUMN public.edi_qb_invoice.customer_name   IS 'CustomerRef.name copied here for fast filtering; canonical name lives on the QB Customer entity.';
COMMENT ON COLUMN public.edi_qb_invoice.sync_token      IS 'Intuit SyncToken -- optimistic-concurrency version. When pushing updates back to QB the request must include the current SyncToken; QB returns 400 "Stale Object Error" otherwise. Increments on every successful update; refreshed on every pull.';
COMMENT ON COLUMN public.edi_qb_invoice.synced_at       IS 'Wall-clock time of the last successful upsert from the QB API.';

CREATE INDEX idx_edi_qb_invoice_org_invoice_date ON public.edi_qb_invoice (org_id, invoice_date DESC);
CREATE INDEX idx_edi_qb_invoice_org_customer     ON public.edi_qb_invoice (org_id, customer_id);
CREATE INDEX idx_edi_qb_invoice_invoice_number   ON public.edi_qb_invoice (org_id, invoice_number);

-- ============================================================
-- edi_qb_invoice_line (line items)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.edi_qb_invoice_line (
    org_id          TEXT NOT NULL REFERENCES public.org(id),
    invoice_id      TEXT NOT NULL,                   -- parent Intuit Invoice.Id
    line_num        INTEGER NOT NULL,                -- Line[].LineNum (1-based ordering within the invoice)
    item_name       TEXT,                            -- SalesItemLineDetail.ItemRef.name (matches sales_product.id for the join in edi_qb_invoice_detail)
    description     TEXT,                            -- Line[].Description
    cases           NUMERIC(14, 4),                  -- SalesItemLineDetail.Qty (in cases for produce; fractional for partial pallets)
    amount          NUMERIC(14, 2),                  -- Line[].Amount -- full cents
    service_date    DATE,                            -- SalesItemLineDetail.ServiceDate -- when service was actually delivered

    PRIMARY KEY (org_id, invoice_id, line_num),
    FOREIGN KEY (org_id, invoice_id)
      REFERENCES public.edi_qb_invoice (org_id, id)
      ON DELETE CASCADE
);

COMMENT ON TABLE  public.edi_qb_invoice_line IS 'Local mirror of QuickBooks Online Invoice line items. One row per (org_id, invoice_id, line_num). Sales-item lines only -- subtotal / tax / discount lines are filtered out at sync time.';
COMMENT ON COLUMN public.edi_qb_invoice_line.line_num     IS 'Line.LineNum from Intuit (1-based). Preserve to maintain print order.';
COMMENT ON COLUMN public.edi_qb_invoice_line.service_date IS 'When the goods/service on this line were delivered (Line[].SalesItemLineDetail.ServiceDate). Distinct from the invoice_date on the header.';

CREATE INDEX idx_edi_qb_invoice_line_item    ON public.edi_qb_invoice_line (org_id, item_name);
CREATE INDEX idx_edi_qb_invoice_line_service ON public.edi_qb_invoice_line (org_id, service_date DESC);

-- ============================================================
-- edi_qb_invoice_summary (header + lines joined to operational tables)
-- ============================================================
-- Pre-flattened reporting shape for the QB invoice grid. One row per
-- invoice line, with a small set of business-facing columns drawn from:
--   * edi_qb_invoice          -- customer_name, invoice_number, invoice_date
--   * edi_qb_invoice_line     -- line_num, service_date, item_name, cases, amount
--   * sales_customer          -- customer_group  (joined by customer_name)
--   * sales_product           -- farm + case_net_weight  (joined by item_name)
-- pounds is computed: cases * sales_product.case_net_weight.
--
-- Joins are LEFT so unmatched customers / items still appear (with NULLs
-- for the joined fields) -- the underlying QB data is the source of truth
-- and shouldn't disappear from the grid because of a missing master-data
-- row. Org isolation enforced via security_invoker on this view + RLS on
-- the base tables.
CREATE OR REPLACE VIEW public.edi_qb_invoice_summary
WITH (security_invoker = true) AS
SELECT
    h.org_id,
    h.customer_name,
    sc.sales_customer_group_id                   AS customer_group,
    h.invoice_number,
    h.invoice_date,
    l.line_num,
    l.service_date,
    l.item_name,
    sp.farm_id                                   AS farm,
    l.cases,
    l.amount,
    (l.cases * sp.case_net_weight)               AS pounds
FROM public.edi_qb_invoice h
LEFT JOIN public.edi_qb_invoice_line l
  ON l.org_id = h.org_id
 AND l.invoice_id = h.id
LEFT JOIN public.sales_customer sc
  ON sc.org_id = h.org_id
 AND sc.id     = h.customer_name
LEFT JOIN public.sales_product sp
  ON sp.org_id = h.org_id
 AND sp.id     = l.item_name;

COMMENT ON VIEW public.edi_qb_invoice_summary IS 'One row per (invoice line) for spreadsheet-style review. Joins QB invoice header + line to sales_customer (for customer_group) and sales_product (for farm + case_net_weight); pounds = cases * case_net_weight. LEFT joins so unmatched master-data rows still appear with NULLs.';

GRANT SELECT ON public.edi_qb_invoice_summary TO authenticated;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.edi_qb_invoice      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.edi_qb_invoice_line ENABLE ROW LEVEL SECURITY;

CREATE POLICY "edi_qb_invoice_read" ON public.edi_qb_invoice
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "edi_qb_invoice_line_read" ON public.edi_qb_invoice_line
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

-- No INSERT / UPDATE / DELETE policies -- the sync script writes via the
-- service-role client, which bypasses RLS.

GRANT SELECT ON public.edi_qb_invoice      TO authenticated;
GRANT SELECT ON public.edi_qb_invoice_line TO authenticated;
