-- BEFORE INSERT trigger on pack_session_product_run:
--   1. Get-or-create pack_lot for (org, farm, session.pack_date, harvest_date) using deterministic lot_number.
--   2. Set NEW.pack_lot_id.
--   3. Upsert a pack_lot_item placeholder (pack_quantity = 0, best_by_date = harvest_date + sales_product.shelf_life_days).
--      Per-hour cases roll up via app code or a future view.

CREATE OR REPLACE FUNCTION pack_session_product_run_ensure_lot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_session       pack_session%ROWTYPE;
    v_lot_id        UUID;
    v_lot_number    TEXT;
    v_shelf_days    INT;
BEGIN
    SELECT * INTO v_session FROM pack_session WHERE id = NEW.pack_session_id;

    -- Get-or-create the lot for this (farm, pack_date, harvest_date).
    SELECT id INTO v_lot_id
      FROM pack_lot
     WHERE org_id      = NEW.org_id
       AND farm_id     = NEW.farm_id
       AND pack_date   = v_session.pack_date
       AND harvest_date IS NOT DISTINCT FROM NEW.harvest_date
       AND is_deleted  = false;

    IF v_lot_id IS NULL THEN
        v_lot_number := pack_lot_default_lot_number(v_session.pack_date, NEW.harvest_date);

        INSERT INTO pack_lot (org_id, farm_id, lot_number, pack_date, harvest_date, created_by, updated_by)
        VALUES (NEW.org_id, NEW.farm_id, v_lot_number, v_session.pack_date, NEW.harvest_date, NEW.created_by, NEW.updated_by)
        RETURNING id INTO v_lot_id;
    END IF;

    NEW.pack_lot_id := v_lot_id;

    -- Placeholder pack_lot_item so best_by + per-product totals have somewhere to live.
    SELECT shelf_life_days INTO v_shelf_days FROM sales_product WHERE id = NEW.sales_product_id;

    INSERT INTO pack_lot_item (org_id, farm_id, pack_lot_id, sales_product_id, best_by_date, pack_quantity, created_by, updated_by)
    VALUES (
        NEW.org_id,
        NEW.farm_id,
        v_lot_id,
        NEW.sales_product_id,
        NEW.harvest_date + COALESCE(v_shelf_days, 0),
        0,
        NEW.created_by,
        NEW.updated_by
    )
    ON CONFLICT (pack_lot_id, sales_product_id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pack_session_product_run_before_insert ON pack_session_product_run;

CREATE TRIGGER pack_session_product_run_before_insert
BEFORE INSERT ON pack_session_product_run
FOR EACH ROW EXECUTE FUNCTION pack_session_product_run_ensure_lot();

COMMENT ON FUNCTION pack_session_product_run_ensure_lot IS 'BEFORE INSERT: get-or-create pack_lot for (farm, pack_date, harvest_date), assign pack_lot_id, and placeholder pack_lot_item (qty=0, best_by from sales_product.shelf_life_days).';
