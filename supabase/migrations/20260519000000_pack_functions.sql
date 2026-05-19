-- pack_functions
-- ==============
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

COMMENT ON FUNCTION "public"."pack_session_cases_guard_immutable"() IS 'BEFORE UPDATE on pack_session_cases: block changes to identity columns. cases_packed remains mutable.';


CREATE OR REPLACE FUNCTION "public"."pack_session_fails_guard_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_fails.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_fails.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_fails.pack_date is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_session_fails.pack_end_hour is immutable';
    END IF;
    IF NEW.pack_fail_category_id IS DISTINCT FROM OLD.pack_fail_category_id THEN
        RAISE EXCEPTION 'pack_session_fails.pack_fail_category_id is immutable';
    END IF;
    RETURN NEW;
END;
$$;


COMMENT ON FUNCTION "public"."pack_session_fails_guard_immutable"() IS 'BEFORE UPDATE on pack_session_fails: block changes to identity columns. fail_count and notes remain mutable.';


CREATE OR REPLACE FUNCTION "public"."pack_session_guard_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session.pack_date is immutable (delete + recreate to correct)';
    END IF;
    IF NEW.sales_product_id IS DISTINCT FROM OLD.sales_product_id THEN
        RAISE EXCEPTION 'pack_session.sales_product_id is immutable';
    END IF;
    IF NEW.harvest_date IS DISTINCT FROM OLD.harvest_date THEN
        RAISE EXCEPTION 'pack_session.harvest_date is immutable';
    END IF;
    IF OLD.started_at IS NOT NULL
       AND NEW.started_at IS DISTINCT FROM OLD.started_at THEN
        RAISE EXCEPTION 'pack_session.started_at is set-once and already recorded';
    END IF;
    -- New check: stopped_at requires started_at to already be set.
    IF NEW.stopped_at IS NOT NULL
       AND OLD.stopped_at IS NULL
       AND (NEW.started_at IS NULL OR OLD.started_at IS NULL) THEN
        RAISE EXCEPTION 'pack_session.stopped_at cannot be set on a row with NULL started_at';
    END IF;
    IF OLD.stopped_at IS NOT NULL
       AND NEW.stopped_at IS DISTINCT FROM OLD.stopped_at THEN
        RAISE EXCEPTION 'pack_session.stopped_at is set-once and already recorded';
    END IF;
    RETURN NEW;
END;
$$;


COMMENT ON FUNCTION "public"."pack_session_guard_immutable"() IS 'BEFORE UPDATE on pack_session: block changes to (org, farm, pack_date, sales_product_id, harvest_date). started_at/stopped_at are set-once. stopped_at additionally requires started_at IS NOT NULL.';


CREATE OR REPLACE FUNCTION "public"."pack_session_labor_hour_guard_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_labor_hour.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_labor_hour.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_labor_hour.pack_date is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_session_labor_hour.pack_end_hour is immutable (hour identity)';
    END IF;
    RETURN NEW;
END;
$$;


COMMENT ON FUNCTION "public"."pack_session_labor_hour_guard_immutable"() IS 'BEFORE UPDATE on pack_session_labor_hour: block changes to (org, farm, pack_date, pack_end_hour). Crew counts and metal-detect remain mutable.';


CREATE OR REPLACE FUNCTION "public"."pack_session_leftover_guard_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_leftover.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_leftover.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_leftover.pack_date is immutable';
    END IF;
    RETURN NEW;
END;
$$;


COMMENT ON FUNCTION "public"."pack_session_leftover_guard_immutable"() IS 'BEFORE UPDATE on pack_session_leftover: block changes to identity columns. Per-crop leftover values remain mutable.';


CREATE OR REPLACE FUNCTION "public"."pack_session_set_defaults"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_shelf_days INT;
BEGIN
    IF NEW.pack_lot IS NULL OR NEW.pack_lot = '' THEN
        NEW.pack_lot := to_char(NEW.pack_date, 'YYYYMMDD')
                     || '-'
                     || to_char(NEW.harvest_date, 'YYYYMMDD');
    END IF;

    IF NEW.best_by_date IS NULL THEN
        SELECT shelf_life_days INTO v_shelf_days
          FROM sales_product
         WHERE id = NEW.sales_product_id;

        NEW.best_by_date := NEW.harvest_date + COALESCE(v_shelf_days, 0);
    END IF;

    RETURN NEW;
END;
$$;


COMMENT ON FUNCTION "public"."pack_session_set_defaults"() IS 'BEFORE INSERT on pack_session: default pack_lot to {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD and best_by_date to harvest_date + sales_product.shelf_life_days when not supplied by caller.';


CREATE OR REPLACE FUNCTION "public"."pack_shelf_life_cascade_day"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


COMMENT ON FUNCTION "public"."pack_shelf_life_cascade_day"() IS 'AFTER UPDATE OF pack_session_id on pack_shelf_life: recompute shelf_life_day on result/photo children. Replaces pack_lot_id-based version dropped in 20260518121100.';


CREATE OR REPLACE FUNCTION "public"."pack_shelf_life_check_termination"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


CREATE OR REPLACE FUNCTION "public"."pack_shelf_life_set_day"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


COMMENT ON FUNCTION "public"."pack_shelf_life_set_day"() IS 'BEFORE INSERT/UPDATE on result/photo: compute shelf_life_day = observation_date − pack_session.pack_date of parent trial. Replaces pack_lot-based version dropped in 20260518121100.';


GRANT ALL ON FUNCTION "public"."pack_session_cases_guard_immutable"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_session_cases_guard_immutable"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_session_cases_guard_immutable"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_session_fails_guard_immutable"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_session_fails_guard_immutable"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_session_fails_guard_immutable"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_session_guard_immutable"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_session_guard_immutable"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_session_guard_immutable"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_session_labor_hour_guard_immutable"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_session_labor_hour_guard_immutable"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_session_labor_hour_guard_immutable"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_session_leftover_guard_immutable"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_session_leftover_guard_immutable"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_session_leftover_guard_immutable"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_session_set_defaults"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_session_set_defaults"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_session_set_defaults"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_cascade_day"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_cascade_day"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_cascade_day"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_check_termination"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_check_termination"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_check_termination"() TO "service_role";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_set_day"() TO "anon";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_set_day"() TO "authenticated";


GRANT ALL ON FUNCTION "public"."pack_shelf_life_set_day"() TO "service_role";

