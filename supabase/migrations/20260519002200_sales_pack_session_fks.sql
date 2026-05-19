-- Cross-module FKs: sales_po_fulfillment + sales_sps_po_asn_carton → pack_session
-- ================================================================================
-- Bridges the sales side of the schema to the new pack_session model.
-- Runs AFTER 20260518230000_pack_module_consolidated.sql so pack_session
-- exists by the time we reference it.
--
-- Replaces (idempotent rewrite of) the two earlier "redirect" migrations
-- that the pack-module consolidation deleted:
--   20260518120900_sales_po_fulfillment_redirect.sql
--   20260518121000_sales_sps_carton_redirect.sql
--
-- Idempotent across:
--   * dev (column may already exist with orphan values from the old
--     redirect file that was just reverted in schema_migrations)
--   * prod (column does NOT exist; freshly added)
--   * future fresh rebuilds (column added cleanly)

-- ---- sales_po_fulfillment ----------------------------------------
ALTER TABLE public.sales_po_fulfillment
    ADD COLUMN IF NOT EXISTS pack_session_id UUID;

-- Drop any stale FK from the prior redirect file before re-adding.
ALTER TABLE public.sales_po_fulfillment
    DROP CONSTRAINT IF EXISTS sales_po_fulfillment_pack_session_id_fkey;

-- NULL out orphan references that point at pack_session UUIDs the
-- consolidated migration just dropped (only matters on dev where the
-- column carried over with values; no-op on prod where the column was
-- freshly added above).
UPDATE public.sales_po_fulfillment
   SET pack_session_id = NULL
 WHERE pack_session_id IS NOT NULL
   AND pack_session_id NOT IN (SELECT id FROM public.pack_session);

ALTER TABLE public.sales_po_fulfillment
    ADD CONSTRAINT sales_po_fulfillment_pack_session_id_fkey
        FOREIGN KEY (pack_session_id) REFERENCES public.pack_session(id);

CREATE INDEX IF NOT EXISTS idx_sales_po_fulfillment_pack_session
    ON public.sales_po_fulfillment (pack_session_id);

COMMENT ON COLUMN public.sales_po_fulfillment.pack_session_id IS
    'Links fulfilled quantity to the specific pack_session (pack_date + product + harvest_date). NULL for historical rows whose pack_lot had no associated pack_lot_item product mapping.';

-- ---- sales_sps_po_asn_carton -------------------------------------
ALTER TABLE public.sales_sps_po_asn_carton
    ADD COLUMN IF NOT EXISTS pack_session_id UUID;

ALTER TABLE public.sales_sps_po_asn_carton
    DROP CONSTRAINT IF EXISTS sales_sps_po_asn_carton_pack_session_id_fkey;

UPDATE public.sales_sps_po_asn_carton
   SET pack_session_id = NULL
 WHERE pack_session_id IS NOT NULL
   AND pack_session_id NOT IN (SELECT id FROM public.pack_session);

ALTER TABLE public.sales_sps_po_asn_carton
    ADD CONSTRAINT sales_sps_po_asn_carton_pack_session_id_fkey
        FOREIGN KEY (pack_session_id) REFERENCES public.pack_session(id);

CREATE INDEX IF NOT EXISTS idx_sales_sps_carton_pack_session
    ON public.sales_sps_po_asn_carton (pack_session_id);

COMMENT ON COLUMN public.sales_sps_po_asn_carton.pack_session_id IS
    'Lot traceability link via pack_session. Required when sales_product.is_fsma_traceable is true so a recall can be enacted from a buyer scan back to the production lot.';
