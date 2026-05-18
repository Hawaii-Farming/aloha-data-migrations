-- Pack restructure step 1/17: drop everything that references the soon-to-be-restructured
-- tables. Views, the auto-lot trigger, immutability guards. Will be recreated against the
-- new schema in the final steps.

-- Views
DROP VIEW IF EXISTS pack_session_summary_v;
DROP VIEW IF EXISTS pack_session_product_run_summary_v;

-- Auto-lot trigger + helper function (pack_lot is being dropped)
DROP TRIGGER  IF EXISTS pack_session_product_run_before_insert ON pack_session_product_run;
DROP FUNCTION IF EXISTS pack_session_product_run_ensure_lot();
-- pack_lot_default_lot_number was defined in 20260514230700; only used by the trigger above.
DROP FUNCTION IF EXISTS pack_lot_default_lot_number(DATE, DATE);

-- Immutability guards (recreated at end against new schema/column names)
DROP TRIGGER  IF EXISTS pack_session_product_run_before_update_guard ON pack_session_product_run;
DROP FUNCTION IF EXISTS pack_session_product_run_guard_immutable();

DROP TRIGGER  IF EXISTS pack_lot_before_update_guard ON pack_lot;
DROP FUNCTION IF EXISTS pack_lot_guard_immutable();

DROP TRIGGER  IF EXISTS pack_session_before_update_guard ON pack_session;
DROP FUNCTION IF EXISTS pack_session_guard_immutable();

DROP TRIGGER  IF EXISTS pack_productivity_hour_before_update_guard ON pack_productivity_hour;
DROP FUNCTION IF EXISTS pack_productivity_hour_guard_immutable();

DROP TRIGGER  IF EXISTS pack_session_product_hour_before_update_guard ON pack_session_product_hour;
DROP FUNCTION IF EXISTS pack_session_product_hour_guard_immutable();
