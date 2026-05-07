-- pack_dryer_result -- drop temperature_uom and moisture_uom
-- ===========================================================
-- Both columns were originally NOT NULL FK -> sys_uom on the table
-- defined in 20260401000137_pack_dryer_result.sql. They are no longer
-- needed (the readings carry no UOM context per row). The original
-- migration file has been edited in place so fresh-DB rebuilds get
-- the correct shape; this patch drops the columns from the live DB.

ALTER TABLE pack_dryer_result
    DROP COLUMN IF EXISTS temperature_uom,
    DROP COLUMN IF EXISTS moisture_uom;
