-- sales_shipment_container
-- ========================
-- One row per physical container (or trailer) on a booking. Real-world
-- shape this models:
--   * Ocean booking with Young Brothers carrying two reefer containers,
--     one with cucumbers and one with lettuce — same sales_shipment,
--     two sales_shipment_container rows with different container_number
--     and seal_number values.
--   * Truck shipment going to a Costco DC — one sales_shipment row with
--     a single sales_shipment_container row representing the trailer.
--
-- Each sales_po_asn references a container, not the shipment directly,
-- so the 856's HL*P*E (Equipment) hierarchy maps cleanly: each ASN
-- knows exactly which container its goods are in.
--
-- SPS-only table.

CREATE TABLE IF NOT EXISTS sales_shipment_container (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      TEXT NOT NULL REFERENCES org(id),
    sales_shipment_id           UUID NOT NULL REFERENCES sales_shipment(id) ON DELETE CASCADE,

    -- Physical container / trailer identifier — for ocean this is the
    -- container number stenciled on the box (e.g. YOBU1234567); for
    -- trucking it's the trailer number. Required because every 856 with
    -- a TD3 segment carries this.
    container_number            TEXT NOT NULL,

    -- Seal number applied at loading. Required by Costco / most retail
    -- buyers for receiving.
    seal_number                 TEXT,

    -- Container type — links to the existing lookup so capacity
    -- (maximum_spaces) and dimensions are inherited rather than
    -- redeclared per container.
    sales_container_type_id     TEXT REFERENCES sales_container_type(id),

    -- Optional: temperature for reefer containers. Many of our buyers
    -- require this on the 856 TD4 segment for cold-chain audit.
    temperature_uom             TEXT REFERENCES sys_uom(id),
    temperature_setpoint        NUMERIC,

    notes                       TEXT,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_sales_shipment_container UNIQUE (sales_shipment_id, container_number)
);

COMMENT ON TABLE sales_shipment_container IS 'SPS-only. Physical container or trailer in a booking. One row per container; an ocean booking with Young Brothers carrying separate reefers for cucumbers and lettuce yields two rows under one sales_shipment. Trucking shipments yield one row (the trailer).';

CREATE INDEX idx_sales_shipment_container_org      ON sales_shipment_container (org_id);
CREATE INDEX idx_sales_shipment_container_shipment ON sales_shipment_container (sales_shipment_id);

COMMENT ON COLUMN sales_shipment_container.container_number IS 'Container number stenciled on the box (ocean) or trailer number (trucking). Sent on 856 TD3 / Equipment segment. Unique within a shipment so the same booking can''t have two rows for the same container.';
COMMENT ON COLUMN sales_shipment_container.seal_number IS 'Seal number applied at loading. Required by Costco and most retail buyers for receiving; sent on 856 TD3.';
COMMENT ON COLUMN sales_shipment_container.sales_container_type_id IS 'Container type (20-foot dry, 40-foot reefer, etc.) from the existing sales_container_type lookup. Drives capacity (maximum_spaces) and dimensions on the 856.';
COMMENT ON COLUMN sales_shipment_container.temperature_setpoint IS 'Reefer setpoint temperature. Required on 856 TD4 by buyers with cold-chain compliance (Costco, Whole Foods).';
