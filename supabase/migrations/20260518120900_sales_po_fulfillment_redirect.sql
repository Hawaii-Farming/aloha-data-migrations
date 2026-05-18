-- Pack restructure step 10/17: redirect sales_po_fulfillment.pack_lot_id → pack_session_id.
-- Mapping per row:
--   fulfillment.pack_lot_id → pack_lot (pack_date, harvest_date)
--                           × sales_po_line.sales_product_id
--                           → pack_session (pack_date, sales_product_id, harvest_date)

ALTER TABLE sales_po_fulfillment
    ADD COLUMN pack_session_id UUID REFERENCES pack_session(id);

UPDATE sales_po_fulfillment AS f
   SET pack_session_id = ps.id
  FROM pack_lot       pl,
       sales_po_line  spl,
       pack_session   ps
 WHERE f.pack_lot_id       = pl.id
   AND spl.id              = f.sales_po_line_id
   AND ps.org_id           = pl.org_id
   AND ps.farm_id          = pl.farm_id
   AND ps.pack_date        = pl.pack_date
   AND ps.harvest_date     = pl.harvest_date
   AND ps.sales_product_id = spl.sales_product_id;

DROP INDEX IF EXISTS idx_sales_po_fulfillment_lot;
ALTER TABLE sales_po_fulfillment DROP COLUMN pack_lot_id;

CREATE INDEX idx_sales_po_fulfillment_pack_session ON sales_po_fulfillment (pack_session_id);

COMMENT ON COLUMN sales_po_fulfillment.pack_session_id IS 'Links fulfilled quantity to the specific pack_session (pack_date + product + harvest_date). Replaces the prior pack_lot_id FK. NULL for historical rows whose pack_lot had no associated pack_lot_item product mapping.';
