-- sales_po_asn_carton
-- ===================
-- Carton-level detail for an outbound 856 ASN. Each row is one physical
-- carton/case bearing a UCC-128 (SSCC-18) label. The label barcode is
-- what the buyer scans on receipt, so the SSCC must match exactly what
-- we ship and what we transmit on the 856 SN1/MAN segments.
--
-- Hierarchy of an 856:
--   ASN (header)              → sales_po_asn
--     PO (order)               → sales_po (referenced by FK on parent)
--       Pack/Tare (pallet)     → optional, modeled inline via parent_carton_id
--         Item (carton)        → sales_po_asn_carton  ← this table
--           Lot/serial detail  → linked to sales_po_fulfillment
--
-- We model pallets and cartons in one table via parent_carton_id (NULL
-- for cartons, set for cartons that belong to a parent pallet carton).
-- Most 856s are flat (case-only); pallet-level grouping is opt-in.
--
-- SPS-only table.

CREATE TABLE IF NOT EXISTS sales_po_asn_carton (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_po_asn_id             UUID NOT NULL REFERENCES sales_po_asn(id) ON DELETE CASCADE,
    sales_po_line_id            UUID NOT NULL REFERENCES sales_po_line(id),
    sales_po_fulfillment_id     UUID REFERENCES sales_po_fulfillment(id),

    -- Optional pallet-level grouping. NULL for cartons not nested under
    -- a tare; otherwise points at the pallet carton in this same table.
    parent_carton_id            UUID REFERENCES sales_po_asn_carton(id) ON DELETE CASCADE,

    -- Carton type — drives the 856 HL hierarchy level code.
    -- Tare = pallet, Pack = case, Item = each.
    carton_type                 TEXT NOT NULL DEFAULT 'Pack'
        CHECK (carton_type IN ('Tare', 'Pack', 'Item')),

    -- GS1 Serial Shipping Container Code (SSCC-18). Printed as the
    -- barcode on the UCC-128 label and transmitted on 856 MAN02.
    sscc                        TEXT NOT NULL,

    -- Quantity inside this carton. For Tare = number of nested cases;
    -- for Pack = number of consumer units; for Item = always 1.
    quantity                    NUMERIC NOT NULL,

    -- Catch-weight cartons (variable-weight produce) need actual net
    -- weight on the 856; non-catch-weight cartons use sales_product
    -- defaults so this stays NULL.
    actual_net_weight           NUMERIC,
    weight_uom                  TEXT REFERENCES sys_uom(id),

    -- Lot traceability (FSMA): which production lot is in this carton.
    -- Required for fsma_traceable products; otherwise optional.
    pack_lot_id                 UUID REFERENCES pack_lot(id),
    pack_date                   DATE,
    best_by_date                DATE,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_po_asn_carton_sscc UNIQUE (sscc)
);

COMMENT ON TABLE sales_po_asn_carton IS 'SPS-only. Carton-level detail for an outbound 856 ASN. One row per physical carton/pallet bearing a UCC-128 SSCC label. Self-referencing parent_carton_id models pallet→case nesting; flat (case-only) ASNs leave it NULL. SSCC is globally unique per GS1 spec — never reuse, even after a carton is consumed.';

CREATE INDEX idx_sales_po_asn_carton_org    ON sales_po_asn_carton (org_id);
CREATE INDEX idx_sales_po_asn_carton_asn    ON sales_po_asn_carton (sales_po_asn_id);
CREATE INDEX idx_sales_po_asn_carton_line   ON sales_po_asn_carton (sales_po_line_id);
CREATE INDEX idx_sales_po_asn_carton_parent ON sales_po_asn_carton (parent_carton_id);
CREATE INDEX idx_sales_po_asn_carton_lot    ON sales_po_asn_carton (pack_lot_id);

COMMENT ON COLUMN sales_po_asn_carton.parent_carton_id IS 'Self-FK for pallet→case nesting. NULL = top-level carton on the ASN. Points at a row whose carton_type is Tare. Cascade delete keeps a pallet and its cases consistent.';
COMMENT ON COLUMN sales_po_asn_carton.carton_type IS 'GS1 Hierarchy Level: Tare (pallet, HL*P*T), Pack (case, HL*P*P), Item (each, HL*P*I). Drives the 856 HL segment hierarchy code.';
COMMENT ON COLUMN sales_po_asn_carton.sscc IS 'GS1 Serial Shipping Container Code (SSCC-18). Printed as the UCC-128 barcode on the carton and transmitted on 856 MAN*GM. Globally unique — must never be reused, including across cancelled shipments.';
COMMENT ON COLUMN sales_po_asn_carton.actual_net_weight IS 'Required only for catch-weight (is_catch_weight) products where the actual carton weight differs from the sales_product spec. NULL for fixed-weight cases.';
COMMENT ON COLUMN sales_po_asn_carton.pack_lot_id IS 'Lot traceability link. Required when sales_product.is_fsma_traceable is true so a recall can be enacted from a buyer scan back to the production lot.';
