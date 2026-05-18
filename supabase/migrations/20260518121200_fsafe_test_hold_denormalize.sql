-- Pack restructure step 13/17: denormalize fsafe_test_hold.
--
-- fsafe_test_hold is LOT-scoped (a hold prevents release of an entire production lot —
-- all products packed on the same pack_date/harvest_date). The new pack_session is
-- PRODUCT-scoped, so a single FK can't represent the relationship without duplicating
-- the hold row N times across products.
--
-- Resolution: drop the FK and denormalize pack_date + harvest_date. Recall queries join
-- on (org_id, farm_id, pack_date, harvest_date) to find all affected pack_session rows.

ALTER TABLE fsafe_test_hold
    ADD COLUMN pack_date    DATE,
    ADD COLUMN harvest_date DATE;

UPDATE fsafe_test_hold h
   SET pack_date    = pl.pack_date,
       harvest_date = pl.harvest_date
  FROM pack_lot pl
 WHERE h.pack_lot_id = pl.id;

-- Defense in depth: preflight (20260518115900) already aborts if any orphan exists,
-- but re-check here in case data shifted between preflight and this step.
DO $$
DECLARE v_missing INT;
BEGIN
    SELECT COUNT(*) INTO v_missing FROM fsafe_test_hold WHERE pack_date IS NULL;
    IF v_missing > 0 THEN
        RAISE EXCEPTION 'fsafe_test_hold has % rows with NULL pack_date after backfill — pack_lot_id must have pointed at a missing pack_lot. Resolve manually.', v_missing;
    END IF;
END $$;

ALTER TABLE fsafe_test_hold
    ALTER COLUMN pack_date    SET NOT NULL;
-- harvest_date stays nullable — some historical pack_lot rows had NULL harvest_date.

DROP INDEX IF EXISTS idx_fsafe_test_hold_lot;
ALTER TABLE fsafe_test_hold DROP COLUMN pack_lot_id;

CREATE INDEX idx_fsafe_test_hold_pack_date ON fsafe_test_hold (org_id, farm_id, pack_date, harvest_date);

COMMENT ON COLUMN fsafe_test_hold.pack_date    IS 'Pack date of the held lot. Recall join key with harvest_date.';
COMMENT ON COLUMN fsafe_test_hold.harvest_date IS 'Harvest date of the held lot. Nullable for historical rows whose source pack_lot had no harvest_date.';
