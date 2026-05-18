-- Pack restructure step 2/17: wipe early-adoption pack_session* test data.
-- 6-23 rows total across these tables; semantics are changing fundamentally so retention
-- has no value. pack_lot / pack_lot_item retained for historical backfill in step 9.

TRUNCATE TABLE
    pack_session_product_hour,
    pack_session_leftover,
    pack_productivity_hour_fail,
    pack_productivity_hour,
    pack_session_product_run,
    pack_session
RESTART IDENTITY CASCADE;
