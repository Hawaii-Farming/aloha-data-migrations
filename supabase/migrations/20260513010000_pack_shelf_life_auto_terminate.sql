-- Auto-terminate Shelf Life trials when a result hits the metric's fail criteria
-- ===============================================================================
-- Fires after INSERT or UPDATE on pack_shelf_life_result. Looks up the
-- metric, evaluates response_boolean/numeric/enum against the matching
-- fail_* fields, and on match flips pack_shelf_life.is_terminated to true.
-- Existing termination_reason is preserved; only the first failure stamps it.

BEGIN;

CREATE OR REPLACE FUNCTION public.pack_shelf_life_check_termination()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  metric  public.pack_shelf_life_metric%ROWTYPE;
  v_fail  BOOLEAN := false;
  v_reason TEXT;
BEGIN
  IF NEW.is_deleted = true THEN
    RETURN NEW;
  END IF;

  SELECT *
    INTO metric
    FROM public.pack_shelf_life_metric
   WHERE id = NEW.pack_shelf_life_metric_id
     AND org_id = NEW.org_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF metric.response_type = 'Boolean'
     AND metric.fail_boolean IS NOT NULL
     AND NEW.response_boolean = metric.fail_boolean THEN
    v_fail := true;
    v_reason := format('Failed metric "%s": %s',
                       metric.id, NEW.response_boolean);

  ELSIF metric.response_type = 'Numeric'
        AND NEW.response_numeric IS NOT NULL
        AND (
             (metric.fail_minimum_value IS NOT NULL
                AND NEW.response_numeric < metric.fail_minimum_value)
          OR (metric.fail_maximum_value IS NOT NULL
                AND NEW.response_numeric > metric.fail_maximum_value)
        ) THEN
    v_fail := true;
    v_reason := format('Failed metric "%s": %s outside [%s, %s]',
                       metric.id,
                       NEW.response_numeric,
                       coalesce(metric.fail_minimum_value::text, '-inf'),
                       coalesce(metric.fail_maximum_value::text, '+inf'));

  ELSIF metric.response_type = 'Enum'
        AND NEW.response_enum IS NOT NULL
        AND metric.fail_enum_values IS NOT NULL
        AND metric.fail_enum_values ? NEW.response_enum THEN
    v_fail := true;
    v_reason := format('Failed metric "%s": %s',
                       metric.id, NEW.response_enum);
  END IF;

  IF v_fail THEN
    UPDATE public.pack_shelf_life
       SET is_terminated      = true,
           termination_reason = COALESCE(termination_reason, v_reason),
           updated_at         = now()
     WHERE id = NEW.pack_shelf_life_id
       AND is_terminated = false;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pack_shelf_life_check_termination
  ON public.pack_shelf_life_result;

CREATE TRIGGER trg_pack_shelf_life_check_termination
  AFTER INSERT OR UPDATE ON public.pack_shelf_life_result
  FOR EACH ROW
  EXECUTE FUNCTION public.pack_shelf_life_check_termination();

COMMIT;
