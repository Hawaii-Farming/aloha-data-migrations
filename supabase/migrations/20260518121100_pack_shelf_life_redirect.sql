-- Pack restructure step 12/17: redirect pack_shelf_life.pack_lot_id → pack_session_id.
-- pack_shelf_life already carries sales_product_id directly, so the lookup is simpler than
-- the fulfillment/carton variants.
--
-- Pre-step: drop the 3 shelf-life-day cascade triggers/functions that reference pack_lot_id
-- (defined in 20260513020000 and 20260513020100). Recreated against pack_session in a
-- follow-up migration (20260518121900_pack_shelf_life_day_recreate).

DROP TRIGGER  IF EXISTS trg_pack_shelf_life_result_set_day ON pack_shelf_life_result;
DROP TRIGGER  IF EXISTS trg_pack_shelf_life_photo_set_day  ON pack_shelf_life_photo;
DROP TRIGGER  IF EXISTS trg_pack_shelf_life_cascade_day    ON pack_shelf_life;
DROP TRIGGER  IF EXISTS trg_pack_lot_cascade_shelf_life_day ON pack_lot;
DROP FUNCTION IF EXISTS public.pack_shelf_life_set_day();
DROP FUNCTION IF EXISTS public.pack_shelf_life_cascade_day();
DROP FUNCTION IF EXISTS public.pack_lot_cascade_shelf_life_day();

ALTER TABLE pack_shelf_life
    ADD COLUMN pack_session_id UUID REFERENCES pack_session(id);

UPDATE pack_shelf_life AS sl
   SET pack_session_id = ps.id
  FROM pack_lot     pl,
       pack_session ps
 WHERE sl.pack_lot_id      = pl.id
   AND ps.org_id           = pl.org_id
   AND ps.farm_id          = pl.farm_id
   AND ps.pack_date        = pl.pack_date
   AND ps.harvest_date     = pl.harvest_date
   AND ps.sales_product_id = sl.sales_product_id;

DROP INDEX IF EXISTS idx_pack_shelf_life_lot;
ALTER TABLE pack_shelf_life DROP COLUMN pack_lot_id;

CREATE INDEX idx_pack_shelf_life_pack_session ON pack_shelf_life (pack_session_id);

COMMENT ON COLUMN pack_shelf_life.pack_session_id IS 'Links the shelf-life trial to the specific pack_session it sampled from (pack_date + product + harvest_date). Replaces prior pack_lot_id FK.';
