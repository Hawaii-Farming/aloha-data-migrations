-- Prefix all SPS Commerce EDI tables with sales_sps_
-- ==================================================
-- The 7 tables that exist solely to support the SPS Commerce integration
-- (trading partner registry, EDI inbound archive, ASN/shipment hierarchy,
-- buyer part-number cross-reference) are getting a sales_sps_ prefix so
-- the SPS-only surface area is obvious at a glance and can be ring-fenced
-- in tooling. The original CREATE TABLE migrations have been edited in
-- place so a fresh `supabase db reset` produces the new names directly;
-- this patch is the one-shot rename for the live dev + prod databases.
--
-- All renames use IF EXISTS so the file is a no-op on a fresh build
-- (where the tables already have the new names from 0112-0132).

ALTER TABLE IF EXISTS sales_trading_partner      RENAME TO sales_sps_trading_partner;
ALTER TABLE IF EXISTS sales_product_buyer_part   RENAME TO sales_sps_product_buyer_part;
ALTER TABLE IF EXISTS sales_edi_inbound_message  RENAME TO sales_sps_edi_inbound_message;
ALTER TABLE IF EXISTS sales_shipment             RENAME TO sales_sps_shipment;
ALTER TABLE IF EXISTS sales_shipment_container   RENAME TO sales_sps_shipment_container;
ALTER TABLE IF EXISTS sales_po_asn               RENAME TO sales_sps_po_asn;
ALTER TABLE IF EXISTS sales_po_asn_carton        RENAME TO sales_sps_po_asn_carton;

-- FK columns on tables that are NOT being renamed (sales_po, sales_pallet)
-- and FK columns on tables that ARE renamed but whose column also picked up
-- the sps prefix. Wrapped in DO blocks because ALTER TABLE ... RENAME COLUMN
-- has no IF EXISTS variant; this keeps the patch idempotent.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'sales_po'
                 AND column_name = 'sales_trading_partner_id') THEN
        ALTER TABLE sales_po
            RENAME COLUMN sales_trading_partner_id TO sales_sps_trading_partner_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'sales_pallet'
                 AND column_name = 'sales_shipment_container_id') THEN
        ALTER TABLE sales_pallet
            RENAME COLUMN sales_shipment_container_id TO sales_sps_shipment_container_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'sales_sps_edi_inbound_message'
                 AND column_name = 'sales_trading_partner_id') THEN
        ALTER TABLE sales_sps_edi_inbound_message
            RENAME COLUMN sales_trading_partner_id TO sales_sps_trading_partner_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'sales_sps_shipment_container'
                 AND column_name = 'sales_shipment_id') THEN
        ALTER TABLE sales_sps_shipment_container
            RENAME COLUMN sales_shipment_id TO sales_sps_shipment_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'sales_sps_po_asn'
                 AND column_name = 'sales_shipment_container_id') THEN
        ALTER TABLE sales_sps_po_asn
            RENAME COLUMN sales_shipment_container_id TO sales_sps_shipment_container_id;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public'
                 AND table_name = 'sales_sps_po_asn_carton'
                 AND column_name = 'sales_po_asn_id') THEN
        ALTER TABLE sales_sps_po_asn_carton
            RENAME COLUMN sales_po_asn_id TO sales_sps_po_asn_id;
    END IF;
END $$;
