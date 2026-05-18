-- Pack restructure self-heal: backfill missing pack_lot_item rows so the pack_session
-- backfill (step 9) can match every fulfillment / shelf-life / carton row.
--
-- Pre-existing data condition: some sales_po_fulfillment / pack_shelf_life / carton rows
-- reference a pack_lot for which pack_lot_item was never created for the row's
-- sales_product. Diagnostic counted 328 fulfillment + 222 shelf-life orphans of this kind.
--
-- Strategy: for every (pack_lot_id, sales_product_id) tuple needed by an upstream trace
-- table but missing from pack_lot_item, INSERT a synthetic pack_lot_item with pack_quantity=0
-- and best_by_date derived from sales_product.shelf_life_days. These rows live just long
-- enough for the pack_session backfill (step 9) to join them — pack_lot_item is dropped
-- in step 14, so the synthetic rows die with the table.

INSERT INTO pack_lot_item (
    org_id, farm_id, pack_lot_id, sales_product_id,
    best_by_date, pack_quantity,
    created_by, updated_by
)
SELECT DISTINCT
    pl.org_id,
    pl.farm_id,
    pl.id,
    missing.sales_product_id,
    pl.harvest_date + COALESCE(sp.shelf_life_days, 0),
    0,
    'synth-restructure-20260518',
    'synth-restructure-20260518'
  FROM (
      -- Fulfillment-driven needs
      SELECT f.pack_lot_id, spl.sales_product_id
        FROM sales_po_fulfillment f
        JOIN sales_po_line       spl ON spl.id = f.sales_po_line_id
       WHERE f.pack_lot_id IS NOT NULL

      UNION

      -- Shelf-life-driven needs (carries sales_product_id directly)
      SELECT sl.pack_lot_id, sl.sales_product_id
        FROM pack_shelf_life sl
       WHERE sl.pack_lot_id      IS NOT NULL
         AND sl.sales_product_id IS NOT NULL

      UNION

      -- Carton-driven needs (currently 0 but included for safety / future)
      SELECT c.pack_lot_id, spl.sales_product_id
        FROM sales_sps_po_asn_carton c
        JOIN sales_po_line           spl ON spl.id = c.sales_po_line_id
       WHERE c.pack_lot_id IS NOT NULL
  ) AS missing
  JOIN pack_lot      pl ON pl.id = missing.pack_lot_id
  JOIN sales_product sp ON sp.id = missing.sales_product_id
 WHERE pl.harvest_date IS NOT NULL
   AND NOT EXISTS (
       SELECT 1
         FROM pack_lot_item pli
        WHERE pli.pack_lot_id      = missing.pack_lot_id
          AND pli.sales_product_id = missing.sales_product_id
          AND pli.is_deleted       = false
   )
ON CONFLICT (pack_lot_id, sales_product_id) DO NOTHING;

-- Report how many synthetic rows were created.
DO $$
DECLARE v_synth INT;
BEGIN
    SELECT COUNT(*) INTO v_synth
      FROM pack_lot_item
     WHERE created_by = 'synth-restructure-20260518';
    RAISE NOTICE 'pack-self-heal: inserted % synthetic pack_lot_item rows to close trace gaps.', v_synth;
END $$;
