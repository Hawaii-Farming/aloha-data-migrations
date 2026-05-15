-- Immutability guards for pack tables.
--
-- Per the Packing Module spec, certain fields must NOT change after the
-- record is created (audit anchors, packlot identifiers, lifecycle
-- timestamps). Permissive UPDATE policies + a generic CRUD update path on
-- the app side leave nothing to enforce these rules — these BEFORE UPDATE
-- triggers raise an exception at the DB layer.
--
-- Set-once rule for started_at / stopped_at: NULL → timestamp is allowed
-- exactly once. Any subsequent change (including back to NULL) is
-- rejected.
--
-- Mutable fields explicitly allowed by the spec:
--   pack_session.pack_date
--   pack_productivity_hour.catchers / packers / mixers / boxers / fsafe_metal_detected / notes
--   pack_session_product_hour.cases_packed

-- ──────────────────────────────────────────────────────────────────
-- pack_session_product_run
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_product_run_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.pack_session_id IS DISTINCT FROM OLD.pack_session_id THEN
        RAISE EXCEPTION 'pack_session_product_run.pack_session_id is immutable';
    END IF;
    IF NEW.sales_product_id IS DISTINCT FROM OLD.sales_product_id THEN
        RAISE EXCEPTION 'pack_session_product_run.sales_product_id is immutable';
    END IF;
    IF NEW.harvest_date IS DISTINCT FROM OLD.harvest_date THEN
        RAISE EXCEPTION 'pack_session_product_run.harvest_date is immutable';
    END IF;
    IF NEW.pack_lot_id IS DISTINCT FROM OLD.pack_lot_id THEN
        RAISE EXCEPTION 'pack_session_product_run.pack_lot_id is set by trigger on insert and immutable';
    END IF;
    IF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
        RAISE EXCEPTION 'pack_session_product_run.started_at is immutable';
    END IF;
    IF OLD.stopped_at IS NOT NULL
       AND NEW.stopped_at IS DISTINCT FROM OLD.stopped_at THEN
        RAISE EXCEPTION 'pack_session_product_run.stopped_at is set-once and already recorded';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_product_run_before_update_guard
    ON pack_session_product_run;

CREATE TRIGGER pack_session_product_run_before_update_guard
BEFORE UPDATE ON pack_session_product_run
FOR EACH ROW EXECUTE FUNCTION pack_session_product_run_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_lot
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_lot_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.lot_number IS DISTINCT FROM OLD.lot_number THEN
        RAISE EXCEPTION 'pack_lot.lot_number is immutable';
    END IF;
    IF NEW.harvest_date IS DISTINCT FROM OLD.harvest_date THEN
        RAISE EXCEPTION 'pack_lot.harvest_date is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_lot.pack_date is immutable (audit anchor)';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_lot.farm_id is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_lot_before_update_guard ON pack_lot;

CREATE TRIGGER pack_lot_before_update_guard
BEFORE UPDATE ON pack_lot
FOR EACH ROW EXECUTE FUNCTION pack_lot_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_session
--   pack_date is intentionally mutable (spec: user may correct pack date)
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session.farm_id is immutable';
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
-- pack_productivity_hour
--   Mutable: catchers, packers, mixers, boxers, fsafe_metal_detected,
--            fsafe_metal_detected_at, notes, is_deleted
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_productivity_hour_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.pack_session_id IS DISTINCT FROM OLD.pack_session_id THEN
        RAISE EXCEPTION 'pack_productivity_hour.pack_session_id is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_productivity_hour.pack_end_hour is immutable (hour identity)';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_productivity_hour.farm_id is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_productivity_hour_before_update_guard
    ON pack_productivity_hour;

CREATE TRIGGER pack_productivity_hour_before_update_guard
BEFORE UPDATE ON pack_productivity_hour
FOR EACH ROW EXECUTE FUNCTION pack_productivity_hour_guard_immutable();

-- ──────────────────────────────────────────────────────────────────
-- pack_session_product_hour
--   Mutable: cases_packed
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pack_session_product_hour_guard_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.pack_productivity_hour_id IS DISTINCT FROM OLD.pack_productivity_hour_id THEN
        RAISE EXCEPTION 'pack_session_product_hour.pack_productivity_hour_id is immutable';
    END IF;
    IF NEW.pack_session_product_run_id IS DISTINCT FROM OLD.pack_session_product_run_id THEN
        RAISE EXCEPTION 'pack_session_product_hour.pack_session_product_run_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_product_hour.farm_id is immutable';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_product_hour_before_update_guard
    ON pack_session_product_hour;

CREATE TRIGGER pack_session_product_hour_before_update_guard
BEFORE UPDATE ON pack_session_product_hour
FOR EACH ROW EXECUTE FUNCTION pack_session_product_hour_guard_immutable();

COMMENT ON FUNCTION pack_session_product_run_guard_immutable IS 'BEFORE UPDATE: block changes to (session_id, sales_product_id, harvest_date, pack_lot_id, started_at). stopped_at is set-once.';
COMMENT ON FUNCTION pack_lot_guard_immutable IS 'BEFORE UPDATE: block changes to (lot_number, harvest_date, pack_date, farm_id).';
COMMENT ON FUNCTION pack_session_guard_immutable IS 'BEFORE UPDATE: block changes to farm_id. started_at / stopped_at are set-once.';
COMMENT ON FUNCTION pack_productivity_hour_guard_immutable IS 'BEFORE UPDATE: block changes to (session_id, pack_end_hour, farm_id). Crew counts remain mutable.';
COMMENT ON FUNCTION pack_session_product_hour_guard_immutable IS 'BEFORE UPDATE: block changes to (hour_id, run_id, farm_id). cases_packed remains mutable.';
