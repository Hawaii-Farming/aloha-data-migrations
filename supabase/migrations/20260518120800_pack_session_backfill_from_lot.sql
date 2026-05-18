-- Pack restructure step 9/17: seed pack_session from historical pack_lot × pack_lot_item
-- so the FK redirect on sales_po_fulfillment / sales_sps_po_asn_carton / pack_shelf_life
-- can find a matching pack_session row for every historical pack_lot reference.
--
-- Mapping per pack_lot:
--   pack_lot      (1 row, by org+farm+pack_date+harvest_date)
--     × pack_lot_item (N rows, one per product packed on that lot)
--       → N pack_session rows, one per product.
--
-- pack_lot rows with NULL harvest_date are SKIPPED — pack_session.harvest_date is NOT NULL
-- and we have no defensible fallback. (Audit: ~0 such rows expected; any that exist were
-- incomplete records.)

INSERT INTO pack_session (
    id, org_id, farm_id,
    pack_date, sales_product_id, harvest_date, best_by_date, pack_lot,
    started_at, stopped_at,
    created_at, created_by, updated_at, updated_by, is_deleted
)
SELECT
    gen_random_uuid(),
    pl.org_id,
    pl.farm_id,
    pl.pack_date,
    pli.sales_product_id,
    pl.harvest_date,
    pli.best_by_date,
    pl.lot_number,
    NULL::TIMESTAMPTZ,                              -- no run-start known for historical
    NULL::TIMESTAMPTZ,                              -- no run-stop  known for historical
    COALESCE(pli.created_at, pl.created_at, now()),
    COALESCE(pli.created_by, pl.created_by),
    COALESCE(pli.updated_at, pl.updated_at, now()),
    COALESCE(pli.updated_by, pl.updated_by),
    false
  FROM pack_lot pl
  JOIN pack_lot_item pli
    ON pli.pack_lot_id = pl.id
   AND pli.is_deleted   = false
 WHERE pl.is_deleted    = false
   AND pl.harvest_date IS NOT NULL
ON CONFLICT (org_id, farm_id, pack_date, sales_product_id, harvest_date) DO NOTHING;

COMMENT ON COLUMN pack_session.pack_lot IS 'Lot number TEXT (formerly pack_lot.lot_number). Auto-generated on insert as {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD by trigger; user-editable. Historical rows backfilled from pack_lot.lot_number in migration 20260518120800.';
