-- sales_product -- drop weight_uom and display_order
-- ====================================================
-- weight_uom is always pounds in this deployment (US-only). display_order
-- is unused in the UI. Original migration 20260401000041 has been edited
-- in place; this patch drops both columns from the live DB.

ALTER TABLE sales_product
    DROP COLUMN IF EXISTS weight_uom,
    DROP COLUMN IF EXISTS display_order;
