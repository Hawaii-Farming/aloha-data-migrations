-- Rename SPS constraint + PK index names to match fresh-build auto-generation
-- ============================================================================
-- 20260508130000_sales_sps_rename did `ALTER TABLE/COLUMN RENAME` in place,
-- which PostgreSQL doesn't propagate to constraint or index names. So dev +
-- prod still carry the original "sales_*_pkey" / "sales_pallet_sales_
-- shipment_container_id_fkey" names attached to the renamed objects, while
-- a shadow DB rebuilt from migration files (CREATE TABLE sales_sps_*)
-- auto-generates "sales_sps_*_pkey" / "sales_pallet_sales_sps_shipment_
-- container_id_fkey".
--
-- That mismatch is what `supabase db pull` keeps capturing as drift every
-- day, and what blew up the 2026-05-11 sync-dev-to-prod run. Renaming the
-- constraints + indexes here brings live state in line with shadow so the
-- drift disappears at the source.
--
-- Each rename is wrapped in IF EXISTS so this is a no-op on a fresh build
-- (where the constraints already have the new names) and idempotent on
-- replays.

DO $$
DECLARE
    r RECORD;
BEGIN
    -- (table_name, old_constraint_name, new_constraint_name)
    FOR r IN
        SELECT * FROM (VALUES
            -- FK constraints on tables NOT renamed (point INTO the SPS tables)
            ('sales_pallet', 'sales_pallet_sales_shipment_container_id_fkey', 'sales_pallet_sales_sps_shipment_container_id_fkey'),
            ('sales_po',     'sales_po_sales_trading_partner_id_fkey',       'sales_po_sales_sps_trading_partner_id_fkey'),

            -- FK + CHECK constraints on the renamed SPS tables
            ('sales_sps_edi_inbound_message', 'sales_edi_inbound_message_acknowledgement_status_check',  'sales_sps_edi_inbound_message_acknowledgement_status_check'),
            ('sales_sps_edi_inbound_message', 'sales_edi_inbound_message_org_id_fkey',                    'sales_sps_edi_inbound_message_org_id_fkey'),
            ('sales_sps_edi_inbound_message', 'sales_edi_inbound_message_sales_po_id_fkey',               'sales_sps_edi_inbound_message_sales_po_id_fkey'),
            ('sales_sps_edi_inbound_message', 'sales_edi_inbound_message_sales_trading_partner_id_fkey',  'sales_sps_edi_inbound_message_sales_sps_trading_partner_id_fkey'),

            ('sales_sps_po_asn', 'sales_po_asn_org_id_fkey',                       'sales_sps_po_asn_org_id_fkey'),
            ('sales_sps_po_asn', 'sales_po_asn_sales_po_id_fkey',                  'sales_sps_po_asn_sales_po_id_fkey'),
            ('sales_sps_po_asn', 'sales_po_asn_sales_shipment_container_id_fkey',  'sales_sps_po_asn_sales_sps_shipment_container_id_fkey'),
            ('sales_sps_po_asn', 'sales_po_asn_status_check',                      'sales_sps_po_asn_status_check'),

            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_carton_type_check',            'sales_sps_po_asn_carton_carton_type_check'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_org_id_fkey',                  'sales_sps_po_asn_carton_org_id_fkey'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_pack_lot_id_fkey',             'sales_sps_po_asn_carton_pack_lot_id_fkey'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_parent_carton_id_fkey',        'sales_sps_po_asn_carton_parent_carton_id_fkey'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_sales_po_asn_id_fkey',         'sales_sps_po_asn_carton_sales_sps_po_asn_id_fkey'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_sales_po_fulfillment_id_fkey', 'sales_sps_po_asn_carton_sales_po_fulfillment_id_fkey'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_sales_po_line_id_fkey',        'sales_sps_po_asn_carton_sales_po_line_id_fkey'),
            ('sales_sps_po_asn_carton', 'sales_po_asn_carton_weight_uom_fkey',              'sales_sps_po_asn_carton_weight_uom_fkey'),

            ('sales_sps_product_buyer_part', 'sales_product_buyer_part_org_id_fkey',              'sales_sps_product_buyer_part_org_id_fkey'),
            ('sales_sps_product_buyer_part', 'sales_product_buyer_part_sales_customer_id_fkey',   'sales_sps_product_buyer_part_sales_customer_id_fkey'),
            ('sales_sps_product_buyer_part', 'sales_product_buyer_part_sales_product_id_fkey',    'sales_sps_product_buyer_part_sales_product_id_fkey'),

            ('sales_sps_shipment',           'sales_shipment_org_id_fkey',                       'sales_sps_shipment_org_id_fkey'),

            ('sales_sps_shipment_container', 'sales_shipment_container_org_id_fkey',             'sales_sps_shipment_container_org_id_fkey'),
            ('sales_sps_shipment_container', 'sales_shipment_container_sales_container_type_id_fkey', 'sales_sps_shipment_container_sales_container_type_id_fkey'),
            ('sales_sps_shipment_container', 'sales_shipment_container_sales_shipment_id_fkey',  'sales_sps_shipment_container_sales_sps_shipment_id_fkey'),
            ('sales_sps_shipment_container', 'sales_shipment_container_temperature_uom_fkey',    'sales_sps_shipment_container_temperature_uom_fkey'),

            ('sales_sps_trading_partner', 'sales_trading_partner_org_id_fkey',            'sales_sps_trading_partner_org_id_fkey'),
            ('sales_sps_trading_partner', 'sales_trading_partner_sales_customer_id_fkey', 'sales_sps_trading_partner_sales_customer_id_fkey'),

            -- PK constraints (note: PK index names are NOT auto-renamed with the constraint,
            -- so we ALTER INDEX RENAME separately below)
            ('sales_sps_edi_inbound_message', 'sales_edi_inbound_message_pkey', 'sales_sps_edi_inbound_message_pkey'),
            ('sales_sps_po_asn',              'sales_po_asn_pkey',              'sales_sps_po_asn_pkey'),
            ('sales_sps_po_asn_carton',       'sales_po_asn_carton_pkey',       'sales_sps_po_asn_carton_pkey'),
            ('sales_sps_product_buyer_part',  'sales_product_buyer_part_pkey',  'sales_sps_product_buyer_part_pkey'),
            ('sales_sps_shipment',            'sales_shipment_pkey',            'sales_sps_shipment_pkey'),
            ('sales_sps_shipment_container',  'sales_shipment_container_pkey',  'sales_sps_shipment_container_pkey'),
            ('sales_sps_trading_partner',     'sales_trading_partner_pkey',     'sales_sps_trading_partner_pkey')
        ) AS t(tbl, old_name, new_name)
    LOOP
        IF EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = r.old_name
              AND conrelid = ('public.' || r.tbl)::regclass
        ) THEN
            EXECUTE format(
                'ALTER TABLE public.%I RENAME CONSTRAINT %I TO %I',
                r.tbl, r.old_name, r.new_name
            );
        END IF;
    END LOOP;
END $$;

-- PK backing indexes — ALTER TABLE RENAME CONSTRAINT leaves these alone.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('sales_edi_inbound_message_pkey', 'sales_sps_edi_inbound_message_pkey'),
            ('sales_po_asn_pkey',              'sales_sps_po_asn_pkey'),
            ('sales_po_asn_carton_pkey',       'sales_sps_po_asn_carton_pkey'),
            ('sales_product_buyer_part_pkey',  'sales_sps_product_buyer_part_pkey'),
            ('sales_shipment_pkey',            'sales_sps_shipment_pkey'),
            ('sales_shipment_container_pkey',  'sales_sps_shipment_container_pkey'),
            ('sales_trading_partner_pkey',     'sales_sps_trading_partner_pkey')
        ) AS t(old_name, new_name)
    LOOP
        IF EXISTS (
            SELECT 1 FROM pg_class
            WHERE relname = r.old_name AND relkind = 'i'
              AND relnamespace = 'public'::regnamespace
        ) THEN
            EXECUTE format(
                'ALTER INDEX public.%I RENAME TO %I',
                r.old_name, r.new_name
            );
        END IF;
    END LOOP;
END $$;
