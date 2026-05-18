-- Pack restructure step 17/17: recreate immutability guards against the new schema.
--
-- Set-once rule for started_at / stopped_at: NULL → timestamp allowed exactly once.
--   Subsequent change (including back to NULL) is rejected.
--
-- Mutable fields explicitly allowed by spec:
--   pack_session.pack_date, pack_lot, best_by_date
--   pack_session_labor_hour.catchers/packers/mixers/boxers/fsafe_metal_detected/notes
--   pack_session_cases.cases_packed
--   pack_session_leftover.leftover_lettuce / leftover_watercress / leftover_arugula
--   pack_session_fails.fail_count / notes

-- ──────────────────────────────────────────────────────────────────
-- pack_session
-- ──────────────────────────────────────────────────────────────────

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
    -- pack_date is treated as immutable to prevent orphaning child denorm rows
    -- (pack_session_labor_hour / _cases / _leftover / _fails all carry pack_date with no FK).
    -- To correct a wrong pack_date, delete + recreate the session and its children.
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
    IF OLD.stopped_at IS NOT NULL
       AND NEW.stopped_at IS DISTINCT FROM OLD.stopped_at THEN
        RAISE EXCEPTION 'pack_session.stopped_at is set-once and already recorded';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_before_update_guard ON pack_session;
CREATE TRIGGER pack_session_before_update_guard
BEFORE UPDATE ON pack_session
FOR EACH ROW EXECUTE FUNCTION pack_session_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_session_labor_hour
--   Mutable: catchers, packers, mixers, boxers, fsafe_metal_detected,
--            fsafe_metal_detected_at, notes
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_labor_hour_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_labor_hour.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_labor_hour.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_labor_hour.pack_date is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_session_labor_hour.pack_end_hour is immutable (hour identity)';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_labor_hour_before_update_guard ON pack_session_labor_hour;
CREATE TRIGGER pack_session_labor_hour_before_update_guard
BEFORE UPDATE ON pack_session_labor_hour
FOR EACH ROW EXECUTE FUNCTION pack_session_labor_hour_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_session_cases
--   Mutable: cases_packed
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_cases_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_cases.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_cases.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_cases.pack_date is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_session_cases.pack_end_hour is immutable';
    END IF;
    IF NEW.sales_product_id IS DISTINCT FROM OLD.sales_product_id THEN
        RAISE EXCEPTION 'pack_session_cases.sales_product_id is immutable';
    END IF;
    IF NEW.harvest_date IS DISTINCT FROM OLD.harvest_date THEN
        RAISE EXCEPTION 'pack_session_cases.harvest_date is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_cases_before_update_guard ON pack_session_cases;
CREATE TRIGGER pack_session_cases_before_update_guard
BEFORE UPDATE ON pack_session_cases
FOR EACH ROW EXECUTE FUNCTION pack_session_cases_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_session_leftover
--   Mutable: leftover_lettuce, leftover_watercress, leftover_arugula
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_leftover_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_leftover.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_leftover.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_leftover.pack_date is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_leftover_before_update_guard ON pack_session_leftover;
CREATE TRIGGER pack_session_leftover_before_update_guard
BEFORE UPDATE ON pack_session_leftover
FOR EACH ROW EXECUTE FUNCTION pack_session_leftover_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_session_fails
--   Mutable: fail_count, notes
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_fails_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_fails.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_fails.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_fails.pack_date is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_session_fails.pack_end_hour is immutable';
    END IF;
    IF NEW.pack_fail_category_id IS DISTINCT FROM OLD.pack_fail_category_id THEN
        RAISE EXCEPTION 'pack_session_fails.pack_fail_category_id is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_fails_before_update_guard ON pack_session_fails;
CREATE TRIGGER pack_session_fails_before_update_guard
BEFORE UPDATE ON pack_session_fails
FOR EACH ROW EXECUTE FUNCTION pack_session_fails_guard_immutable();

COMMENT ON FUNCTION pack_session_guard_immutable             IS 'BEFORE UPDATE on pack_session: block changes to (org, farm, pack_date, sales_product_id, harvest_date). started_at/stopped_at are set-once. pack_lot text and best_by_date remain mutable.';
COMMENT ON FUNCTION pack_session_labor_hour_guard_immutable  IS 'BEFORE UPDATE on pack_session_labor_hour: block changes to (org, farm, pack_date, pack_end_hour). Crew counts and metal-detect remain mutable.';
COMMENT ON FUNCTION pack_session_cases_guard_immutable       IS 'BEFORE UPDATE on pack_session_cases: block changes to identity columns. cases_packed remains mutable.';
COMMENT ON FUNCTION pack_session_leftover_guard_immutable    IS 'BEFORE UPDATE on pack_session_leftover: block changes to identity columns. Per-crop leftover values remain mutable.';
COMMENT ON FUNCTION pack_session_fails_guard_immutable       IS 'BEFORE UPDATE on pack_session_fails: block changes to identity columns. fail_count and notes remain mutable.';
