-- Pack restructure follow-up: BEFORE INSERT trigger on pack_session.
--   - Auto-set pack_lot TEXT      = {pack_date YYYYMMDD}-{harvest_date YYYYMMDD}.
--   - Auto-set best_by_date       = harvest_date + sales_product.shelf_life_days.
-- Both are user-editable post-insert (mutable per guards above) so callers may override.

CREATE OR REPLACE FUNCTION pack_session_set_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_shelf_days INT;
BEGIN
    IF NEW.pack_lot IS NULL OR NEW.pack_lot = '' THEN
        NEW.pack_lot := to_char(NEW.pack_date, 'YYYYMMDD')
                     || '-'
                     || to_char(NEW.harvest_date, 'YYYYMMDD');
    END IF;

    IF NEW.best_by_date IS NULL THEN
        SELECT shelf_life_days INTO v_shelf_days
          FROM sales_product
         WHERE id = NEW.sales_product_id;

        NEW.best_by_date := NEW.harvest_date + COALESCE(v_shelf_days, 0);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_before_insert_defaults ON pack_session;
CREATE TRIGGER pack_session_before_insert_defaults
BEFORE INSERT ON pack_session
FOR EACH ROW EXECUTE FUNCTION pack_session_set_defaults();

COMMENT ON FUNCTION pack_session_set_defaults IS 'BEFORE INSERT on pack_session: default pack_lot to {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD and best_by_date to harvest_date + sales_product.shelf_life_days when not supplied by caller.';
