-- sales_product -- drop is_active and temperature_uom
-- ====================================================
-- is_active is redundant with is_deleted (soft-delete is the canonical
-- "not in use" signal across this schema). temperature_uom carried no
-- per-row UOM context. Original migration 20260401000041 has been
-- edited in place so fresh-DB rebuilds get the correct shape; this
-- patch drops both columns from the live DB.

ALTER TABLE sales_product
    DROP COLUMN IF EXISTS is_active,
    DROP COLUMN IF EXISTS temperature_uom;
