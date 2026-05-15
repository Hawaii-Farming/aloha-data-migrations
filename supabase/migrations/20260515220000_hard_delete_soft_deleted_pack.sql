-- Hard-delete all soft-deleted pack rows on aloha-dev. The previous
-- wipe set is_deleted = true, but pack_session has a non-partial
-- UNIQUE (org_id, farm_id, pack_date) constraint that still blocks
-- the loader's auto-insert for today. Removing the tombstones frees
-- the slot.
--
-- Order: leaf tables first, then parents, so FK CASCADE rules (if
-- any) don't accidentally cascade unrelated data.

DELETE FROM pack_session_leftover         WHERE is_deleted = true;
DELETE FROM pack_session_product_hour     WHERE is_deleted = true;
DELETE FROM pack_productivity_hour_fail   WHERE is_deleted = true;
DELETE FROM pack_productivity_hour        WHERE is_deleted = true;
DELETE FROM pack_session_product_run      WHERE is_deleted = true;
DELETE FROM pack_lot_item                 WHERE is_deleted = true;
DELETE FROM pack_lot                      WHERE is_deleted = true;
DELETE FROM pack_session                  WHERE is_deleted = true;
