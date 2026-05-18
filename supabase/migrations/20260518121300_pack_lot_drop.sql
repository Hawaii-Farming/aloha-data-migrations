-- Pack restructure step 14/17: drop pack_lot, pack_lot_item, pack_variety.
-- All dependents (sales_po_fulfillment, sales_sps_po_asn_carton, pack_shelf_life,
-- fsafe_test_hold) were redirected in steps 10-13. pack_variety is replaced by 3 hard-coded
-- columns on pack_session_leftover (step 6).

DROP TABLE IF EXISTS pack_lot_item CASCADE;
DROP TABLE IF EXISTS pack_lot      CASCADE;
DROP TABLE IF EXISTS pack_variety  CASCADE;
