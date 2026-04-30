-- sales_po_asn
-- ============
-- Outbound 856 Advance Ship Notice header. One row per PO per container.
-- The 856 is a per-PO EDI document (separate transmission for each PO),
-- so per-document state lives here: status, sent_at, acknowledgement, raw payload.
--
-- A PO that splits across two containers in the same booking gets two
-- ASN rows — one per container — which maps cleanly to the 856's
-- HL*P*E (Equipment) hierarchy: each ASN identifies its container.
--
-- Hierarchy:
--   sales_shipment              (booking — carrier, BOL, ship_date)
--     |- sales_shipment_container (each physical container/trailer)
--         |- sales_po_asn          (one per PO per container)   <- this table
--             |- sales_po_asn_carton  (cartons with SSCC labels)
--
-- SPS-only table.

CREATE TABLE IF NOT EXISTS sales_po_asn (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_shipment_container_id UUID NOT NULL REFERENCES sales_shipment_container(id),
    sales_po_id                 UUID NOT NULL REFERENCES sales_po(id),

    -- Outbound lifecycle (per EDI document)
    status                      TEXT NOT NULL DEFAULT 'Pending'
        CHECK (status IN ('Pending', 'Sent', 'Acknowledged', 'Rejected', 'Cancelled')),
    sent_at                     TIMESTAMPTZ,
    acknowledged_at             TIMESTAMPTZ,
    sps_message_id              TEXT,

    -- Raw outbound payload we transmitted, for audit / replay
    raw_outbound                TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_po_asn_container_po UNIQUE (sales_shipment_container_id, sales_po_id)
);

COMMENT ON TABLE sales_po_asn IS 'SPS-only. Outbound 856 Advance Ship Notice header. One row per PO per container. Truck-/voyage-level info (BOL, carrier, ship_date) lives on sales_shipment; container info (number, seal, type) lives on sales_shipment_container; carton-level detail lives on sales_po_asn_carton. A PO split across two containers gets two ASN rows.';

CREATE INDEX idx_sales_po_asn_org       ON sales_po_asn (org_id);
CREATE INDEX idx_sales_po_asn_container ON sales_po_asn (sales_shipment_container_id);
CREATE INDEX idx_sales_po_asn_po        ON sales_po_asn (sales_po_id);
CREATE INDEX idx_sales_po_asn_status    ON sales_po_asn (status, created_at);

COMMENT ON COLUMN sales_po_asn.sales_shipment_container_id IS 'Container this PO is loaded in. Reach the booking via sales_shipment_container.sales_shipment_id.';
COMMENT ON COLUMN sales_po_asn.status IS 'Outbound lifecycle: Pending (built but not sent) -> Sent (transmitted to SPS) -> Acknowledged (SPS 997 received) | Rejected (functional acknowledgement failed). Cancelled if voided before send.';
COMMENT ON COLUMN sales_po_asn.sent_at IS 'Timestamp the 856 was transmitted to SPS. Drives buyer SLA windows (most retailers require ASN within 1h of departure).';
COMMENT ON COLUMN sales_po_asn.sps_message_id IS 'SPS-assigned identifier returned at submission. Used to correlate inbound 997 acknowledgements back to this row.';
COMMENT ON COLUMN sales_po_asn.raw_outbound IS 'Verbatim payload we transmitted. Kept for audit and for replay if SPS reports loss.';
