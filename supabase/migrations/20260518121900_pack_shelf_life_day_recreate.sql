-- Recreate the shelf-life-day cascade triggers against the new pack_session schema.
-- Originals (20260513020000, 20260513020100) joined pack_shelf_life → pack_lot via pack_lot_id.
-- New: join pack_shelf_life → pack_session via pack_session_id. pack_session.pack_date is
-- immutable (per immutability guard), so the pack_lot.pack_date-change cascade trigger is
-- no longer needed and is intentionally not recreated.

-- ---------------------------------------------------------------
-- BEFORE INSERT/UPDATE on result/photo: compute shelf_life_day from parent trial's pack_session.pack_date.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pack_shelf_life_set_day()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pack_date DATE;
BEGIN
    SELECT ps.pack_date
      INTO v_pack_date
      FROM public.pack_shelf_life t
      JOIN public.pack_session    ps ON ps.id = t.pack_session_id
     WHERE t.id = NEW.pack_shelf_life_id;

    IF v_pack_date IS NOT NULL AND NEW.observation_date IS NOT NULL THEN
        NEW.shelf_life_day := (NEW.observation_date - v_pack_date);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pack_shelf_life_result_set_day ON public.pack_shelf_life_result;
CREATE TRIGGER trg_pack_shelf_life_result_set_day
    BEFORE INSERT OR UPDATE OF observation_date, pack_shelf_life_id
    ON public.pack_shelf_life_result
    FOR EACH ROW
    EXECUTE FUNCTION public.pack_shelf_life_set_day();

DROP TRIGGER IF EXISTS trg_pack_shelf_life_photo_set_day ON public.pack_shelf_life_photo;
CREATE TRIGGER trg_pack_shelf_life_photo_set_day
    BEFORE INSERT OR UPDATE OF observation_date, pack_shelf_life_id
    ON public.pack_shelf_life_photo
    FOR EACH ROW
    EXECUTE FUNCTION public.pack_shelf_life_set_day();

-- ---------------------------------------------------------------
-- AFTER UPDATE OF pack_session_id on pack_shelf_life: recompute children's shelf_life_day.
-- (Trial moved to a different session, or session attached for the first time.)
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
    IF NEW.pack_session_id IS DISTINCT FROM OLD.pack_session_id THEN
        SELECT pack_date
          INTO v_pack_date
          FROM public.pack_session
         WHERE id = NEW.pack_session_id;

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

DROP TRIGGER IF EXISTS trg_pack_shelf_life_cascade_day ON public.pack_shelf_life;
CREATE TRIGGER trg_pack_shelf_life_cascade_day
    AFTER UPDATE OF pack_session_id ON public.pack_shelf_life
    FOR EACH ROW
    EXECUTE FUNCTION public.pack_shelf_life_cascade_day();

-- Backfill existing rows once against the new linkage.
UPDATE public.pack_shelf_life_result r
   SET shelf_life_day = (r.observation_date - ps.pack_date)
  FROM public.pack_shelf_life t,
       public.pack_session    ps
 WHERE r.pack_shelf_life_id = t.id
   AND ps.id                = t.pack_session_id
   AND ps.pack_date         IS NOT NULL
   AND r.shelf_life_day     IS DISTINCT FROM (r.observation_date - ps.pack_date);

UPDATE public.pack_shelf_life_photo p
   SET shelf_life_day = (p.observation_date - ps.pack_date)
  FROM public.pack_shelf_life t,
       public.pack_session    ps
 WHERE p.pack_shelf_life_id = t.id
   AND ps.id                = t.pack_session_id
   AND ps.pack_date         IS NOT NULL
   AND p.shelf_life_day     IS DISTINCT FROM (p.observation_date - ps.pack_date);

COMMENT ON FUNCTION public.pack_shelf_life_set_day      IS 'BEFORE INSERT/UPDATE on result/photo: compute shelf_life_day = observation_date − pack_session.pack_date of parent trial. Replaces pack_lot-based version dropped in 20260518121100.';
COMMENT ON FUNCTION public.pack_shelf_life_cascade_day  IS 'AFTER UPDATE OF pack_session_id on pack_shelf_life: recompute shelf_life_day on result/photo children. Replaces pack_lot_id-based version dropped in 20260518121100.';
