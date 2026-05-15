-- Second-pass pack data wipe on aloha-dev so the operator can re-test
-- the per-minute cadence build from a clean slate. Hard delete (not
-- soft) because pack_session has UNIQUE(org_id, farm_id, pack_date)
-- and tombstones still occupy the slot.

DELETE FROM pack_session_leftover;
DELETE FROM pack_session_product_hour;
DELETE FROM pack_productivity_hour_fail;
DELETE FROM pack_productivity_hour;
DELETE FROM pack_session_product_run;
DELETE FROM pack_lot_item;
DELETE FROM pack_lot;
DELETE FROM pack_session;
