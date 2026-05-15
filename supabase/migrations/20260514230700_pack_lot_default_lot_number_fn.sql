-- Deterministic lot_number generator: {pack_date YYYYMMDD}-{harvest_date YYYYMMDD}.
-- If harvest_date is NULL, falls back to pack_date alone (legacy compat).

CREATE OR REPLACE FUNCTION pack_lot_default_lot_number(p_pack_date DATE, p_harvest_date DATE)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT to_char(p_pack_date, 'YYYYMMDD') ||
           CASE WHEN p_harvest_date IS NOT NULL
                THEN '-' || to_char(p_harvest_date, 'YYYYMMDD')
                ELSE ''
           END;
$$;

COMMENT ON FUNCTION pack_lot_default_lot_number IS 'Deterministic lot_number = {pack_date YYYYMMDD}-{harvest_date YYYYMMDD}. User-editable on pack_lot.lot_number.';
