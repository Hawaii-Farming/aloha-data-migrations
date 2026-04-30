-- sales_shipment
-- ==============
-- Booking / voyage record. One row per carrier dispatch — for ocean
-- carriers like Young Brothers this is one booking that may carry many
-- physical containers; for trucking carriers this is one BOL with one
-- trailer (modeled as a single sales_shipment_container row).
--
-- Hierarchy:
--   sales_shipment              (booking — carrier, ship_date, BOL)
--     |- sales_shipment_container  (each physical container/trailer in the booking)
--         |- sales_po_asn          (one 856 EDI document per PO per container)
--             |- sales_po_asn_carton  (cartons with SSCC labels)
--
-- Container-level attributes (container_number, seal_number,
-- container_type) live on sales_shipment_container, not here. Booking-
-- level attributes (carrier, BOL, ship_date, ETA) live here so they're
-- not duplicated across containers in the same booking.
--
-- SPS-only table.

CREATE TABLE IF NOT EXISTS sales_shipment (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),

    -- Master Bill of Lading number — printed on freight paperwork and
    -- echoed on every 856 BSN02 for POs riding this booking.
    bol_number                  TEXT NOT NULL,

    -- Booking number — the carrier's reservation identifier, distinct
    -- from BOL for ocean carriers (Young Brothers issues a booking
    -- number when the slot is reserved, then a BOL when the cargo is
    -- tendered). For trucking, this is usually the same as bol_number
    -- and may be left NULL.
    booking_number              TEXT,

    -- Carrier identification
    carrier_scac                TEXT,
    carrier_pro_number          TEXT,

    -- Dates
    ship_date                   DATE NOT NULL,
    estimated_delivery_date     DATE,

    notes                       TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_shipment_bol UNIQUE (org_id, bol_number)
);

COMMENT ON TABLE sales_shipment IS 'SPS-only. Booking / voyage record. One row per carrier dispatch. For ocean carriers (Young Brothers) one booking carries multiple physical containers; for trucking one booking is one trailer. Container-level data lives on sales_shipment_container. Per-PO EDI state lives on sales_po_asn.';

CREATE INDEX idx_sales_shipment_org       ON sales_shipment (org_id);
CREATE INDEX idx_sales_shipment_ship_date ON sales_shipment (org_id, ship_date);

COMMENT ON COLUMN sales_shipment.bol_number IS 'Master Bill of Lading number for the booking. Echoed on every 856 BSN02 for POs riding this booking. Unique within the org.';
COMMENT ON COLUMN sales_shipment.booking_number IS 'Carrier booking / reservation identifier (e.g. Young Brothers booking number). Distinct from bol_number for ocean carriers; NULL for trucking where BOL serves both purposes.';
COMMENT ON COLUMN sales_shipment.carrier_scac IS 'Standard Carrier Alpha Code for the carrier (e.g. YOBR for Young Brothers). Sent on 856 TD5.';
COMMENT ON COLUMN sales_shipment.carrier_pro_number IS 'Carrier''s PRO / tracking number for the booking. Sent on 856 TD3 segment.';
