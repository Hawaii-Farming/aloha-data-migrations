-- Pack restructure preflight: ABORT if irrecoverable conditions exist on hosted dev.
-- This must run BEFORE 20260518120000_pack_drop_views_triggers_guards.sql.
--
-- Catches:
--   (1) FSMA carton orphans  — sales_sps_po_asn_carton rows that would lose pack_lot link.
--   (2) Sales fulfillment orphans — same condition; lower stakes but counted.
--   (3) Shelf-life orphans  — same condition; affects shelf_life trial trace.
--   (4) Duplicate-lot collisions — multiple pack_lot rows with the same natural key that
--       both contain the same product → would silently merge in the pack_session backfill.
--
-- All counts MUST be zero for the migration to proceed.

DO $$
DECLARE
    v_carton_orphans          INT;
    v_carton_null_harvest     INT;
    v_carton_missing_item     INT;
    v_fulfillment_orphans     INT;
    v_fulfillment_null_harvest INT;
    v_fulfillment_missing_item INT;
    v_shelf_life_orphans      INT;
    v_shelf_life_null_harvest INT;
    v_shelf_life_missing_item INT;
    v_dup_lot_collisions      INT;
    v_fsafe_orphans           INT;
BEGIN
    -- (1) FSMA carton orphans: pack_lot has NULL harvest_date OR no pack_lot_item for the carton's product.
    SELECT COUNT(*) INTO v_carton_orphans
      FROM sales_sps_po_asn_carton c
      JOIN pack_lot       pl  ON pl.id  = c.pack_lot_id
      JOIN sales_po_line  spl ON spl.id = c.sales_po_line_id
     WHERE pl.harvest_date IS NULL
        OR NOT EXISTS (
            SELECT 1
              FROM pack_lot_item pli
             WHERE pli.pack_lot_id     = pl.id
               AND pli.sales_product_id = spl.sales_product_id
               AND pli.is_deleted       = false
        );

    SELECT COUNT(*) INTO v_carton_null_harvest
      FROM sales_sps_po_asn_carton c
      JOIN pack_lot pl ON pl.id = c.pack_lot_id
     WHERE pl.harvest_date IS NULL;

    SELECT COUNT(*) INTO v_carton_missing_item
      FROM sales_sps_po_asn_carton c
      JOIN pack_lot       pl  ON pl.id  = c.pack_lot_id
      JOIN sales_po_line  spl ON spl.id = c.sales_po_line_id
     WHERE pl.harvest_date IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
             FROM pack_lot_item pli
            WHERE pli.pack_lot_id      = pl.id
              AND pli.sales_product_id = spl.sales_product_id
              AND pli.is_deleted       = false
       );

    -- (2) sales_po_fulfillment orphans (same condition).
    SELECT COUNT(*) INTO v_fulfillment_orphans
      FROM sales_po_fulfillment f
      JOIN pack_lot       pl  ON pl.id  = f.pack_lot_id
      JOIN sales_po_line  spl ON spl.id = f.sales_po_line_id
     WHERE pl.harvest_date IS NULL
        OR NOT EXISTS (
            SELECT 1
              FROM pack_lot_item pli
             WHERE pli.pack_lot_id      = pl.id
               AND pli.sales_product_id = spl.sales_product_id
               AND pli.is_deleted       = false
        );

    -- Breakdown: how many fulfillment orphans are NULL-harvest vs missing pack_lot_item.
    SELECT COUNT(*) INTO v_fulfillment_null_harvest
      FROM sales_po_fulfillment f
      JOIN pack_lot pl ON pl.id = f.pack_lot_id
     WHERE pl.harvest_date IS NULL;

    SELECT COUNT(*) INTO v_fulfillment_missing_item
      FROM sales_po_fulfillment f
      JOIN pack_lot       pl  ON pl.id  = f.pack_lot_id
      JOIN sales_po_line  spl ON spl.id = f.sales_po_line_id
     WHERE pl.harvest_date IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
             FROM pack_lot_item pli
            WHERE pli.pack_lot_id      = pl.id
              AND pli.sales_product_id = spl.sales_product_id
              AND pli.is_deleted       = false
       );

    -- (3) pack_shelf_life orphans (rows with sales_product_id set — these would FK to pack_session).
    -- Rows with sales_product_id IS NULL are product-agnostic trials; pack_session_id ends up
    -- NULL for them by design — they're excluded from the orphan check.
    SELECT COUNT(*) INTO v_shelf_life_orphans
      FROM pack_shelf_life sl
      JOIN pack_lot pl ON pl.id = sl.pack_lot_id
     WHERE sl.sales_product_id IS NOT NULL
       AND (pl.harvest_date IS NULL
            OR NOT EXISTS (
                SELECT 1
                  FROM pack_lot_item pli
                 WHERE pli.pack_lot_id      = pl.id
                   AND pli.sales_product_id = sl.sales_product_id
                   AND pli.is_deleted       = false
            ));

    -- Breakdown for shelf-life.
    SELECT COUNT(*) INTO v_shelf_life_null_harvest
      FROM pack_shelf_life sl
      JOIN pack_lot pl ON pl.id = sl.pack_lot_id
     WHERE sl.sales_product_id IS NOT NULL
       AND pl.harvest_date IS NULL;

    SELECT COUNT(*) INTO v_shelf_life_missing_item
      FROM pack_shelf_life sl
      JOIN pack_lot pl ON pl.id = sl.pack_lot_id
     WHERE sl.sales_product_id IS NOT NULL
       AND pl.harvest_date    IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
             FROM pack_lot_item pli
            WHERE pli.pack_lot_id      = pl.id
              AND pli.sales_product_id = sl.sales_product_id
              AND pli.is_deleted       = false
       );

    -- (4) fsafe_test_hold orphans (its pack_lot_id may dangle if force-deleted).
    SELECT COUNT(*) INTO v_fsafe_orphans
      FROM fsafe_test_hold h
      LEFT JOIN pack_lot pl ON pl.id = h.pack_lot_id
     WHERE pl.id IS NULL;

    -- (5) Duplicate-lot natural-key collisions: multiple pack_lot rows for the same
    --     (org, farm, pack_date, harvest_date) that both contain the same sales_product.
    --     Backfill ON CONFLICT would silently drop the second; cartons referencing the
    --     dropped lot would re-bind to the surviving pack_session with the wrong lot_number.
    SELECT COUNT(*) INTO v_dup_lot_collisions
      FROM (
          SELECT pl.org_id, pl.farm_id, pl.pack_date, pli.sales_product_id, pl.harvest_date
            FROM pack_lot      pl
            JOIN pack_lot_item pli ON pli.pack_lot_id = pl.id
           WHERE pl.is_deleted   = false
             AND pli.is_deleted  = false
             AND pl.harvest_date IS NOT NULL
           GROUP BY pl.org_id, pl.farm_id, pl.pack_date, pli.sales_product_id, pl.harvest_date
          HAVING COUNT(*) > 1
      ) x;

    -- Report all counts every run so they appear in the migration log.
    RAISE NOTICE 'pack-preflight: carton_orphans=%, fulfillment_orphans=%, shelf_life_orphans=%, fsafe_orphans=%, dup_lot_collisions=%',
        v_carton_orphans, v_fulfillment_orphans, v_shelf_life_orphans, v_fsafe_orphans, v_dup_lot_collisions;
    RAISE NOTICE '  carton breakdown:      null_harvest=%, missing_pack_lot_item=%',     v_carton_null_harvest,      v_carton_missing_item;
    RAISE NOTICE '  fulfillment breakdown: null_harvest=%, missing_pack_lot_item=%',     v_fulfillment_null_harvest, v_fulfillment_missing_item;
    RAISE NOTICE '  shelf_life breakdown:  null_harvest=%, missing_pack_lot_item=%',     v_shelf_life_null_harvest,  v_shelf_life_missing_item;

    IF v_carton_orphans > 0 THEN
        RAISE EXCEPTION 'pack-preflight ABORT: % sales_sps_po_asn_carton rows would lose pack_lot link (FSMA trace). Resolve before pushing.', v_carton_orphans;
    END IF;

    IF v_fulfillment_orphans > 0 THEN
        RAISE EXCEPTION 'pack-preflight ABORT: % sales_po_fulfillment rows would lose pack_lot link. Resolve before pushing.', v_fulfillment_orphans;
    END IF;

    IF v_shelf_life_orphans > 0 THEN
        RAISE EXCEPTION 'pack-preflight ABORT: % pack_shelf_life rows would lose pack_lot link. Resolve before pushing.', v_shelf_life_orphans;
    END IF;

    IF v_fsafe_orphans > 0 THEN
        RAISE EXCEPTION 'pack-preflight ABORT: % fsafe_test_hold rows reference a missing pack_lot. Resolve before pushing.', v_fsafe_orphans;
    END IF;

    IF v_dup_lot_collisions > 0 THEN
        RAISE EXCEPTION 'pack-preflight ABORT: % duplicate-lot natural-key collisions would merge silently in pack_session backfill. Resolve manually (pick canonical lot_number per duplicate group) before pushing.', v_dup_lot_collisions;
    END IF;

    RAISE NOTICE 'pack-preflight OK: proceeding with restructure.';
END $$;
