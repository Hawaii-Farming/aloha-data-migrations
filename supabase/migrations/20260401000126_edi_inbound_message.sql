-- edi_inbound_message
-- ===================
-- Raw archive of every EDI document received from SPS Commerce. We write
-- the raw payload here first, then parse and apply downstream. If the
-- parse fails the raw_body stays for replay; if it succeeds parsed_at is
-- set and sales_po_id is filled in. This is the audit trail for "what
-- did the partner actually send us", separate from the resolved sales_po
-- which is our interpretation of it.
--
-- SPS-only table.

CREATE TABLE IF NOT EXISTS edi_inbound_message (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_trading_partner_id    TEXT REFERENCES sales_trading_partner(id),

    -- Document type — 850 (PO), 860 (PO Change), 870 (Status Inquiry),
    -- 997 (Functional Acknowledgement). Free text rather than CHECK because SPS adds
    -- new document types over time.
    document_type               TEXT NOT NULL,

    -- SPS message identifiers / SFTP filename for tracing
    sps_message_id              TEXT,
    source_filename             TEXT,

    -- The raw payload as received. SPS delivers either X12 (raw EDI) or
    -- their XML wrapper; we don't normalize on ingest.
    raw_body                    TEXT NOT NULL,

    received_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    parsed_at                   TIMESTAMPTZ,
    parse_error                 TEXT,

    -- Resolved target. NULL until parse succeeds and the doc is applied.
    sales_po_id                 UUID REFERENCES sales_po(id),

    -- 997 Functional Acknowledgement we sent back to SPS
    acknowledgement_sent_at     TIMESTAMPTZ,
    acknowledgement_status      TEXT CHECK (acknowledgement_status IN ('Accepted', 'AcceptedWithErrors', 'Rejected')),

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE edi_inbound_message IS 'SPS-only. Immutable archive of every inbound EDI document from SPS Commerce. Parser writes raw payload first, then attempts to apply; parsed_at + sales_po_id are filled in on success. Failed parses keep raw_body for replay. Used for compliance / audit (proving what the buyer actually sent) and for replay after parser bugs.';

CREATE INDEX idx_edi_inbound_org      ON edi_inbound_message (org_id);
CREATE INDEX idx_edi_inbound_partner  ON edi_inbound_message (sales_trading_partner_id);
CREATE INDEX idx_edi_inbound_document_type ON edi_inbound_message (document_type, received_at);
CREATE INDEX idx_edi_inbound_unparsed ON edi_inbound_message (received_at)
    WHERE parsed_at IS NULL AND parse_error IS NULL;

COMMENT ON COLUMN edi_inbound_message.document_type IS 'X12 transaction set number (e.g. 850, 860, 870, 997).';
COMMENT ON COLUMN edi_inbound_message.sps_message_id IS 'SPS Commerce message identifier from the API or SFTP filename. Used to deduplicate retries.';
COMMENT ON COLUMN edi_inbound_message.source_filename IS 'Original filename when delivered via SFTP. Useful for support requests to SPS.';
COMMENT ON COLUMN edi_inbound_message.raw_body IS 'Verbatim payload as received. Do not modify. Replay parser against this if upstream code changes.';
COMMENT ON COLUMN edi_inbound_message.parse_error IS 'Set when parse fails. Operator triages, fixes mapping (often a missing sales_product_buyer_part row), then replays.';
COMMENT ON COLUMN edi_inbound_message.sales_po_id IS 'Resolved PO once the parse succeeds and the document is applied. NULL for unparsed messages and for non-PO document types (e.g. 997 acknowledgements).';
COMMENT ON COLUMN edi_inbound_message.acknowledgement_status IS 'Status of the 997 Functional Acknowledgement we sent in response. Required by SPS within 24h of receipt.';
