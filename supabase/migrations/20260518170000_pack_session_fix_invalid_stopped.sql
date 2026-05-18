-- Fix 4 pack_session rows where stopped_at was set on a row that never had
-- started_at — invalid state caused by the Stop button being reachable on
-- backfilled rows before the front-end fix landed.
--
-- Also harden the immutability guard to reject any future stopped_at change
-- when started_at IS NULL.

-- Report the rows being fixed.
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM pack_session
     WHERE started_at IS NULL
       AND stopped_at IS NOT NULL;
    RAISE NOTICE 'pack_session: resetting stopped_at on % rows with NULL started_at', v_count;
END $$;

-- The existing set-once guard rejects NULL-ing stopped_at. Drop the trigger,
-- fix the data, then recreate with the hardened body below.
DROP TRIGGER IF EXISTS pack_session_before_update_guard ON pack_session;

UPDATE pack_session
   SET stopped_at = NULL
 WHERE started_at IS NULL
   AND stopped_at IS NOT NULL;

-- Harden the guard: stopped_at can only transition NULL→value when started_at IS NOT NULL.
CREATE OR REPLACE FUNCTION pack_session_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session.pack_date is immutable (delete + recreate to correct)';
    END IF;
    IF NEW.sales_product_id IS DISTINCT FROM OLD.sales_product_id THEN
        RAISE EXCEPTION 'pack_session.sales_product_id is immutable';
    END IF;
    IF NEW.harvest_date IS DISTINCT FROM OLD.harvest_date THEN
        RAISE EXCEPTION 'pack_session.harvest_date is immutable';
    END IF;
    IF OLD.started_at IS NOT NULL
       AND NEW.started_at IS DISTINCT FROM OLD.started_at THEN
        RAISE EXCEPTION 'pack_session.started_at is set-once and already recorded';
    END IF;
    -- New check: stopped_at requires started_at to already be set.
    IF NEW.stopped_at IS NOT NULL
       AND OLD.stopped_at IS NULL
       AND (NEW.started_at IS NULL OR OLD.started_at IS NULL) THEN
        RAISE EXCEPTION 'pack_session.stopped_at cannot be set on a row with NULL started_at';
    END IF;
    IF OLD.stopped_at IS NOT NULL
       AND NEW.stopped_at IS DISTINCT FROM OLD.stopped_at THEN
        RAISE EXCEPTION 'pack_session.stopped_at is set-once and already recorded';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER pack_session_before_update_guard
BEFORE UPDATE ON pack_session
FOR EACH ROW EXECUTE FUNCTION pack_session_guard_immutable();

COMMENT ON FUNCTION pack_session_guard_immutable IS 'BEFORE UPDATE on pack_session: block changes to (org, farm, pack_date, sales_product_id, harvest_date). started_at/stopped_at are set-once. stopped_at additionally requires started_at IS NOT NULL.';
