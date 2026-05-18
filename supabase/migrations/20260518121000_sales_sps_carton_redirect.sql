-- Pack restructure step 11/17: redirect sales_sps_po_asn_carton.pack_lot_id → pack_session_id.
-- FSMA carton-level traceability link. Same mapping as fulfillment.

ALTER TABLE sales_sps_po_asn_carton
    ADD COLUMN pack_session_id UUID REFERENCES pack_session(id);

UPDATE sales_sps_po_asn_carton AS c
   SET pack_session_id = ps.id
  FROM pack_lot       pl,
       sales_po_line  spl,
       pack_session   ps
 WHERE c.pack_lot_id       = pl.id
   AND spl.id              = c.sales_po_line_id
   AND ps.org_id           = pl.org_id
   AND ps.farm_id          = pl.farm_id
   AND ps.pack_date        = pl.pack_date
   AND ps.harvest_date     = pl.harvest_date
   AND ps.sales_product_id = spl.sales_product_id;

DROP INDEX IF EXISTS idx_sales_po_asn_carton_lot;
ALTER TABLE sales_sps_po_asn_carton DROP COLUMN pack_lot_id;

CREATE INDEX idx_sales_sps_carton_pack_session ON sales_sps_po_asn_carton (pack_session_id);

COMMENT ON COLUMN sales_sps_po_asn_carton.pack_session_id IS 'Lot traceability link via pack_session. Required when sales_product.is_fsma_traceable is true so a recall can be enacted from a buyer scan back to the production lot. Replaces prior pack_lot_id FK.';
