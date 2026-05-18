-- Pack restructure finalize: tighten pack_session.pack_lot to NOT NULL.
-- All existing rows were populated by:
--   - Backfill (20260518120800) — used pl.lot_number (pack_lot.lot_number is NOT NULL).
--   - Defaults trigger (20260518121700) — auto-fills future INSERTs.
-- Belt and suspenders: scan once before tightening the constraint.

DO $$
DECLARE v_missing INT;
BEGIN
    SELECT COUNT(*) INTO v_missing
      FROM pack_session
     WHERE pack_lot IS NULL OR pack_lot = '';
    IF v_missing > 0 THEN
        RAISE EXCEPTION 'pack_session has % rows with NULL/empty pack_lot — defaults trigger or backfill missed them. Resolve before tightening NOT NULL.', v_missing;
    END IF;
END $$;

ALTER TABLE pack_session
    ALTER COLUMN pack_lot SET NOT NULL;

COMMENT ON COLUMN pack_session.pack_lot IS 'Lot number TEXT (formerly pack_lot.lot_number). Auto-generated on INSERT as {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD; user-editable. NOT NULL — every session row has a lot identifier for FSMA traceability.';
