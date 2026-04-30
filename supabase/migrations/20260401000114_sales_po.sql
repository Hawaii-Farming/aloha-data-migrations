CREATE TABLE IF NOT EXISTS sales_po (
    id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                          TEXT NOT NULL REFERENCES org(id),
    sales_customer_group_id         TEXT REFERENCES sales_customer_group(id),
    sales_customer_id               TEXT NOT NULL REFERENCES sales_customer(id),
    sales_fob_id                    TEXT REFERENCES sales_fob(id),

    -- EDI link. NULL for orders entered manually in the app; set when the
    -- PO arrived via SPS Commerce 850. The EDI fields below are populated
    -- from the 850 segments and are SPS-only — they remain NULL for
    -- manual orders.
    sales_trading_partner_id        TEXT REFERENCES sales_trading_partner(id),

    -- For manual orders this is the customer's PO number. For EDI orders
    -- this is the buyer's PO number from 850 BEG, echoed back on 856 BSN
    -- and 810 BIG.
    po_number                       TEXT,

    order_date                      DATE NOT NULL,
    invoice_date                    DATE,
    requested_ship_date             DATE,
    requested_delivery_date         DATE,
    recurring_frequency             TEXT CHECK (recurring_frequency IN ('Weekly', 'Biweekly', 'Monthly')),

    -- Buyer department / division / contact (from 850 N1/PER segments)
    buyer_department                TEXT,
    buyer_division                  TEXT,
    buyer_contact_name              TEXT,
    buyer_contact_email             TEXT,
    buyer_contact_phone             TEXT,

    -- Ship-to address (from 850 N1*ST segment; may differ from sales_customer)
    ship_to_name                    TEXT,
    ship_to_address1                TEXT,
    ship_to_address2                TEXT,
    ship_to_city                    TEXT,
    ship_to_state                   TEXT,
    ship_to_zip                     TEXT,
    ship_to_country                 TEXT,

    -- Bill-to address (from 850 N1*BT segment)
    bill_to_name                    TEXT,
    bill_to_address1                TEXT,
    bill_to_address2                TEXT,
    bill_to_city                    TEXT,
    bill_to_state                   TEXT,
    bill_to_zip                     TEXT,
    bill_to_country                 TEXT,

    -- Carrier / routing (from 850 TD5 segment)
    carrier_scac                    TEXT,
    carrier_routing                 TEXT,

    -- Payment terms (from 850 ITD segment, e.g. 30 for Net 30)
    payment_terms_net_days          INTEGER,

    notes                           TEXT,

    -- Lifecycle state. Manual orders flow Draft -> Approved ->
    -- Fulfilled/Unfulfilled (or Past Due). EDI orders flow
    -- Received -> Acknowledged -> Approved -> Shipped -> Invoiced.
    status                          TEXT NOT NULL DEFAULT 'Draft' CHECK (status IN (
        'Draft',
        'Received',
        'Acknowledged',
        'Approved',
        'Shipped',
        'Invoiced',
        'Fulfilled',
        'Unfulfilled',
        'Past Due'
    )),

    approved_at                     TIMESTAMPTZ,
    approved_by                     TEXT,
    qb_uploaded_at                  TIMESTAMPTZ,
    qb_uploaded_by                  TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                      TEXT,
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                      TEXT,
    is_deleted                      BOOLEAN NOT NULL DEFAULT false,

    -- Named FKs so PostgREST can disambiguate when embedding hr_employee
    CONSTRAINT fk_sales_po_approved_by
      FOREIGN KEY (approved_by) REFERENCES hr_employee(id),
    CONSTRAINT fk_sales_po_qb_uploaded_by
      FOREIGN KEY (qb_uploaded_by) REFERENCES hr_employee(id)
);

COMMENT ON TABLE sales_po IS 'Customer order header. One row per order. Tracks customer, FOB, dates, approval workflow, optional recurring frequency, and EDI snapshot fields (buyer_*, ship_to_*, bill_to_*, carrier_*, payment_terms_*) populated from inbound SPS 850 documents.';

CREATE INDEX idx_sales_po_org_id          ON sales_po (org_id);
CREATE INDEX idx_sales_po_customer        ON sales_po (sales_customer_id);
CREATE INDEX idx_sales_po_status          ON sales_po (org_id, status);
CREATE INDEX idx_sales_po_trading_partner ON sales_po (sales_trading_partner_id);

COMMENT ON COLUMN sales_po.sales_trading_partner_id IS 'EDI-only. Set when this PO arrived via SPS Commerce 850. NULL for orders entered manually in the app.';
COMMENT ON COLUMN sales_po.recurring_frequency IS 'weekly, biweekly, monthly; null means not recurring; auto-creates a new order after status is marked fulfilled';
COMMENT ON COLUMN sales_po.status IS 'Lifecycle state. Manual orders flow Draft -> Approved -> Fulfilled/Unfulfilled (or Past Due). EDI orders flow Received -> Acknowledged -> Approved -> Shipped -> Invoiced.';
COMMENT ON COLUMN sales_po.sales_customer_group_id IS 'Auto-set from sales_customer.sales_customer_group_id; read-only';
COMMENT ON COLUMN sales_po.sales_fob_id IS 'Auto-set from sales_customer.sales_fob_id; read-only';
COMMENT ON COLUMN sales_po.po_number IS 'Customer PO number. For manual orders this is what the customer gave us. For EDI orders this is the buyer''s PO number from 850 BEG, echoed back on 856 BSN and 810 BIG.';
COMMENT ON COLUMN sales_po.buyer_department IS 'EDI-only. From 850 BEG09 / REF. Costco/Safeway use this to route receiving.';
COMMENT ON COLUMN sales_po.buyer_division IS 'EDI-only. Buyer''s division code from the 850 envelope.';
COMMENT ON COLUMN sales_po.buyer_contact_name IS 'EDI-only. Buyer-side contact from 850 PER segment.';
COMMENT ON COLUMN sales_po.buyer_contact_email IS 'EDI-only. Buyer contact email from 850 PER.';
COMMENT ON COLUMN sales_po.buyer_contact_phone IS 'EDI-only. Buyer contact phone from 850 PER.';
COMMENT ON COLUMN sales_po.ship_to_name IS 'EDI-only. Ship-to party name from 850 N1*ST segment. Snapshot at PO receipt.';
COMMENT ON COLUMN sales_po.ship_to_address1 IS 'EDI-only. Ship-to address line 1 from 850 N3 segment.';
COMMENT ON COLUMN sales_po.ship_to_address2 IS 'EDI-only. Ship-to address line 2 from 850 N3 segment.';
COMMENT ON COLUMN sales_po.ship_to_city IS 'EDI-only. Ship-to city from 850 N4 segment.';
COMMENT ON COLUMN sales_po.ship_to_state IS 'EDI-only. Ship-to state code from 850 N4 segment.';
COMMENT ON COLUMN sales_po.ship_to_zip IS 'EDI-only. Ship-to postal code from 850 N4 segment.';
COMMENT ON COLUMN sales_po.ship_to_country IS 'EDI-only. Ship-to country from 850 N4 segment.';
COMMENT ON COLUMN sales_po.bill_to_name IS 'EDI-only. Bill-to party name from 850 N1*BT segment.';
COMMENT ON COLUMN sales_po.bill_to_address1 IS 'EDI-only. Bill-to address line 1 from 850 N3.';
COMMENT ON COLUMN sales_po.bill_to_address2 IS 'EDI-only. Bill-to address line 2 from 850 N3.';
COMMENT ON COLUMN sales_po.bill_to_city IS 'EDI-only. Bill-to city from 850 N4.';
COMMENT ON COLUMN sales_po.bill_to_state IS 'EDI-only. Bill-to state from 850 N4.';
COMMENT ON COLUMN sales_po.bill_to_zip IS 'EDI-only. Bill-to postal code from 850 N4.';
COMMENT ON COLUMN sales_po.bill_to_country IS 'EDI-only. Bill-to country from 850 N4.';
COMMENT ON COLUMN sales_po.carrier_scac IS 'EDI-only. Standard Carrier Alpha Code from 850 TD5 segment. Also sent on outbound 856 TD5.';
COMMENT ON COLUMN sales_po.carrier_routing IS 'EDI-only. Carrier routing instructions from 850 TD5.';
COMMENT ON COLUMN sales_po.requested_ship_date IS 'EDI-only. Requested ship date from 850 DTM*002 segment.';
COMMENT ON COLUMN sales_po.requested_delivery_date IS 'EDI-only. Requested delivery date from 850 DTM*002 / DTM*010 segment.';
COMMENT ON COLUMN sales_po.payment_terms_net_days IS 'EDI-only. Net days from 850 ITD segment (e.g. 30 for Net 30). Drives invoice due date on outbound 810.';
