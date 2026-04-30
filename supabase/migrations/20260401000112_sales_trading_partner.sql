-- sales_trading_partner
-- =====================
-- One row per EDI trading partner (Costco, Safeway, etc.) that the org
-- exchanges documents with via SPS Commerce. Maps the buyer side of an
-- 850 Purchase Order to a sales_customer in our system, and tracks
-- which document flows are required for that partner (855 PO Acknowledgement,
-- 856 ASN, 810 Invoice).
--
-- SPS-only table: every column here exists to support the EDI lifecycle
-- and has no meaning outside the SPS integration. If you remove the SPS
-- automation, you remove this table.

CREATE TABLE IF NOT EXISTS sales_trading_partner (
    id                          TEXT PRIMARY KEY,
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_customer_id           TEXT NOT NULL REFERENCES sales_customer(id),

    -- SPS-side identifiers
    sps_partner_id              TEXT NOT NULL,
    sps_vendor_number           TEXT,

    -- Document flow flags — what we exchange with this partner
    acknowledgement_required    BOOLEAN NOT NULL DEFAULT false,
    asn_required                BOOLEAN NOT NULL DEFAULT false,
    invoice_required            BOOLEAN NOT NULL DEFAULT false,

    -- Routing defaults applied to outbound documents when the inbound
    -- 850 doesn't specify them. Most partners do specify; these are the
    -- fallback when they don't.
    default_carrier_scac        TEXT,
    default_payment_terms_net_days INTEGER,

    is_active                   BOOLEAN NOT NULL DEFAULT true,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_trading_partner_sps UNIQUE (org_id, sps_partner_id)
);

COMMENT ON TABLE sales_trading_partner IS 'SPS-only. EDI trading partner registry. Bridges an SPS partner identity (Costco, Safeway, etc.) to a sales_customer and declares which document flows (PO Acknowledgement / ASN / Invoice) are required for that partner. Inbound 850 routes to a partner via sps_partner_id; outbound 856/810 use the partner''s flags to decide whether to send.';

CREATE INDEX idx_sales_trading_partner_org      ON sales_trading_partner (org_id);
CREATE INDEX idx_sales_trading_partner_customer ON sales_trading_partner (sales_customer_id);

COMMENT ON COLUMN sales_trading_partner.sps_partner_id IS 'SPS Commerce partner identifier; matches the buyer code in the 850 envelope. Used to route inbound documents to the correct sales_customer.';
COMMENT ON COLUMN sales_trading_partner.sps_vendor_number IS 'Our vendor number assigned by the buyer (e.g. Costco vendor #). Echoed back on outbound 856/810.';
COMMENT ON COLUMN sales_trading_partner.acknowledgement_required IS 'Send 855 Purchase Order Acknowledgement after receiving 850.';
COMMENT ON COLUMN sales_trading_partner.asn_required IS 'Send 856 Advance Ship Notice when the PO ships.';
COMMENT ON COLUMN sales_trading_partner.invoice_required IS 'Send 810 Invoice after the ASN is sent. Some partners self-invoice from receipt.';
COMMENT ON COLUMN sales_trading_partner.default_carrier_scac IS 'Fallback Standard Carrier Alpha Code used on outbound 856 when the inbound 850 omits routing.';
