-- Cascade shelf_life_day when pack_date or trial's pack_lot_id changes
-- =====================================================================
-- Companion to 20260513020000_pack_shelf_life_set_day_trigger which
-- enforces shelf_life_day at insert/update of the result/photo rows.
-- This migration handles the cases where the upstream inputs change:
--
--   1. pack_lot.pack_date is corrected (lot data fix)
--   2. pack_shelf_life.pack_lot_id is reassigned (trial moved to a
--      different lot, or lot attached for the first time)
--
-- After either happens, every dependent shelf_life_day needs to be
-- recomputed. AFTER UPDATE triggers do the cascade.

BEGIN;

-- ---------------------------------------------------------------
-- 1. pack_lot.pack_date changes → recompute all dependent days
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pack_lot_cascade_shelf_life_day()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
    UPDATE public.pack_shelf_life_result r
       SET shelf_life_day = (r.observation_date - NEW.pack_date)
      FROM public.pack_shelf_life t
     WHERE t.id = r.pack_shelf_life_id
       AND t.pack_lot_id = NEW.id
       AND NEW.pack_date IS NOT NULL;

    UPDATE public.pack_shelf_life_photo p
       SET shelf_life_day = (p.observation_date - NEW.pack_date)
      FROM public.pack_shelf_life t
     WHERE t.id = p.pack_shelf_life_id
       AND t.pack_lot_id = NEW.id
       AND NEW.pack_date IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pack_lot_cascade_shelf_life_day
  ON public.pack_lot;
CREATE TRIGGER trg_pack_lot_cascade_shelf_life_day
  AFTER UPDATE OF pack_date ON public.pack_lot
  FOR EACH ROW
  EXECUTE FUNCTION public.pack_lot_cascade_shelf_life_day();

-- ---------------------------------------------------------------
-- 2. pack_shelf_life.pack_lot_id changes → recompute trial's days
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pack_shelf_life_cascade_day()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pack_date DATE;
BEGIN
  IF NEW.pack_lot_id IS DISTINCT FROM OLD.pack_lot_id THEN
    SELECT pack_date
      INTO v_pack_date
      FROM public.pack_lot
     WHERE id = NEW.pack_lot_id;

    IF v_pack_date IS NOT NULL THEN
      UPDATE public.pack_shelf_life_result
         SET shelf_life_day = (observation_date - v_pack_date)
       WHERE pack_shelf_life_id = NEW.id;

      UPDATE public.pack_shelf_life_photo
         SET shelf_life_day = (observation_date - v_pack_date)
       WHERE pack_shelf_life_id = NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pack_shelf_life_cascade_day
  ON public.pack_shelf_life;
CREATE TRIGGER trg_pack_shelf_life_cascade_day
  AFTER UPDATE OF pack_lot_id ON public.pack_shelf_life
  FOR EACH ROW
  EXECUTE FUNCTION public.pack_shelf_life_cascade_day();

COMMIT;
