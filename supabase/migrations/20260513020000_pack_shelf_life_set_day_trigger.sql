-- Enforce shelf_life_day = observation_date - pack_lot.pack_date
-- ================================================================
-- BEFORE INSERT/UPDATE trigger on pack_shelf_life_result and
-- pack_shelf_life_photo. Looks up the parent trial's pack_lot.pack_date
-- and recalculates shelf_life_day so the value is always consistent
-- regardless of what the client sent. Also backfills existing rows
-- (gsheets import shipped inconsistent values — same observation_date
-- but different shelf_life_day across result vs photo tables).

BEGIN;

CREATE OR REPLACE FUNCTION public.pack_shelf_life_set_day()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pack_date DATE;
BEGIN
  SELECT pl.pack_date
    INTO v_pack_date
    FROM public.pack_shelf_life t
    JOIN public.pack_lot       pl ON pl.id = t.pack_lot_id
   WHERE t.id = NEW.pack_shelf_life_id;

  IF v_pack_date IS NOT NULL AND NEW.observation_date IS NOT NULL THEN
    NEW.shelf_life_day := (NEW.observation_date - v_pack_date);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pack_shelf_life_result_set_day
  ON public.pack_shelf_life_result;
CREATE TRIGGER trg_pack_shelf_life_result_set_day
  BEFORE INSERT OR UPDATE OF observation_date, pack_shelf_life_id
  ON public.pack_shelf_life_result
  FOR EACH ROW
  EXECUTE FUNCTION public.pack_shelf_life_set_day();

DROP TRIGGER IF EXISTS trg_pack_shelf_life_photo_set_day
  ON public.pack_shelf_life_photo;
CREATE TRIGGER trg_pack_shelf_life_photo_set_day
  BEFORE INSERT OR UPDATE OF observation_date, pack_shelf_life_id
  ON public.pack_shelf_life_photo
  FOR EACH ROW
  EXECUTE FUNCTION public.pack_shelf_life_set_day();

-- Backfill existing rows.
UPDATE public.pack_shelf_life_result r
   SET shelf_life_day = (r.observation_date - pl.pack_date)
  FROM public.pack_shelf_life t,
       public.pack_lot pl
 WHERE r.pack_shelf_life_id = t.id
   AND pl.id = t.pack_lot_id
   AND pl.pack_date IS NOT NULL
   AND r.shelf_life_day IS DISTINCT FROM (r.observation_date - pl.pack_date);

UPDATE public.pack_shelf_life_photo p
   SET shelf_life_day = (p.observation_date - pl.pack_date)
  FROM public.pack_shelf_life t,
       public.pack_lot pl
 WHERE p.pack_shelf_life_id = t.id
   AND pl.id = t.pack_lot_id
   AND pl.pack_date IS NOT NULL
   AND p.shelf_life_day IS DISTINCT FROM (p.observation_date - pl.pack_date);

COMMIT;
