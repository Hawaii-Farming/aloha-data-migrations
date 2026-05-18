


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_access_level"("target_org" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT sys_access_level_id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND org_id = target_org
    AND is_deleted = false
  LIMIT 1;
$$;


ALTER FUNCTION "public"."auth_access_level"("target_org" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."auth_access_level"("target_org" "text") IS 'Returns the current auth.uid()''s sys_access_level_id within the supplied org_id. SECURITY DEFINER + STABLE for safe inline use in views (e.g. CASE WHEN auth_access_level(org_id) = ''Team Lead'' THEN NULL ELSE col END).';



CREATE OR REPLACE FUNCTION "public"."auth_employee_id"("target_org" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND org_id = target_org
    AND is_deleted = false
  LIMIT 1;
$$;


ALTER FUNCTION "public"."auth_employee_id"("target_org" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."auth_employee_id"("target_org" "text") IS 'Returns the current auth.uid()''s hr_employee.id within the supplied org_id. SECURITY DEFINER + STABLE so it can be called inline from views without re-evaluating per row and without tripping RLS on hr_employee.';



CREATE OR REPLACE FUNCTION "public"."chat_query"("q" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $_$
DECLARE
  result jsonb;
  q_low  text := lower(q);
  q_trim text := regexp_replace(q, ';\s*$', '');
BEGIN
  IF q_low !~ '^\s*(select|with)\s' THEN
    RAISE EXCEPTION 'Only SELECT/WITH queries are allowed';
  END IF;
  IF q_low ~ '\y(insert|update|delete|drop|alter|create|truncate|grant|revoke|comment|copy|vacuum|analyze|reindex|cluster|listen|notify|do|call|set|reset|begin|commit|rollback|savepoint|lock)\y' THEN
    RAISE EXCEPTION 'Write/DDL keywords are not permitted';
  END IF;
  IF q_low ~ '\y(hr_|app_hr_)' THEN
    RAISE EXCEPTION 'Restricted tables (hr_*) are not accessible';
  END IF;
  IF regexp_replace(q_trim, ';\s*$', '') ~ ';\s*\S' THEN
    RAISE EXCEPTION 'Multiple statements are not allowed';
  END IF;

  PERFORM set_config('statement_timeout', '20000', true);
  PERFORM set_config('transaction_read_only', 'on', true);

  EXECUTE format('SELECT COALESCE(jsonb_agg(row_to_json(t)), ''[]''::jsonb) FROM (%s) t', q_trim) INTO result;
  RETURN result;
END;
$_$;


ALTER FUNCTION "public"."chat_query"("q" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."chat_schema"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(jsonb_agg(t ORDER BY t->>'table'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'table', c.relname,
      'kind', CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'view' ELSE 'table' END,
      'columns', (
        SELECT jsonb_agg(jsonb_build_object('name', a.attname, 'type', format_type(a.atttypid, a.atttypmod)) ORDER BY a.attnum)
        FROM pg_attribute a
        WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      )
    ) AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r','v','m')
      AND c.relname NOT LIKE 'hr\_%'
      AND c.relname NOT LIKE 'app\_hr\_%'
  ) sub;
$$;


ALTER FUNCTION "public"."chat_schema"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_org_ids"() RETURNS SETOF "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT org_id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND is_deleted = false;
$$;


ALTER FUNCTION "public"."get_user_org_ids"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_auth_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Gate: only link verified email addresses
  IF NEW.email_confirmed_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Link every hr_employee row whose company_email matches this auth user
  -- and is not already linked. Covers multi-org employees in one statement.
  UPDATE public.hr_employee
  SET user_id = NEW.id
  WHERE company_email = NEW.email
    AND user_id IS NULL;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_auth_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pack_session_cases_guard_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.org_id IS DISTINCT FROM OLD.org_id THEN
        RAISE EXCEPTION 'pack_session_cases.org_id is immutable';
    END IF;
    IF NEW.farm_id IS DISTINCT FROM OLD.farm_id THEN
        RAISE EXCEPTION 'pack_session_cases.farm_id is immutable';
    END IF;
    IF NEW.pack_date IS DISTINCT FROM OLD.pack_date THEN
        RAISE EXCEPTION 'pack_session_cases.pack_date is immutable';
    END IF;
    IF NEW.pack_end_hour IS DISTINCT FROM OLD.pack_end_hour THEN
        RAISE EXCEPTION 'pack_session_cases.pack_end_hour is immutable';
    END IF;
    IF NEW.sales_product_id IS DISTINCT FROM OLD.sales_product_id THEN
        RAISE EXCEPTION 'pack_session_cases.sales_product_id is immutable';
    END IF;
    IF NEW.harvest_date IS DISTINCT FROM OLD.harvest_date THEN
        RAISE EXCEPTION 'pack_session_cases.harvest_date is immutable';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."pack_session_cases_guard_immutable"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_session_fails_guard_immutable"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_session_guard_immutable"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_session_labor_hour_guard_immutable"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_session_leftover_guard_immutable"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_session_set_defaults"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_shelf_life_cascade_day"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_shelf_life_check_termination"() OWNER TO "postgres";


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


ALTER FUNCTION "public"."pack_shelf_life_set_day"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."pack_shelf_life_set_day"() IS 'BEFORE INSERT/UPDATE on result/photo: compute shelf_life_day = observation_date − pack_session.pack_date of parent trial. Replaces pack_lot-based version dropped in 20260518121100.';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."edi_crodeon_weather" (
    "org_id" "text" NOT NULL,
    "reading_at" timestamp without time zone NOT NULL,
    "outside_temperature" numeric,
    "outside_humidity" numeric,
    "outside_wet_bulb_temperature" numeric,
    "outside_dew_point_temperature" numeric,
    "outside_wind_average_speed" numeric,
    "outside_wind_average_max_speed" numeric,
    "outside_wind_direction" "text",
    "outside_rain" numeric,
    "inside_par" numeric,
    "inside_temperature" numeric,
    "inside_humidity" numeric,
    "power_supply" "text",
    "atmospheric_pressure" numeric
);


ALTER TABLE "public"."edi_crodeon_weather" OWNER TO "postgres";


COMMENT ON TABLE "public"."edi_crodeon_weather" IS 'Per-minute weather readings pulled from the Crodeon greenhouse station via /reporters/{master_id}/measurements. (org_id, reading_at) is the natural PK; reading_at is HST wall-clock. No audit columns -- we aren''t the source of truth, rows come from the every-10-min sync and are never user-edited.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."reading_at" IS 'Wall-clock HST timestamp at which the station emitted this reading. Stored as plain TIMESTAMP -- no timezone math needed in queries.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_temperature" IS 'Ambient temperature in degrees Fahrenheit.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_humidity" IS 'Ambient relative humidity in percent.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_wet_bulb_temperature" IS 'Wet-bulb temperature in degrees Fahrenheit.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_dew_point_temperature" IS 'Dew-point temperature in degrees Fahrenheit.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_wind_average_speed" IS 'Average wind speed for the sample interval, mph.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_wind_average_max_speed" IS 'Peak gust within the sample interval, mph.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_wind_direction" IS 'Compass direction string (e.g. N, NNE, NE, ESE).';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."outside_rain" IS 'Rainfall accumulation for the sample interval, inches.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."inside_par" IS 'Photosynthetically Active Radiation inside the greenhouse, μmol/m²/s.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."inside_temperature" IS 'Greenhouse interior temperature, degrees Fahrenheit.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."inside_humidity" IS 'Greenhouse interior relative humidity, percent.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."power_supply" IS 'Station mains/battery state — typically "On" when grid power is up.';



COMMENT ON COLUMN "public"."edi_crodeon_weather"."atmospheric_pressure" IS 'Station-level atmospheric pressure, millibar.';



CREATE OR REPLACE VIEW "public"."edi_crodeon_weather_dli" WITH ("security_invoker"='true') AS
 SELECT "org_id",
    "reading_at",
    "outside_temperature",
    "outside_humidity",
    "outside_wet_bulb_temperature",
    "outside_dew_point_temperature",
    "outside_wind_average_speed",
    "outside_wind_average_max_speed",
    "outside_wind_direction",
    "outside_rain",
    "inside_par",
    "inside_temperature",
    "inside_humidity",
    "power_supply",
    "atmospheric_pressure",
    COALESCE((("inside_par" * EXTRACT(epoch FROM ("lead"("reading_at") OVER (PARTITION BY "org_id" ORDER BY "reading_at") - "reading_at"))) / 1000000.0), (0)::numeric) AS "dli"
   FROM "public"."edi_crodeon_weather" "w";


ALTER VIEW "public"."edi_crodeon_weather_dli" OWNER TO "postgres";


COMMENT ON VIEW "public"."edi_crodeon_weather_dli" IS 'edi_crodeon_weather with a derived dli column: inside_par * seconds_to_next_reading / 1,000,000. Sum dli over a 24h window for daily DLI. The last row in each org_id partition has dli=0 (no next reading).';



CREATE TABLE IF NOT EXISTS "public"."edi_qb_expense" (
    "org_id" "text" NOT NULL,
    "id" "text" NOT NULL,
    "payee_name" "text",
    "account_name" "text",
    "is_credit" boolean DEFAULT false NOT NULL,
    "transaction_date" "date",
    "synced_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sync_token" "text"
);


ALTER TABLE "public"."edi_qb_expense" OWNER TO "postgres";


COMMENT ON TABLE "public"."edi_qb_expense" IS 'Local mirror of QuickBooks Online Purchase headers (expenses paid by cash / check / credit card). (org_id, id) is the source-of-truth PK; id holds the Intuit Purchase.Id directly.';



COMMENT ON COLUMN "public"."edi_qb_expense"."id" IS 'Intuit Purchase.Id (string). Unique within a QB company; primary key with org_id.';



COMMENT ON COLUMN "public"."edi_qb_expense"."account_name" IS 'Bank / credit-card account the purchase was paid FROM (Purchase.AccountRef.name). Distinct from edi_qb_expense_line.account_name which is the line-level categorization account.';



COMMENT ON COLUMN "public"."edi_qb_expense"."is_credit" IS 'Purchase.Credit. True = refund / vendor credit reducing AP balance. False = normal outflow.';



COMMENT ON COLUMN "public"."edi_qb_expense"."synced_at" IS 'Wall-clock time of the last successful upsert from the QB API.';



COMMENT ON COLUMN "public"."edi_qb_expense"."sync_token" IS 'Intuit SyncToken -- optimistic-concurrency version. When pushing updates back to QB the request must include the current SyncToken; QB returns 400 "Stale Object Error" otherwise. Increments on every successful update; refreshed on every pull.';



CREATE TABLE IF NOT EXISTS "public"."edi_qb_expense_line" (
    "org_id" "text" NOT NULL,
    "expense_id" "text" NOT NULL,
    "line_num" integer NOT NULL,
    "account_name" "text",
    "class_name" "text",
    "description" "text",
    "amount" numeric(14,2)
);


ALTER TABLE "public"."edi_qb_expense_line" OWNER TO "postgres";


COMMENT ON TABLE "public"."edi_qb_expense_line" IS 'Local mirror of QuickBooks Online Purchase line items. One row per (org_id, expense_id, line_num). Captures both AccountBasedExpenseLineDetail and ItemBasedExpenseLineDetail line types -- whichever provides the AccountRef gets surfaced as account_name.';



COMMENT ON COLUMN "public"."edi_qb_expense_line"."line_num" IS 'Line.LineNum from Intuit (1-based). Preserve to maintain ordering.';



COMMENT ON COLUMN "public"."edi_qb_expense_line"."account_name" IS 'Line-level categorization account (e.g. ''Repairs & Maintenance''). Distinct from edi_qb_expense.account_name which is the funding account.';



COMMENT ON COLUMN "public"."edi_qb_expense_line"."class_name" IS 'QB Class tag on the line. Typically used for farm-level (Cuke / Lettuce) cost allocation.';



CREATE OR REPLACE VIEW "public"."edi_qb_expense_summary" WITH ("security_invoker"='true') AS
 SELECT "h"."org_id",
    "h"."payee_name",
    "h"."account_name" AS "funding_account",
    "h"."is_credit",
    "h"."transaction_date",
    "l"."line_num",
    "l"."account_name" AS "expense_account",
    "l"."class_name",
    "l"."description",
    "l"."amount"
   FROM ("public"."edi_qb_expense" "h"
     LEFT JOIN "public"."edi_qb_expense_line" "l" ON ((("l"."org_id" = "h"."org_id") AND ("l"."expense_id" = "h"."id"))));


ALTER VIEW "public"."edi_qb_expense_summary" OWNER TO "postgres";


COMMENT ON VIEW "public"."edi_qb_expense_summary" IS 'One row per (expense line) for spreadsheet-style review. Header fields (payee_name, funding_account, transaction_date, is_credit) repeat across each expense''s line rows. funding_account = bank/CC paid from; expense_account = the categorization account on the line. Mirrors the legacy G-Accon export shape.';



CREATE TABLE IF NOT EXISTS "public"."edi_qb_invoice" (
    "org_id" "text" NOT NULL,
    "id" "text" NOT NULL,
    "invoice_number" "text",
    "customer_id" "text",
    "customer_name" "text",
    "invoice_date" "date",
    "total_amount" numeric(14,2),
    "synced_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sync_token" "text"
);


ALTER TABLE "public"."edi_qb_invoice" OWNER TO "postgres";


COMMENT ON TABLE "public"."edi_qb_invoice" IS 'Local mirror of QuickBooks Online Invoice headers. (org_id, id) is the source-of-truth PK; id holds the Intuit Invoice.Id directly (no surrogate UUID).';



COMMENT ON COLUMN "public"."edi_qb_invoice"."id" IS 'Intuit Invoice.Id (string). Unique within a QB company; primary key with org_id.';



COMMENT ON COLUMN "public"."edi_qb_invoice"."invoice_number" IS 'Human invoice number shown in QB UI (Invoice.DocNumber). Not unique on its own; can be missing on auto-numbered drafts.';



COMMENT ON COLUMN "public"."edi_qb_invoice"."customer_name" IS 'CustomerRef.name copied here for fast filtering; canonical name lives on the QB Customer entity.';



COMMENT ON COLUMN "public"."edi_qb_invoice"."synced_at" IS 'Wall-clock time of the last successful upsert from the QB API.';



COMMENT ON COLUMN "public"."edi_qb_invoice"."sync_token" IS 'Intuit SyncToken -- optimistic-concurrency version. When pushing updates back to QB the request must include the current SyncToken; QB returns 400 "Stale Object Error" otherwise. Increments on every successful update; refreshed on every pull.';



CREATE TABLE IF NOT EXISTS "public"."edi_qb_invoice_line" (
    "org_id" "text" NOT NULL,
    "invoice_id" "text" NOT NULL,
    "line_num" integer NOT NULL,
    "item_name" "text",
    "description" "text",
    "cases" numeric(14,4),
    "amount" numeric(14,2),
    "service_date" "date"
);


ALTER TABLE "public"."edi_qb_invoice_line" OWNER TO "postgres";


COMMENT ON TABLE "public"."edi_qb_invoice_line" IS 'Local mirror of QuickBooks Online Invoice line items. One row per (org_id, invoice_id, line_num). Sales-item lines only -- subtotal / tax / discount lines are filtered out at sync time.';



COMMENT ON COLUMN "public"."edi_qb_invoice_line"."line_num" IS 'Line.LineNum from Intuit (1-based). Preserve to maintain print order.';



COMMENT ON COLUMN "public"."edi_qb_invoice_line"."service_date" IS 'When the goods/service on this line were delivered (Line[].SalesItemLineDetail.ServiceDate). Distinct from the invoice_date on the header.';



CREATE TABLE IF NOT EXISTS "public"."sales_customer" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_customer_group_id" "text",
    "sales_fob_id" "text",
    "qb_account" "text",
    "email" "text",
    "cc_emails" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "billing_address" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_customer" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_customer" IS 'Stores an organization''s customers with their group classification, preferred delivery method, billing address, and a link to external accounting software via qb_account. Additional contact emails are stored in cc_emails.';



COMMENT ON COLUMN "public"."sales_customer"."sales_customer_group_id" IS 'Cascades to sales_po.sales_customer_group_id when an order is created for this customer';



COMMENT ON COLUMN "public"."sales_customer"."sales_fob_id" IS 'Default FOB delivery point; cascades to sales_po.sales_fob_id when an order is created for this customer';



COMMENT ON COLUMN "public"."sales_customer"."qb_account" IS 'QuickBooks account identifier for accounting integration';



CREATE TABLE IF NOT EXISTS "public"."sales_product" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "grow_grade_id" "text",
    "name" "text" NOT NULL,
    "description" "text",
    "invnt_item_id" "text",
    "item_uom" "text",
    "pack_uom" "text",
    "item_per_pack" numeric,
    "pack_per_case" numeric,
    "maximum_case_per_pallet" numeric,
    "pack_net_weight" numeric,
    "case_net_weight" numeric,
    "pallet_net_weight" numeric,
    "dimension_uom" "text",
    "case_length" numeric,
    "case_width" numeric,
    "case_height" numeric,
    "manufacturer_storage_method" "text",
    "minimum_storage_temperature" numeric,
    "maximum_storage_temperature" numeric,
    "shelf_life_days" integer,
    "pallet_ti" numeric,
    "pallet_hi" numeric,
    "shipping_requirements" "text",
    "is_catch_weight" boolean DEFAULT false NOT NULL,
    "is_hazardous" boolean DEFAULT false NOT NULL,
    "is_fsma_traceable" boolean DEFAULT false NOT NULL,
    "gtin" "text",
    "upc" "text",
    "photos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_product" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_product" IS 'The sellable products from each farm. Combines a grade with a full packaging hierarchy (item → pack → case → pallet). The sale unit is always a case; the shipping unit is always a pallet.';



COMMENT ON COLUMN "public"."sales_product"."invnt_item_id" IS 'Filtered to packaging items in inventory';



COMMENT ON COLUMN "public"."sales_product"."item_uom" IS 'Smallest countable unit of the product (e.g. count, lb, oz)';



COMMENT ON COLUMN "public"."sales_product"."pack_uom" IS 'Intermediate packaging unit (e.g. bag, tray)';



COMMENT ON COLUMN "public"."sales_product"."item_per_pack" IS 'Number of items per pack unit';



COMMENT ON COLUMN "public"."sales_product"."pack_per_case" IS 'Number of pack units per case';



COMMENT ON COLUMN "public"."sales_product"."maximum_case_per_pallet" IS 'Maximum number of cases that fit on a pallet';



COMMENT ON COLUMN "public"."sales_product"."dimension_uom" IS 'Unit for all case dimension fields (e.g. in, cm)';



COMMENT ON COLUMN "public"."sales_product"."shelf_life_days" IS 'Expected shelf life in days from pack date; used to auto-calculate best_by_date on pack_lot_item';



COMMENT ON COLUMN "public"."sales_product"."pallet_ti" IS 'Pallet tier — number of cases per layer on pallet';



COMMENT ON COLUMN "public"."sales_product"."pallet_hi" IS 'Pallet high — number of layers stacked on pallet';



COMMENT ON COLUMN "public"."sales_product"."is_catch_weight" IS 'Whether sold by actual weight rather than fixed unit count';



COMMENT ON COLUMN "public"."sales_product"."is_fsma_traceable" IS 'Whether this product requires FSMA traceability documentation';



COMMENT ON COLUMN "public"."sales_product"."gtin" IS 'Global Trade Item Number for supply chain identification';



COMMENT ON COLUMN "public"."sales_product"."upc" IS 'Universal Product Code for retail scanning';



CREATE OR REPLACE VIEW "public"."edi_qb_invoice_summary" WITH ("security_invoker"='true') AS
 SELECT "h"."org_id",
    "h"."customer_name",
    "sc"."sales_customer_group_id" AS "customer_group",
    "h"."invoice_number",
    "h"."invoice_date",
    "l"."line_num",
    "l"."service_date",
    "l"."item_name",
    "sp"."farm_id" AS "farm",
    "l"."cases",
    "l"."amount",
    ("l"."cases" * "sp"."case_net_weight") AS "pounds"
   FROM ((("public"."edi_qb_invoice" "h"
     LEFT JOIN "public"."edi_qb_invoice_line" "l" ON ((("l"."org_id" = "h"."org_id") AND ("l"."invoice_id" = "h"."id"))))
     LEFT JOIN "public"."sales_customer" "sc" ON ((("sc"."org_id" = "h"."org_id") AND ("sc"."id" = "h"."customer_name"))))
     LEFT JOIN "public"."sales_product" "sp" ON ((("sp"."org_id" = "h"."org_id") AND ("sp"."id" = "l"."item_name"))));


ALTER VIEW "public"."edi_qb_invoice_summary" OWNER TO "postgres";


COMMENT ON VIEW "public"."edi_qb_invoice_summary" IS 'One row per (invoice line) for spreadsheet-style review. Joins QB invoice header + line to sales_customer (for customer_group) and sales_product (for farm + case_net_weight); pounds = cases * case_net_weight. LEFT joins so unmatched master-data rows still appear with NULLs.';



CREATE TABLE IF NOT EXISTS "public"."fin_expense" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "txn_date" "date" NOT NULL,
    "payee_name" "text",
    "description" "text",
    "account_name" "text",
    "account_ref" "text",
    "class_name" "text",
    "amount" numeric,
    "is_credit" boolean DEFAULT false NOT NULL,
    "effective_amount" numeric,
    "macro_category" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."fin_expense" OWNER TO "postgres";


COMMENT ON TABLE "public"."fin_expense" IS 'Financial expense transactions sourced from QuickBooks (nightly-synced from the invoices/expense spreadsheet today, moving to direct QB API later). One row per line item on a QB expense transaction.';



COMMENT ON COLUMN "public"."fin_expense"."farm_id" IS 'Nullable — the expense spreadsheet does not currently carry a Farm column. Populated later when expenses are farm-tagged (likely derivable from class_name)';



COMMENT ON COLUMN "public"."fin_expense"."txn_date" IS 'Transaction date from QB (Txn Date column in the expense sheet)';



COMMENT ON COLUMN "public"."fin_expense"."payee_name" IS 'Free-text payee; Payee Ref.name from QB. Nullable since some expenses are line items without a distinct payee';



COMMENT ON COLUMN "public"."fin_expense"."description" IS 'Line-item description from QB (Line Item.description)';



COMMENT ON COLUMN "public"."fin_expense"."account_name" IS 'QB chart-of-accounts bucket (Line Item.account Name), e.g. "6. Office:Misc" or "3. R&M:Facilities"';



COMMENT ON COLUMN "public"."fin_expense"."account_ref" IS 'Originating account / card identifier (Account Ref.name), e.g. "JPM,0388" or "JPM CC:JPM5660/6836,LF"';



COMMENT ON COLUMN "public"."fin_expense"."class_name" IS 'QB class (Line Item.class Name), cost-center style tag. Often null';



COMMENT ON COLUMN "public"."fin_expense"."amount" IS 'Raw line-item amount from QB (Line Item.amount), always positive';



COMMENT ON COLUMN "public"."fin_expense"."is_credit" IS 'True when the QB transaction is a credit/refund; from the "Creadit" (sic) column in the sheet';



COMMENT ON COLUMN "public"."fin_expense"."effective_amount" IS 'Signed amount used by dashboards: equals amount when is_credit=false, equals -amount when is_credit=true. From the second "Amt" column in the sheet (pre-computed there)';



COMMENT ON COLUMN "public"."fin_expense"."macro_category" IS 'Top-level QB account category (Macro), e.g. "3. R&M", "6. Office", derived from account_name';



CREATE OR REPLACE VIEW "public"."fin_expense_v" WITH ("security_invoker"='true') AS
 SELECT "id",
    "org_id",
    "farm_id",
    "txn_date",
    "payee_name",
    "description",
    "account_name",
    "account_ref",
    "class_name",
    "amount",
    "is_credit",
    "effective_amount",
    "macro_category",
    "notes",
    "created_at",
    "created_by",
    "updated_at",
    "updated_by",
    "is_deleted",
    (EXTRACT(year FROM "txn_date"))::integer AS "year",
    (EXTRACT(month FROM "txn_date"))::integer AS "month"
   FROM "public"."fin_expense" "e"
  WHERE ("is_deleted" = false);


ALTER VIEW "public"."fin_expense_v" OWNER TO "postgres";


COMMENT ON VIEW "public"."fin_expense_v" IS 'fin_expense with derived year/month columns and soft-delete filter applied. Dashboards read from this view';



CREATE TABLE IF NOT EXISTS "public"."fsafe_lab" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."fsafe_lab" OWNER TO "postgres";


COMMENT ON TABLE "public"."fsafe_lab" IS 'Catalog of laboratories used for food safety test submissions (e.g. test-and-hold pathogen testing).';



CREATE TABLE IF NOT EXISTS "public"."fsafe_lab_test" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "test_methods" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "test_description" "text",
    "result_type" "text" NOT NULL,
    "enum_options" "jsonb",
    "enum_pass_options" "jsonb",
    "minimum_value" numeric,
    "maximum_value" numeric,
    "atp_site_count" integer,
    "required_retests" integer DEFAULT 0 NOT NULL,
    "required_vector_tests" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "fsafe_lab_test_result_type_check" CHECK (("result_type" = ANY (ARRAY['Enum'::"text", 'Numeric'::"text"])))
);


ALTER TABLE "public"."fsafe_lab_test" OWNER TO "postgres";


COMMENT ON TABLE "public"."fsafe_lab_test" IS 'Catalog of EMP test definitions and their result configuration. Defines how results are evaluated and how many retests or vector tests are required on a fail.';



COMMENT ON COLUMN "public"."fsafe_lab_test"."test_methods" IS 'JSON array of available testing methods; fsafe_result.test_method is selected from this list';



COMMENT ON COLUMN "public"."fsafe_lab_test"."result_type" IS 'enum, numeric';



COMMENT ON COLUMN "public"."fsafe_lab_test"."enum_options" IS 'JSON array of allowed result values when result_type is enum (e.g. ["Positive", "Negative"])';



COMMENT ON COLUMN "public"."fsafe_lab_test"."enum_pass_options" IS 'Subset of enum_options that indicate a passing result; used to auto-set fsafe_result.result_pass';



COMMENT ON COLUMN "public"."fsafe_lab_test"."minimum_value" IS 'Numeric result at or above this value passes; used to auto-set fsafe_result.result_pass when result_type is numeric';



COMMENT ON COLUMN "public"."fsafe_lab_test"."maximum_value" IS 'Numeric result at or below this value passes; used to auto-set fsafe_result.result_pass when result_type is numeric';



COMMENT ON COLUMN "public"."fsafe_lab_test"."atp_site_count" IS 'Number of zone_1 sites to randomly select for ATP testing; null means this test is not ATP';



COMMENT ON COLUMN "public"."fsafe_lab_test"."required_retests" IS 'Number of retest results to auto-create in fsafe_result when a result fails';



COMMENT ON COLUMN "public"."fsafe_lab_test"."required_vector_tests" IS 'Number of vector test results to auto-create in fsafe_result when a result fails';



CREATE TABLE IF NOT EXISTS "public"."fsafe_pest_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "site_id" "text" NOT NULL,
    "pest_type" "text",
    "photo_url" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "fsafe_pest_result_pest_type_check" CHECK (("pest_type" = ANY (ARRAY['Mouse'::"text", 'Rat'::"text"])))
);


ALTER TABLE "public"."fsafe_pest_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."fsafe_pest_result" IS 'Per-station pest trap inspection result. One row per trap station per inspection event. The ops_task_tracker acts as the inspection header with date, farm, and verification.';



COMMENT ON COLUMN "public"."fsafe_pest_result"."site_id" IS 'The specific trap station (org_site where category = pest_trap); distinct from ops_task_tracker.site_id which is the parent building';



COMMENT ON COLUMN "public"."fsafe_pest_result"."pest_type" IS 'mouse, rat; null means no activity at this station';



CREATE TABLE IF NOT EXISTS "public"."fsafe_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text",
    "fsafe_test_hold_id" "uuid",
    "fsafe_lab_id" "text",
    "fsafe_lab_test_id" "text" NOT NULL,
    "test_method" "text",
    "initial_retest_vector" "text",
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "result_enum" "text",
    "result_numeric" numeric,
    "result_pass" boolean,
    "fail_code" "text",
    "fsafe_result_id_original" "uuid",
    "notes" "text",
    "sampled_at" timestamp with time zone,
    "sampled_by" "text",
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "verified_at" timestamp with time zone,
    "verified_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "fsafe_result_initial_retest_vector_check" CHECK (("initial_retest_vector" = ANY (ARRAY['Initial'::"text", 'Retest'::"text", 'Vector'::"text"]))),
    CONSTRAINT "fsafe_result_status_check" CHECK (("status" = ANY (ARRAY['Pending'::"text", 'In Progress'::"text", 'Completed'::"text"])))
);


ALTER TABLE "public"."fsafe_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."fsafe_result" IS 'Unified food safety test results table. Result type is derived from existing fields: EMP (site_id set, fsafe_test_hold_id null, zone != water), Test-and-Hold (fsafe_test_hold_id set), Water (site_id set, zone = water). Retests and vector tests link back to the original via fsafe_result_id_original.';



COMMENT ON COLUMN "public"."fsafe_result"."site_id" IS 'Food safety site (org_site where category = food_safety or zone = water); set for EMP and water results, null for test-and-hold';



COMMENT ON COLUMN "public"."fsafe_result"."fsafe_lab_id" IS 'Pre-filled from fsafe_test_hold.fsafe_lab_id for test-and-hold results; editable';



COMMENT ON COLUMN "public"."fsafe_result"."test_method" IS 'Pre-filled from fsafe_lab_test.test_methods; editable';



COMMENT ON COLUMN "public"."fsafe_result"."initial_retest_vector" IS 'initial, retest, vector';



COMMENT ON COLUMN "public"."fsafe_result"."status" IS 'pending, in_progress, completed';



COMMENT ON COLUMN "public"."fsafe_result"."result_pass" IS 'Auto-set by evaluating result against fsafe_lab_test pass/fail criteria';



COMMENT ON COLUMN "public"."fsafe_result"."fsafe_result_id_original" IS 'Sourced from the original fsafe_result when initial_retest_vector is retest or vector';



CREATE TABLE IF NOT EXISTS "public"."fsafe_test_hold" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "sales_customer_group_id" "text",
    "sales_customer_id" "text",
    "fsafe_lab_id" "text",
    "lab_test_id" "text",
    "notes" "text",
    "delivered_to_lab_on" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_date" "date" NOT NULL,
    "harvest_date" "date"
);


ALTER TABLE "public"."fsafe_test_hold" OWNER TO "postgres";


COMMENT ON TABLE "public"."fsafe_test_hold" IS 'Test-and-hold header. One record per pack lot per lab. If the same lot is sent to a different lab, a separate entry is created. Tracks sample collection, lab submission, and test timeline.';



COMMENT ON COLUMN "public"."fsafe_test_hold"."sales_customer_group_id" IS 'Pre-filled from sales_customer.sales_customer_group_id; editable';



COMMENT ON COLUMN "public"."fsafe_test_hold"."sales_customer_id" IS 'Pre-filled from the linked sales_po customer; editable';



COMMENT ON COLUMN "public"."fsafe_test_hold"."pack_date" IS 'Pack date of the held lot. Recall join key with harvest_date.';



COMMENT ON COLUMN "public"."fsafe_test_hold"."harvest_date" IS 'Harvest date of the held lot. Nullable for historical rows whose source pack_lot had no harvest_date.';



CREATE TABLE IF NOT EXISTS "public"."fsafe_test_hold_po" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "fsafe_test_hold_id" "uuid" NOT NULL,
    "sales_po_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."fsafe_test_hold_po" OWNER TO "postgres";


COMMENT ON TABLE "public"."fsafe_test_hold_po" IS 'Links a test-and-hold record to one or more sales purchase orders.';



CREATE TABLE IF NOT EXISTS "public"."grow_chemistry_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "site_id" "text" NOT NULL,
    "sample_date" "date" NOT NULL,
    "nutrient" "text" NOT NULL,
    "result" numeric NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_chemistry_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_chemistry_result" IS 'External-lab chemistry readings for ponds and water sources. One row per (sample_date, site_id, nutrient). Loaded nightly from the lab spreadsheet.';



COMMENT ON COLUMN "public"."grow_chemistry_result"."site_id" IS 'Sample location label as written by the lab (e.g. P1..P7 for lettuce ponds, Water for the incoming water source). Free text; not FK-bound to org_site today.';



COMMENT ON COLUMN "public"."grow_chemistry_result"."sample_date" IS 'Date the lab drew the sample (not the date the result was returned).';



COMMENT ON COLUMN "public"."grow_chemistry_result"."nutrient" IS 'Nutrient or parameter code from the lab (e.g. Ca, Mg, NO3, EC, pH). Free text; not FK-bound.';



COMMENT ON COLUMN "public"."grow_chemistry_result"."result" IS 'Numeric reading. Units depend on nutrient (ppm for most ions, dS/m for EC, unitless for pH).';



CREATE TABLE IF NOT EXISTS "public"."grow_cuke_gh_row_planting" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "org_site_cuke_gh_row_id" "uuid" NOT NULL,
    "scenario" "text" NOT NULL,
    "grow_variety_id" "text" NOT NULL,
    "grow_variety_id_2" "text",
    "plants_per_bag" integer NOT NULL,
    "num_bags" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "grow_cuke_gh_row_planting_plants_per_bag_check" CHECK (("plants_per_bag" = ANY (ARRAY[4, 5]))),
    CONSTRAINT "grow_cuke_gh_row_planting_scenario_check" CHECK (("scenario" = ANY (ARRAY['Current'::"text", 'Planned'::"text"])))
);


ALTER TABLE "public"."grow_cuke_gh_row_planting" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_cuke_gh_row_planting" IS 'Cuke planting assignment per physical GH row. Two scenarios per row: current (live layout the transplant crew follows) and planned (proposed future layout). Rows are always planted to full capacity; split rows are always 50/50.';



COMMENT ON COLUMN "public"."grow_cuke_gh_row_planting"."org_site_cuke_gh_row_id" IS 'The physical row being planted. References org_site_cuke_gh_row';



COMMENT ON COLUMN "public"."grow_cuke_gh_row_planting"."scenario" IS 'current = live layout being followed by the transplant crew. planned = proposed future layout under review. Exactly one row per (org_site_cuke_gh_row_id, scenario)';



COMMENT ON COLUMN "public"."grow_cuke_gh_row_planting"."grow_variety_id" IS 'Primary variety planted in this row. If grow_variety_id_2 is null, this variety fills all num_bags. If split, it occupies num_bags / 2.';



COMMENT ON COLUMN "public"."grow_cuke_gh_row_planting"."grow_variety_id_2" IS 'Second variety when the row is split 50/50. Null for non-split rows';



COMMENT ON COLUMN "public"."grow_cuke_gh_row_planting"."plants_per_bag" IS 'Plants per bag: 4 or 5. Applies uniformly across the row, including both varieties in a split';



COMMENT ON COLUMN "public"."grow_cuke_gh_row_planting"."num_bags" IS 'Bags per row for this scenario. Total plants in this row under this scenario = num_bags * plants_per_bag';



CREATE TABLE IF NOT EXISTS "public"."grow_cuke_seed_batch" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text",
    "ops_task_tracker_id" "uuid",
    "grow_trial_type_id" "text",
    "invnt_item_id" "text",
    "invnt_lot_id" "text",
    "seeding_date" "date" NOT NULL,
    "transplant_date" "date" NOT NULL,
    "next_bag_change_date" "date",
    "rows_4_per_bag" integer DEFAULT 0 NOT NULL,
    "rows_5_per_bag" integer DEFAULT 0 NOT NULL,
    "seeds" integer NOT NULL,
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "grow_cuke_seed_batch_status_check" CHECK (("status" = ANY (ARRAY['Planned'::"text", 'Seeded'::"text", 'Transplanted'::"text", 'Harvesting'::"text", 'Harvested'::"text"])))
);


ALTER TABLE "public"."grow_cuke_seed_batch" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_cuke_seed_batch" IS 'Cuke seeding cycle record. One row per variety per greenhouse per seeding event. Holds historical and forward-planned cycles. Snapshot fields (rows_4_per_bag, rows_5_per_bag, seeds) are frozen at seeding time from the plant map and not recomputed.';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."site_id" IS 'Greenhouse being seeded; filtered to org_site where subcategory = greenhouse';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."grow_trial_type_id" IS 'Null if not a trial; set when testing a new lot, variety, or seed source';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."invnt_item_id" IS 'Specific seed cultivar used for this cycle (e.g. delta_star_minis_rz). Variety (k/j/e) is derivable via invnt_item.grow_variety_id';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."invnt_lot_id" IS 'Lot number for the cultivar. References invnt_lot filtered by invnt_item_id';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."seeding_date" IS 'Actual planting date. For future cycles this is the planned date. Dashboard derives ISO week from this';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."transplant_date" IS 'Planned or actual date transplant crew moves seedlings into the greenhouse';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."next_bag_change_date" IS 'Scheduled bag-swap date for this cycle. Null if not yet scheduled';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."rows_4_per_bag" IS 'Snapshot: number of physical GH rows at 4 plants per bag for this variety this cycle. Populated from the plant map at seeding time. -1 indicates historical data imported before the snapshot was tracked';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."rows_5_per_bag" IS 'Snapshot: number of physical GH rows at 5 plants per bag for this variety this cycle. Populated from the plant map at seeding time. -1 indicates historical data imported before the snapshot was tracked';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."seeds" IS 'Total seeds sown for this variety this cycle. Calculated at seeding time';



COMMENT ON COLUMN "public"."grow_cuke_seed_batch"."status" IS 'Auto-set: planned (seeding_date > today), seeded (seeding_date <= today < transplant_date), transplanted (transplant_date <= today < estimated_harvest_date), harvesting, harvested (manually set when complete)';



CREATE TABLE IF NOT EXISTS "public"."grow_harvest_weight" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text",
    "ops_task_tracker_id" "uuid",
    "grow_lettuce_seed_batch_id" "uuid",
    "grow_cuke_seed_batch_id" "uuid",
    "grow_grade_id" "text",
    "harvest_date" "date" NOT NULL,
    "grow_harvest_container_id" "text" NOT NULL,
    "number_of_containers" integer NOT NULL,
    "weight_uom" "text" NOT NULL,
    "gross_weight" numeric NOT NULL,
    "net_weight" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_grow_harvest_weight_batch_exactly_one" CHECK (((("grow_lettuce_seed_batch_id" IS NOT NULL) AND ("grow_cuke_seed_batch_id" IS NULL)) OR (("grow_lettuce_seed_batch_id" IS NULL) AND ("grow_cuke_seed_batch_id" IS NOT NULL))))
);


ALTER TABLE "public"."grow_harvest_weight" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_harvest_weight" IS 'Individual weigh-in for a harvest. One row per container type weighed. Links directly to the seeding batch for traceability. Tare is calculated on the fly from grow_harvest_container.tare_weight × number_of_containers.';



COMMENT ON COLUMN "public"."grow_harvest_weight"."site_id" IS 'Growing site being harvested; pre-filled from the seed batch.site_id';



COMMENT ON COLUMN "public"."grow_harvest_weight"."grow_lettuce_seed_batch_id" IS 'The lettuce seeding batch being harvested. Populated when farm_id = Lettuce; null for Cuke';



COMMENT ON COLUMN "public"."grow_harvest_weight"."grow_cuke_seed_batch_id" IS 'The cuke seeding batch being harvested. Populated when farm_id = Cuke; null for Lettuce';



COMMENT ON COLUMN "public"."grow_harvest_weight"."grow_grade_id" IS 'Grade assigned to this harvest (e.g. Grade A, Grade B)';



COMMENT ON COLUMN "public"."grow_harvest_weight"."grow_harvest_container_id" IS 'Container type used for this weigh-in; drives tare weight calculation';



COMMENT ON COLUMN "public"."grow_harvest_weight"."weight_uom" IS 'Pre-filled from grow_harvest_container.weight_uom; editable';



COMMENT ON COLUMN "public"."grow_harvest_weight"."gross_weight" IS 'Total weight on the scale including containers';



COMMENT ON COLUMN "public"."grow_harvest_weight"."net_weight" IS 'Auto-calculated: gross_weight minus (grow_harvest_container.tare_weight × number_of_containers)';



CREATE TABLE IF NOT EXISTS "public"."invnt_item" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "invnt_category_id" "text",
    "invnt_subcategory_id" "text",
    "qb_account" "text",
    "description" "text",
    "burn_uom" "text",
    "onhand_uom" "text",
    "order_uom" "text",
    "burn_per_onhand" numeric DEFAULT 0 NOT NULL,
    "burn_per_order" numeric DEFAULT 0 NOT NULL,
    "is_palletized" boolean DEFAULT false NOT NULL,
    "order_per_pallet" numeric DEFAULT 0 NOT NULL,
    "pallet_per_truckload" numeric DEFAULT 0 NOT NULL,
    "is_frequently_used" boolean DEFAULT false NOT NULL,
    "burn_per_week" numeric DEFAULT 0 NOT NULL,
    "cushion_weeks" numeric DEFAULT 0 NOT NULL,
    "is_auto_reorder" boolean DEFAULT false NOT NULL,
    "reorder_point_in_burn" numeric DEFAULT 0 NOT NULL,
    "reorder_quantity_in_burn" numeric DEFAULT 0 NOT NULL,
    "requires_lot_tracking" boolean DEFAULT false NOT NULL,
    "requires_expiry_date" boolean DEFAULT false NOT NULL,
    "site_id" "text",
    "equipment_id" "text",
    "invnt_vendor_id" "text",
    "manufacturer" "text",
    "grow_variety_id" "text",
    "seed_is_pelleted" boolean,
    "maint_part_type" "text",
    "maint_part_number" "text",
    "photos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."invnt_item" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_item" IS 'The main inventory record. Items belong to an organization and optionally to a specific farm. Classification is handled by the category/subcategory structure. All item details are proper columns grouped by logical sections. Seed-specific fields are prefixed seed_; maintenance part fields are prefixed maint_.';



COMMENT ON COLUMN "public"."invnt_item"."invnt_category_id" IS 'References invnt_category rows where sub_category_name IS NULL';



COMMENT ON COLUMN "public"."invnt_item"."invnt_subcategory_id" IS 'References invnt_category rows where sub_category_name IS NOT NULL';



COMMENT ON COLUMN "public"."invnt_item"."burn_uom" IS 'Smallest consumption unit used for burn rate tracking (e.g. ml, g, seed)';



COMMENT ON COLUMN "public"."invnt_item"."cushion_weeks" IS 'Safety stock buffer in weeks used in next-order-date calculations';



COMMENT ON COLUMN "public"."invnt_item"."reorder_point_in_burn" IS 'Auto-calculated: burn_per_week * cushion_weeks; triggers reorder alert when on-hand falls below this';



COMMENT ON COLUMN "public"."invnt_item"."reorder_quantity_in_burn" IS 'Auto-calculated: burn_per_week * cushion_weeks; default quantity for auto-reorder in burn units';



COMMENT ON COLUMN "public"."invnt_item"."site_id" IS 'Filtered to org_site where category = storage; the storage location for this item';



COMMENT ON COLUMN "public"."invnt_item"."seed_is_pelleted" IS 'Whether seed item is pelleted; null for non-seed items';



COMMENT ON COLUMN "public"."invnt_item"."maint_part_type" IS 'Type classification for parts (e.g. electrical, mechanical, plumbing)';



COMMENT ON COLUMN "public"."invnt_item"."photos" IS 'Reference photos of the item used for visual identification during ordering';



COMMENT ON COLUMN "public"."invnt_item"."is_active" IS 'Whether this item is currently active for ordering and tracking; false means inactive but not deleted';



CREATE OR REPLACE VIEW "public"."grow_cuke_harvest" WITH ("security_invoker"='true') AS
 SELECT "h"."id",
    "h"."harvest_date",
    "h"."site_id",
        CASE "h"."site_id"
            WHEN '01'::"text" THEN 'GH1'::"text"
            WHEN '02'::"text" THEN 'GH2'::"text"
            WHEN '03'::"text" THEN 'GH3'::"text"
            WHEN '04'::"text" THEN 'GH4'::"text"
            WHEN '05'::"text" THEN 'GH5'::"text"
            WHEN '06'::"text" THEN 'GH6'::"text"
            WHEN '07'::"text" THEN 'GH7'::"text"
            WHEN '08'::"text" THEN 'GH8'::"text"
            WHEN 'ko'::"text" THEN 'Kona'::"text"
            WHEN 'hk'::"text" THEN 'HK'::"text"
            WHEN 'hi'::"text" THEN 'Hilo'::"text"
            WHEN 'wa'::"text" THEN 'Waimea'::"text"
            ELSE "upper"("h"."site_id")
        END AS "greenhouse",
    "upper"(COALESCE("i"."grow_variety_id", ''::"text")) AS "variety",
    "h"."grow_grade_id" AS "grade",
    "h"."net_weight" AS "greenhouse_net_weight",
    "h"."gross_weight",
    "h"."number_of_containers",
    "h"."weight_uom",
    "h"."grow_cuke_seed_batch_id",
    "b"."seeding_date",
    ("h"."harvest_date" - "b"."seeding_date") AS "days_since_seed",
    "h"."org_id",
    "h"."farm_id"
   FROM (("public"."grow_harvest_weight" "h"
     LEFT JOIN "public"."grow_cuke_seed_batch" "b" ON (("b"."id" = "h"."grow_cuke_seed_batch_id")))
     LEFT JOIN "public"."invnt_item" "i" ON (("i"."id" = "b"."invnt_item_id")))
  WHERE (("h"."farm_id" = 'Cuke'::"text") AND ("h"."is_deleted" = false));


ALTER VIEW "public"."grow_cuke_harvest" OWNER TO "postgres";


COMMENT ON VIEW "public"."grow_cuke_harvest" IS 'Cuke harvest weigh-ins with display-friendly greenhouse names (GH1/Kona/HK/etc.), variety letter (K/J/E), and days_since_seed (harvest_date - seeding_date) for dashboards.';



CREATE TABLE IF NOT EXISTS "public"."grow_cuke_rotation" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "slot_num" integer NOT NULL,
    "site_id" "text" NOT NULL,
    "is_anchor" boolean DEFAULT false NOT NULL,
    "anchor_week_start" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "grow_cuke_rotation_check" CHECK (((("is_anchor" = true) AND ("anchor_week_start" IS NOT NULL)) OR (("is_anchor" = false) AND ("anchor_week_start" IS NULL)))),
    CONSTRAINT "grow_cuke_rotation_slot_num_check" CHECK ((("slot_num" >= 1) AND ("slot_num" <= 12)))
);


ALTER TABLE "public"."grow_cuke_rotation" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_cuke_rotation" IS 'Cuke seeding rotation slots. 12 rows, one per 12-week cycle position. Anchor row carries the calendar date for its seeding week; all other slots are derived.';



CREATE TABLE IF NOT EXISTS "public"."grow_cycle_pattern" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_cycle_pattern" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_cycle_pattern" IS 'Defines growing cycle patterns per farm (e.g. 18/17/17 harvest pattern). Used to classify seeding batches by their growth cycle.';



CREATE TABLE IF NOT EXISTS "public"."grow_disease" (
    "id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_disease" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_disease" IS 'System-wide disease catalog for scouting observations. Diseases are biological facts shared across all organizations.';



CREATE TABLE IF NOT EXISTS "public"."grow_fertigation" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "grow_fertigation_recipe_id" "text" NOT NULL,
    "equipment_id" "text",
    "volume_uom" "text" NOT NULL,
    "volume_applied" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_fertigation" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_fertigation" IS 'Tanks used during a fertigation event with the volume applied per tank.';



COMMENT ON COLUMN "public"."grow_fertigation"."grow_fertigation_recipe_id" IS 'Pre-filled from grow_fertigation_recipe_site based on selected sites; editable';



COMMENT ON COLUMN "public"."grow_fertigation"."equipment_id" IS 'Filtered to org_equipment where type = tank; pre-filled from grow_fertigation_recipe_item.equipment_id; editable';



CREATE TABLE IF NOT EXISTS "public"."grow_fertigation_recipe" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_fertigation_recipe" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_fertigation_recipe" IS 'Reusable fertigation recipe. Can be a fertilizer mix, flush water, or top-up water — each is a separate recipe. Items are defined in grow_fertigation_recipe_item. Sites are linked via grow_fertigation_recipe_site.';



CREATE TABLE IF NOT EXISTS "public"."grow_fertigation_recipe_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "grow_fertigation_recipe_id" "text" NOT NULL,
    "equipment_id" "text",
    "invnt_item_id" "text",
    "item_name" "text" NOT NULL,
    "application_uom" "text" NOT NULL,
    "application_quantity" numeric NOT NULL,
    "burn_uom" "text",
    "application_per_burn" numeric,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_fertigation_recipe_item" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_fertigation_recipe_item" IS 'Individual fertilizer items within a recipe. invnt_item_id is nullable for products not stored in-house; item_name is always set for display.';



COMMENT ON COLUMN "public"."grow_fertigation_recipe_item"."item_name" IS 'Pre-filled from invnt_item.id when invnt_item_id is set; editable';



COMMENT ON COLUMN "public"."grow_fertigation_recipe_item"."burn_uom" IS 'Pre-filled from grow_spray_compliance.burn_uom when a compliance record exists; editable';



COMMENT ON COLUMN "public"."grow_fertigation_recipe_item"."application_per_burn" IS 'Pre-filled from grow_spray_compliance.application_per_burn when a compliance record exists; editable';



CREATE TABLE IF NOT EXISTS "public"."grow_fertigation_recipe_site" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "grow_fertigation_recipe_id" "text" NOT NULL,
    "site_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_fertigation_recipe_site" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_fertigation_recipe_site" IS 'Sites that receive this fertigation recipe. Used to pre-fill site selection and look up active seedings during a fertigation event.';



CREATE TABLE IF NOT EXISTS "public"."grow_grade" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_grade" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_grade" IS 'Harvest quality grades for a specific farm, each with a short code. Applied during harvest logging and carried through to product definition, packing, and sales.';



CREATE TABLE IF NOT EXISTS "public"."grow_harvest_container" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "grow_variety_id" "text",
    "grow_grade_id" "text",
    "weight_uom" "text" NOT NULL,
    "tare_weight" numeric,
    "is_tare_calculated" boolean DEFAULT false NOT NULL,
    "tare_formula" "text",
    "tare_formula_inputs" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_harvest_container" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_harvest_container" IS 'Harvest container definitions with tare weight per container type, optionally specific to variety and grade. Used to auto-calculate tare during weigh-ins.';



COMMENT ON COLUMN "public"."grow_harvest_container"."grow_variety_id" IS 'Tare weight can vary by variety; null means any variety';



COMMENT ON COLUMN "public"."grow_harvest_container"."grow_grade_id" IS 'Tare weight can vary by grade; null means any grade';



COMMENT ON COLUMN "public"."grow_harvest_container"."tare_weight" IS 'Fixed weight of one empty container; multiplied by number_of_containers in grow_harvest_weight. Null when is_tare_calculated is true.';



COMMENT ON COLUMN "public"."grow_harvest_container"."is_tare_calculated" IS 'When true, tare is computed per weigh-in via tare_formula; when false the static tare_weight applies.';



COMMENT ON COLUMN "public"."grow_harvest_container"."tare_formula" IS 'SQL-style formula evaluated against the gross_weight at weigh-in (e.g. "ROUND(0.031 * gross_weight - 0.83) * 3 + 48")';



COMMENT ON COLUMN "public"."grow_harvest_container"."tare_formula_inputs" IS 'Optional JSONB metadata for extra formula inputs (e.g. variety-specific coefficients)';



CREATE TABLE IF NOT EXISTS "public"."grow_lettuce_seed_batch" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text",
    "ops_task_tracker_id" "uuid",
    "batch_code" "text" NOT NULL,
    "grow_cycle_pattern_id" "text",
    "grow_trial_type_id" "text",
    "grow_lettuce_seed_mix_id" "text",
    "invnt_item_id" "text",
    "invnt_lot_id" "text",
    "seeding_uom" "text" NOT NULL,
    "number_of_units" integer NOT NULL,
    "seeds_per_unit" integer NOT NULL,
    "number_of_rows" integer NOT NULL,
    "seeding_date" "date" NOT NULL,
    "transplant_date" "date" NOT NULL,
    "estimated_harvest_date" "date" NOT NULL,
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_grow_lettuce_seed_batch_source" CHECK (((("invnt_item_id" IS NOT NULL) AND ("grow_lettuce_seed_mix_id" IS NULL)) OR (("invnt_item_id" IS NULL) AND ("grow_lettuce_seed_mix_id" IS NOT NULL)))),
    CONSTRAINT "grow_lettuce_seed_batch_status_check" CHECK (("status" = ANY (ARRAY['Planned'::"text", 'Seeded'::"text", 'Transplanted'::"text", 'Harvesting'::"text", 'Harvested'::"text"])))
);


ALTER TABLE "public"."grow_lettuce_seed_batch" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_lettuce_seed_batch" IS 'Lettuce seeding batch linked to an ops activity. Either a single seed item or a seed mix, never both. Cuke seeding lives in grow_cuke_seed_batch.';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."site_id" IS 'Filtered to org_site where category = growing (subcategory: nursery, greenhouse, or pond)';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."batch_code" IS 'System-generated traceability code; carries through to harvesting; editable';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."grow_cycle_pattern_id" IS 'Describes the cycle pattern (e.g. 18/17/17 harvest pattern); does not drive calculations';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."grow_trial_type_id" IS 'Null if not a trial; set when testing a new lot, variety, or seed source';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."grow_lettuce_seed_mix_id" IS 'Set when seeding a mix; null when seeding a single variety. Mutually exclusive with invnt_item_id';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."invnt_item_id" IS 'Set when seeding a single seed item; null when seeding a mix. Mutually exclusive with grow_lettuce_seed_mix_id';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."invnt_lot_id" IS 'Only when invnt_item_id is set; sourced from invnt_lot filtered by the selected item';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."seeding_uom" IS 'Unit for number_of_units (e.g. board, flat, tray)';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."transplant_date" IS 'Planned or actual transplant date';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."estimated_harvest_date" IS 'User-selected estimated harvest date';



COMMENT ON COLUMN "public"."grow_lettuce_seed_batch"."status" IS 'Auto-set: planned (seeding_date > today), seeded (seeding_date <= today < transplant_date), transplanted (transplant_date <= today < estimated_harvest_date), harvesting (estimated_harvest_date <= today), harvested (manually set when complete)';



CREATE OR REPLACE VIEW "public"."grow_lettuce_harvest" WITH ("security_invoker"='true') AS
 SELECT "h"."id",
    "h"."harvest_date",
    "upper"("h"."site_id") AS "pond",
    COALESCE("i"."id", ''::"text") AS "seed_name",
    "h"."number_of_containers" AS "boards_per_pond",
        CASE
            WHEN ("h"."number_of_containers" > 0) THEN ("h"."net_weight" / ("h"."number_of_containers")::numeric)
            ELSE (0)::numeric
        END AS "pounds_per_board",
    "h"."net_weight" AS "greenhouse_net_weight",
    "h"."gross_weight",
    "h"."grow_lettuce_seed_batch_id",
    "h"."org_id",
    "h"."farm_id"
   FROM (("public"."grow_harvest_weight" "h"
     LEFT JOIN "public"."grow_lettuce_seed_batch" "b" ON (("b"."id" = "h"."grow_lettuce_seed_batch_id")))
     LEFT JOIN "public"."invnt_item" "i" ON (("i"."id" = "b"."invnt_item_id")))
  WHERE (("h"."farm_id" = 'Lettuce'::"text") AND ("h"."is_deleted" = false));


ALTER VIEW "public"."grow_lettuce_harvest" OWNER TO "postgres";


COMMENT ON VIEW "public"."grow_lettuce_harvest" IS 'Lettuce harvest weigh-ins with pond name uppercased (P1/P2/..) and seed cultivar name joined from invnt_item. boards_per_pond = number_of_containers, pounds_per_board = net_weight / number_of_containers.';



CREATE TABLE IF NOT EXISTS "public"."grow_lettuce_seed_mix" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_lettuce_seed_mix" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_lettuce_seed_mix" IS 'Named seed blend recipes (e.g. Spring Blend, Mixed Version 1). Farm-scoped. Items and percentages are defined in grow_lettuce_seed_mix_item.';



CREATE TABLE IF NOT EXISTS "public"."grow_lettuce_seed_mix_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "grow_lettuce_seed_mix_id" "text" NOT NULL,
    "invnt_item_id" "text" NOT NULL,
    "invnt_lot_id" "text",
    "percentage" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_lettuce_seed_mix_item" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_lettuce_seed_mix_item" IS 'Individual seed items within a mix recipe with their proportion. Each row defines one seed and its percentage in the blend.';



COMMENT ON COLUMN "public"."grow_lettuce_seed_mix_item"."invnt_lot_id" IS 'Sourced from invnt_lot filtered by the selected invnt_item_id';



COMMENT ON COLUMN "public"."grow_lettuce_seed_mix_item"."percentage" IS 'Proportion in the mix (e.g. 0.6 for 60%); all items in a mix should sum to 1.0';



CREATE TABLE IF NOT EXISTS "public"."grow_monitoring_metric" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_category" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "response_type" "text" DEFAULT 'numeric'::"text" NOT NULL,
    "reading_uom" "text",
    "minimum_value" numeric,
    "maximum_value" numeric,
    "enum_options" "jsonb",
    "enum_pass_options" "jsonb",
    "is_calculated" boolean DEFAULT false NOT NULL,
    "formula" "text",
    "input_point_ids" "jsonb",
    "is_required" boolean DEFAULT true NOT NULL,
    "corrective_actions" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "grow_monitoring_metric_response_type_check" CHECK (("response_type" = ANY (ARRAY['Boolean'::"text", 'Numeric'::"text", 'Enum'::"text"])))
);


ALTER TABLE "public"."grow_monitoring_metric" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_monitoring_metric" IS 'Defines what to measure per farm and site category. Direct points are entered manually; calculated points are derived from other points using a formula.';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."site_category" IS 'Matches org_site.category to scope which metrics apply (e.g. greenhouse, nursery, pond)';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."response_type" IS 'boolean, numeric, enum';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."minimum_value" IS 'Reading below this value auto-sets grow_monitoring_result.is_out_of_range to true; null if not numeric';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."maximum_value" IS 'Reading above this value auto-sets grow_monitoring_result.is_out_of_range to true; null if not numeric';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."enum_options" IS 'JSON array of allowed values when response_type is enum; null if not enum';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."enum_pass_options" IS 'Subset of enum_options that are acceptable; values outside this set auto-set is_out_of_range to true';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."formula" IS 'Expression for calculated points (e.g. (drain_ml / (drip_ml * drippers)) * 100); null when is_calculated = false';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."input_point_ids" IS 'JSON array of grow_monitoring_metric IDs that feed into this calculation; null when is_calculated = false';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."is_required" IS 'When true, an out-of-range reading triggers corrective action creation; when false, the metric is informational only';



COMMENT ON COLUMN "public"."grow_monitoring_metric"."corrective_actions" IS 'JSON array of corrective action options shown when reading is out of range; selected value stored in grow_monitoring_result.corrective_action';



CREATE TABLE IF NOT EXISTS "public"."grow_monitoring_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "grow_monitoring_metric_id" "text" NOT NULL,
    "monitoring_station" "text",
    "reading" numeric,
    "reading_boolean" boolean,
    "reading_enum" "text",
    "is_out_of_range" boolean DEFAULT false NOT NULL,
    "corrective_action" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_monitoring_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_monitoring_result" IS 'Individual measurement recorded during a monitoring event. One row per point per station. Calculated points store the computed result for historical record.';



COMMENT ON COLUMN "public"."grow_monitoring_result"."reading" IS 'Auto-calculated from grow_monitoring_metric.formula when point_type is calculated';



COMMENT ON COLUMN "public"."grow_monitoring_result"."reading_enum" IS 'Selected from grow_monitoring_metric.enum_options when response_type is enum';



COMMENT ON COLUMN "public"."grow_monitoring_result"."is_out_of_range" IS 'Auto-set by comparing reading against grow_monitoring_metric min/max values or enum_pass_options';



COMMENT ON COLUMN "public"."grow_monitoring_result"."corrective_action" IS 'Pre-filled from grow_monitoring_metric.corrective_actions when is_out_of_range is true; editable';



CREATE TABLE IF NOT EXISTS "public"."grow_pest" (
    "id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_pest" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_pest" IS 'System-wide pest catalog for scouting observations. Pests are biological facts shared across all organizations.';



CREATE TABLE IF NOT EXISTS "public"."grow_scout_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "site_id" "text",
    "observation_type" "text" NOT NULL,
    "grow_pest_id" "text",
    "grow_disease_id" "text",
    "disease_infection_stage" "text",
    "severity_level" "text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "grow_scout_result_disease_infection_stage_check" CHECK (("disease_infection_stage" = ANY (ARRAY['Early'::"text", 'Mid'::"text", 'Late'::"text", 'Advanced'::"text"]))),
    CONSTRAINT "grow_scout_result_observation_type_check" CHECK (("observation_type" = ANY (ARRAY['Pest'::"text", 'Disease'::"text"]))),
    CONSTRAINT "grow_scout_result_severity_level_check" CHECK (("severity_level" = ANY (ARRAY['Low'::"text", 'Moderate'::"text", 'High'::"text", 'Severe'::"text"])))
);


ALTER TABLE "public"."grow_scout_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_scout_result" IS 'Individual pest or disease finding within a scouting event. Either a pest or disease, enforced by CHECK constraint.';



COMMENT ON COLUMN "public"."grow_scout_result"."site_id" IS 'The specific growing row (org_site where category = row); one observation per row per pest/disease';



COMMENT ON COLUMN "public"."grow_scout_result"."observation_type" IS 'pest, disease';



COMMENT ON COLUMN "public"."grow_scout_result"."grow_pest_id" IS 'Shown when observation_type is pest; null when disease';



COMMENT ON COLUMN "public"."grow_scout_result"."grow_disease_id" IS 'Shown when observation_type is disease; null when pest';



COMMENT ON COLUMN "public"."grow_scout_result"."disease_infection_stage" IS 'early, mid, late, advanced; shown when observation_type is disease; null when pest';



COMMENT ON COLUMN "public"."grow_scout_result"."severity_level" IS 'low, moderate, high, severe';



CREATE TABLE IF NOT EXISTS "public"."grow_spray_compliance" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "invnt_item_id" "text",
    "epa_registration" "text",
    "phi_days" integer DEFAULT 0 NOT NULL,
    "rei_hours" integer DEFAULT 0 NOT NULL,
    "application_method" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "target_pest_disease" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "application_uom" "text",
    "maximum_quantity_per_acre" numeric,
    "burn_uom" "text",
    "application_per_burn" numeric DEFAULT 1 NOT NULL,
    "label_date" "date",
    "effective_date" "date",
    "expiration_date" "date",
    "external_label_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_spray_compliance" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_spray_compliance" IS 'Chemical label registry storing regulatory information per product. One row per chemical/fertilizer item with REI, PHI, label rates, and application restrictions.';



COMMENT ON COLUMN "public"."grow_spray_compliance"."invnt_item_id" IS 'The chemical or fertilizer product this compliance record applies to';



COMMENT ON COLUMN "public"."grow_spray_compliance"."epa_registration" IS 'EPA registration number from the product label';



COMMENT ON COLUMN "public"."grow_spray_compliance"."phi_days" IS 'Pre-Harvest Interval in days; minimum days between last application and harvest';



COMMENT ON COLUMN "public"."grow_spray_compliance"."rei_hours" IS 'Restricted Entry Interval in hours; minimum hours before workers can re-enter treated area';



COMMENT ON COLUMN "public"."grow_spray_compliance"."application_method" IS 'JSON array of allowed application methods from the label (e.g. ["spray", "drench", "granular"])';



COMMENT ON COLUMN "public"."grow_spray_compliance"."target_pest_disease" IS 'JSON array of pests/diseases this product is labeled to treat';



COMMENT ON COLUMN "public"."grow_spray_compliance"."maximum_quantity_per_acre" IS 'Maximum label rate per acre per application; app enforces this limit on grow_spray_input';



COMMENT ON COLUMN "public"."grow_spray_compliance"."burn_uom" IS 'Smallest consumption unit for this product (e.g. oz, ml, g)';



COMMENT ON COLUMN "public"."grow_spray_compliance"."application_per_burn" IS 'Application rate expressed in burn units; used for inventory deduction';



COMMENT ON COLUMN "public"."grow_spray_compliance"."label_date" IS 'Date printed on the product label';



COMMENT ON COLUMN "public"."grow_spray_compliance"."effective_date" IS 'Date this compliance record becomes active; only the active record is shown for selection';



COMMENT ON COLUMN "public"."grow_spray_compliance"."expiration_date" IS 'Date this compliance record expires; null means no expiry';



COMMENT ON COLUMN "public"."grow_spray_compliance"."external_label_url" IS 'URL to the full product label PDF for reference';



CREATE TABLE IF NOT EXISTS "public"."grow_spray_equipment" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "equipment_id" "text",
    "water_uom" "text" NOT NULL,
    "water_quantity" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_spray_equipment" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_spray_equipment" IS 'Equipment used during a spraying event with the water quantity per piece of equipment.';



COMMENT ON COLUMN "public"."grow_spray_equipment"."equipment_id" IS 'Filtered to org_equipment where type IN (fogger, bag_pack_sprayer)';



CREATE TABLE IF NOT EXISTS "public"."grow_spray_input" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "grow_spray_compliance_id" "uuid" NOT NULL,
    "invnt_item_id" "text" NOT NULL,
    "invnt_lot_id" "text",
    "target_pest_disease" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "application_uom" "text" NOT NULL,
    "application_quantity" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_spray_input" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_spray_input" IS 'Individual chemical or fertilizer applied during a spraying event. One row per input product. The compliance record is the source of truth — only compliant products can be sprayed, and the app enforces label rate limits via maximum_quantity_per_acre.';



COMMENT ON COLUMN "public"."grow_spray_input"."invnt_item_id" IS 'Pre-filled from grow_spray_compliance.invnt_item_id';



COMMENT ON COLUMN "public"."grow_spray_input"."invnt_lot_id" IS 'Sourced from invnt_lot filtered by the selected invnt_item_id';



COMMENT ON COLUMN "public"."grow_spray_input"."target_pest_disease" IS 'Pre-filled from grow_spray_compliance.target_pest_disease; editable';



COMMENT ON COLUMN "public"."grow_spray_input"."application_uom" IS 'Pre-filled from grow_spray_compliance.application_uom; editable';



CREATE TABLE IF NOT EXISTS "public"."ops_task_tracker" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "site_id" "text",
    "sales_product_id" "text",
    "ops_task_id" "text" NOT NULL,
    "start_time" timestamp with time zone NOT NULL,
    "stop_time" timestamp with time zone,
    "is_completed" boolean DEFAULT false NOT NULL,
    "number_of_people" integer,
    "notes" "text",
    "verified_at" timestamp with time zone,
    "verified_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_task_tracker" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_task_tracker" IS 'Header record for a task event. One record per task session — captures what task was done, where, when, and its verification status.';



COMMENT ON COLUMN "public"."ops_task_tracker"."farm_id" IS 'Pre-filled from ops_task.farm_id when task is selected; editable';



COMMENT ON COLUMN "public"."ops_task_tracker"."sales_product_id" IS 'The product being packed; set for packing activities, null for all other task types';



COMMENT ON COLUMN "public"."ops_task_tracker"."is_completed" IS 'Auto-set to true when stop_time is entered and activity is submitted';



COMMENT ON COLUMN "public"."ops_task_tracker"."number_of_people" IS 'Crew size assigned to this task session; used for productivity/labor-hour calculations';



CREATE OR REPLACE VIEW "public"."grow_spray_restriction" WITH ("security_invoker"='true') AS
 WITH "spray_events" AS (
         SELECT "tt"."id" AS "ops_task_tracker_id",
            "tt"."org_id",
            "tt"."farm_id",
            "tt"."site_id",
            "tt"."stop_time" AS "spray_stop",
            "max"("c"."rei_hours") AS "max_rei_hours",
            "max"("c"."phi_days") AS "max_phi_days"
           FROM (("public"."ops_task_tracker" "tt"
             JOIN "public"."grow_spray_input" "si" ON ((("si"."ops_task_tracker_id" = "tt"."id") AND ("si"."is_deleted" = false))))
             JOIN "public"."grow_spray_compliance" "c" ON (("c"."id" = "si"."grow_spray_compliance_id")))
          WHERE (("tt"."is_deleted" = false) AND ("tt"."is_completed" = true) AND ("tt"."stop_time" IS NOT NULL))
          GROUP BY "tt"."id", "tt"."org_id", "tt"."farm_id", "tt"."site_id", "tt"."stop_time"
        ), "rei_restrictions" AS (
         SELECT "se"."ops_task_tracker_id",
            "se"."org_id",
            "se"."farm_id",
            "se"."site_id",
            'NE'::"text" AS "restriction_type",
            ("d"."d")::"date" AS "restriction_date",
            GREATEST("se"."spray_stop", "d"."d") AS "start_time",
            LEAST(("se"."spray_stop" + (("se"."max_rei_hours")::double precision * '01:00:00'::interval)), ("d"."d" + '1 day'::interval)) AS "end_time",
            "se"."spray_stop",
            ("se"."spray_stop" + (("se"."max_rei_hours")::double precision * '01:00:00'::interval)) AS "rei_stop",
            "se"."max_rei_hours"
           FROM ("spray_events" "se"
             CROSS JOIN LATERAL "generate_series"((("se"."spray_stop")::"date")::timestamp with time zone, ((("se"."spray_stop" + (("se"."max_rei_hours")::double precision * '01:00:00'::interval)))::"date")::timestamp with time zone, '1 day'::interval) "d"("d"))
          WHERE ("se"."max_rei_hours" > 0)
        ), "phi_restrictions" AS (
         SELECT "se"."ops_task_tracker_id",
            "se"."org_id",
            "se"."farm_id",
            "se"."site_id",
            'NH'::"text" AS "restriction_type",
            ("d"."d")::"date" AS "restriction_date",
            GREATEST("se"."spray_stop", "d"."d") AS "start_time",
            LEAST(("se"."spray_stop" + (("se"."max_phi_days")::double precision * '1 day'::interval)), ("d"."d" + '1 day'::interval)) AS "end_time",
            "se"."spray_stop",
            ("se"."spray_stop" + (("se"."max_phi_days")::double precision * '1 day'::interval)) AS "phi_stop",
            "se"."max_phi_days"
           FROM ("spray_events" "se"
             CROSS JOIN LATERAL "generate_series"((("se"."spray_stop")::"date")::timestamp with time zone, ((("se"."spray_stop" + (("se"."max_phi_days")::double precision * '1 day'::interval)))::"date")::timestamp with time zone, '1 day'::interval) "d"("d"))
          WHERE ("se"."max_phi_days" > 0)
        )
 SELECT "rei_restrictions"."ops_task_tracker_id",
    "rei_restrictions"."org_id",
    "rei_restrictions"."farm_id",
    "rei_restrictions"."site_id",
    "rei_restrictions"."restriction_type",
    "rei_restrictions"."restriction_date",
    "rei_restrictions"."start_time",
    "rei_restrictions"."end_time",
    "rei_restrictions"."spray_stop",
    "rei_restrictions"."rei_stop" AS "restriction_stop",
    "rei_restrictions"."max_rei_hours" AS "restriction_value"
   FROM "rei_restrictions"
UNION ALL
 SELECT "phi_restrictions"."ops_task_tracker_id",
    "phi_restrictions"."org_id",
    "phi_restrictions"."farm_id",
    "phi_restrictions"."site_id",
    "phi_restrictions"."restriction_type",
    "phi_restrictions"."restriction_date",
    "phi_restrictions"."start_time",
    "phi_restrictions"."end_time",
    "phi_restrictions"."spray_stop",
    "phi_restrictions"."phi_stop" AS "restriction_stop",
    "phi_restrictions"."max_phi_days" AS "restriction_value"
   FROM "phi_restrictions";


ALTER VIEW "public"."grow_spray_restriction" OWNER TO "postgres";


COMMENT ON VIEW "public"."grow_spray_restriction" IS 'Derived daily restriction calendar per site after each spray event. NE (No Entry) rows span from spray stop to REI expiry. NH (No Harvest) rows span from spray stop to PHI expiry. One row per calendar day per restriction type per spray event.';



CREATE TABLE IF NOT EXISTS "public"."grow_task_photo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "photo_url" "text" NOT NULL,
    "caption" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_task_photo" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_task_photo" IS 'Unified photo table for any grow activity (scouting, monitoring, etc.). One row per photo with optional caption. Activity type is derived from ops_task_tracker → ops_task_id.';



CREATE TABLE IF NOT EXISTS "public"."grow_task_seed_batch" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid" NOT NULL,
    "grow_lettuce_seed_batch_id" "uuid",
    "grow_cuke_seed_batch_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_grow_task_seed_batch_exactly_one" CHECK (((("grow_lettuce_seed_batch_id" IS NOT NULL) AND ("grow_cuke_seed_batch_id" IS NULL)) OR (("grow_lettuce_seed_batch_id" IS NULL) AND ("grow_cuke_seed_batch_id" IS NOT NULL))))
);


ALTER TABLE "public"."grow_task_seed_batch" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_task_seed_batch" IS 'Unified join table linking any grow activity (scouting, spraying, fertigation, monitoring) to the seeding batches involved. Exactly one of grow_lettuce_seed_batch_id / grow_cuke_seed_batch_id is set, determined by the farm. Activity type is derived from ops_task_tracker -> ops_task_id.';



COMMENT ON COLUMN "public"."grow_task_seed_batch"."grow_lettuce_seed_batch_id" IS 'The lettuce seeding batch covered by this activity. Populated when farm_id = Lettuce; null for Cuke';



COMMENT ON COLUMN "public"."grow_task_seed_batch"."grow_cuke_seed_batch_id" IS 'The cuke seeding batch covered by this activity. Populated when farm_id = Cuke; null for Lettuce';



CREATE TABLE IF NOT EXISTS "public"."grow_trial_type" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_trial_type" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_trial_type" IS 'Lookup table defining types of seeding trials (e.g. new lot, new variety, new seed source). Farm-scoped.';



CREATE TABLE IF NOT EXISTS "public"."grow_variety" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."grow_variety" OWNER TO "postgres";


COMMENT ON TABLE "public"."grow_variety" IS 'Crop varieties grown on a specific farm, each with a short code for quick reference during data entry. Used across seeding, growing, and harvest modules.';



CREATE TABLE IF NOT EXISTS "public"."hr_department" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."hr_department" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_department" IS 'Org-specific departments used to classify employees. Each org defines its own set of departments. id is the display name (e.g. "GH", "PH", "Lettuce").';



CREATE TABLE IF NOT EXISTS "public"."hr_disciplinary_warning" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "warning_date" "date",
    "warning_type" "text",
    "offense_type" "text",
    "offense_description" "text",
    "plan_for_improvement" "text",
    "further_infraction_consequences" "text",
    "notes" "text",
    "is_acknowledged" boolean DEFAULT false NOT NULL,
    "acknowledged_at" timestamp with time zone,
    "employee_signature_url" "text",
    "status" "text" DEFAULT 'Pending'::"text" NOT NULL,
    "reported_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reported_by" "text",
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "hr_disciplinary_warning_status_check" CHECK (("status" = ANY (ARRAY['Pending'::"text", 'Reviewed'::"text"]))),
    CONSTRAINT "hr_disciplinary_warning_warning_type_check" CHECK (("warning_type" = ANY (ARRAY['Verbal Warning'::"text", 'Written Warning'::"text", 'Final Warning'::"text"])))
);


ALTER TABLE "public"."hr_disciplinary_warning" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_disciplinary_warning" IS 'Employee disciplinary warning records. Tracks the offense, action plan, and employee acknowledgment alongside a pending to reviewed workflow.';



COMMENT ON COLUMN "public"."hr_disciplinary_warning"."warning_type" IS 'verbal_warning, written_warning, final_warning';



COMMENT ON COLUMN "public"."hr_disciplinary_warning"."status" IS 'pending, reviewed';



CREATE TABLE IF NOT EXISTS "public"."hr_employee" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "first_name" "text" NOT NULL,
    "last_name" "text" NOT NULL,
    "preferred_name" "text",
    "gender" "text",
    "date_of_birth" "date",
    "ethnicity" "text" DEFAULT 'Non-Caucasian'::"text",
    "profile_photo_url" "text",
    "phone" "text",
    "email" "text",
    "company_email" "text",
    "user_id" "uuid",
    "is_primary_org" boolean DEFAULT false NOT NULL,
    "hr_department_id" "text",
    "sys_access_level_id" "text" NOT NULL,
    "team_lead_id" "text",
    "compensation_manager_id" "text",
    "hr_work_authorization_id" "text",
    "start_date" "date",
    "end_date" "date",
    "payroll_id" "text",
    "pay_structure" "text",
    "overtime_threshold" numeric,
    "wc" "text",
    "payroll_processor" "text",
    "pay_delivery_method" "text",
    "housing_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "hr_employee_ethnicity_check" CHECK (("ethnicity" = ANY (ARRAY['Caucasian'::"text", 'Non-Caucasian'::"text"]))),
    CONSTRAINT "hr_employee_gender_check" CHECK (("gender" = ANY (ARRAY['Male'::"text", 'Female'::"text"]))),
    CONSTRAINT "hr_employee_pay_structure_check" CHECK (("pay_structure" = ANY (ARRAY['Hourly'::"text", 'Salary'::"text"])))
);


ALTER TABLE "public"."hr_employee" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_employee" IS 'Unified employee register and org membership table. Every employee gets a row here with a required sys_access_level_id that defines their role (owner, manager, team_lead, employee). Employees without app access have a null user_id. A user can belong to multiple orgs by having one row per org. Tracks employment details, management hierarchy, and compensation.';



COMMENT ON COLUMN "public"."hr_employee"."is_primary_org" IS 'When user belongs to multiple orgs, the primary org auto-loads on login; only one row per user_id should be true';



COMMENT ON COLUMN "public"."hr_employee"."sys_access_level_id" IS 'Sourced from sys_access_level; determines the employee role and module visibility';



COMMENT ON COLUMN "public"."hr_employee"."team_lead_id" IS 'Filtered to employees with sys_access_level_id = team_lead';



COMMENT ON COLUMN "public"."hr_employee"."compensation_manager_id" IS 'Filtered to employees with sys_access_level_id = manager';



COMMENT ON COLUMN "public"."hr_employee"."pay_structure" IS 'hourly, salary';



COMMENT ON COLUMN "public"."hr_employee"."overtime_threshold" IS 'Hours per week before overtime applies; only relevant when pay_structure = hourly';



COMMENT ON COLUMN "public"."hr_employee"."wc" IS 'Workers compensation code identifying the compensation plan or pay grade';



COMMENT ON COLUMN "public"."hr_employee"."housing_id" IS 'References org_site_housing; the housing facility the employee is assigned to. Null if the employee is not housed';



CREATE TABLE IF NOT EXISTS "public"."hr_employee_review" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "review_year" integer NOT NULL,
    "review_quarter" integer NOT NULL,
    "productivity" integer NOT NULL,
    "attendance" integer NOT NULL,
    "quality" integer NOT NULL,
    "engagement" integer NOT NULL,
    "average" numeric GENERATED ALWAYS AS (((((("productivity" + "attendance") + "quality") + "engagement"))::numeric / 4.0)) STORED,
    "notes" "text",
    "lead_id" "text",
    "is_locked" boolean DEFAULT false NOT NULL,
    "created_by" "text",
    "updated_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "hr_employee_review_attendance_check" CHECK ((("attendance" >= 1) AND ("attendance" <= 3))),
    CONSTRAINT "hr_employee_review_engagement_check" CHECK ((("engagement" >= 1) AND ("engagement" <= 3))),
    CONSTRAINT "hr_employee_review_productivity_check" CHECK ((("productivity" >= 1) AND ("productivity" <= 3))),
    CONSTRAINT "hr_employee_review_quality_check" CHECK ((("quality" >= 1) AND ("quality" <= 3))),
    CONSTRAINT "hr_employee_review_review_quarter_check" CHECK ((("review_quarter" >= 1) AND ("review_quarter" <= 4)))
);


ALTER TABLE "public"."hr_employee_review" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hr_module_access" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "sys_module_id" "text" NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "can_edit" boolean DEFAULT true NOT NULL,
    "can_delete" boolean DEFAULT false NOT NULL,
    "can_verify" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."hr_module_access" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_module_access" IS 'Controls which modules each employee can access. One row per employee per module; is_enabled toggles access without deleting the record.';



COMMENT ON COLUMN "public"."hr_module_access"."sys_module_id" IS 'Sourced from org_module; identifies which module this access record controls';



COMMENT ON COLUMN "public"."hr_module_access"."is_enabled" IS 'Pre-filled from org_module.is_enabled when employee access is seeded; editable per employee';



COMMENT ON COLUMN "public"."hr_module_access"."can_edit" IS 'Auto-set to true when provisioned; controls whether employee can edit records in this module';



COMMENT ON COLUMN "public"."hr_module_access"."can_delete" IS 'Auto-set to false when provisioned; controls whether employee can delete records in this module';



COMMENT ON COLUMN "public"."hr_module_access"."can_verify" IS 'Auto-set to false when provisioned; controls whether employee can verify/approve records in this module';



CREATE TABLE IF NOT EXISTS "public"."hr_payroll" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "payroll_id" "text" NOT NULL,
    "pay_period_start" "date" NOT NULL,
    "pay_period_end" "date" NOT NULL,
    "check_date" "date" NOT NULL,
    "invoice_number" "text",
    "payroll_processor" "text" NOT NULL,
    "is_standard" boolean DEFAULT true NOT NULL,
    "employee_name" "text" NOT NULL,
    "hr_department_id" "text",
    "hr_work_authorization_id" "text",
    "wc" "text",
    "pay_structure" "text",
    "hourly_rate" numeric,
    "overtime_threshold" numeric,
    "regular_hours" numeric DEFAULT 0 NOT NULL,
    "overtime_hours" numeric DEFAULT 0 NOT NULL,
    "discretionary_overtime_hours" numeric DEFAULT 0 NOT NULL,
    "holiday_hours" numeric DEFAULT 0 NOT NULL,
    "pto_hours" numeric DEFAULT 0 NOT NULL,
    "sick_hours" numeric DEFAULT 0 NOT NULL,
    "funeral_hours" numeric DEFAULT 0 NOT NULL,
    "total_hours" numeric DEFAULT 0 NOT NULL,
    "pto_hours_accrued" numeric DEFAULT 0 NOT NULL,
    "regular_pay" numeric DEFAULT 0 NOT NULL,
    "overtime_pay" numeric DEFAULT 0 NOT NULL,
    "discretionary_overtime_pay" numeric DEFAULT 0 NOT NULL,
    "holiday_pay" numeric DEFAULT 0 NOT NULL,
    "pto_pay" numeric DEFAULT 0 NOT NULL,
    "sick_pay" numeric DEFAULT 0 NOT NULL,
    "funeral_pay" numeric DEFAULT 0 NOT NULL,
    "other_pay" numeric DEFAULT 0 NOT NULL,
    "bonus_pay" numeric DEFAULT 0 NOT NULL,
    "auto_allowance" numeric DEFAULT 0 NOT NULL,
    "per_diem" numeric DEFAULT 0 NOT NULL,
    "salary" numeric DEFAULT 0 NOT NULL,
    "gross_wage" numeric DEFAULT 0 NOT NULL,
    "fit" numeric DEFAULT 0 NOT NULL,
    "sit" numeric DEFAULT 0 NOT NULL,
    "social_security" numeric DEFAULT 0 NOT NULL,
    "medicare" numeric DEFAULT 0 NOT NULL,
    "comp_plus" numeric DEFAULT 0 NOT NULL,
    "hds_dental" numeric DEFAULT 0 NOT NULL,
    "pre_tax_401k" numeric DEFAULT 0 NOT NULL,
    "auto_deduction" numeric DEFAULT 0 NOT NULL,
    "child_support" numeric DEFAULT 0 NOT NULL,
    "program_fees" numeric DEFAULT 0 NOT NULL,
    "net_pay" numeric DEFAULT 0 NOT NULL,
    "labor_tax" numeric DEFAULT 0 NOT NULL,
    "other_tax" numeric DEFAULT 0 NOT NULL,
    "workers_compensation" numeric DEFAULT 0 NOT NULL,
    "health_benefits" numeric DEFAULT 0 NOT NULL,
    "other_health_charges" numeric DEFAULT 0 NOT NULL,
    "admin_fees" numeric DEFAULT 0 NOT NULL,
    "hawaii_get" numeric DEFAULT 0 NOT NULL,
    "other_charges" numeric DEFAULT 0 NOT NULL,
    "tdi" numeric DEFAULT 0 NOT NULL,
    "total_cost" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."hr_payroll" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_payroll" IS 'Merged payroll data imported from external payroll processor. One row per employee per check date. Employee fields are snapshotted at time of processing to preserve historical accuracy.';



COMMENT ON COLUMN "public"."hr_payroll"."payroll_id" IS 'Employee ID as it appears in the payroll processor system; used to match records during import';



COMMENT ON COLUMN "public"."hr_payroll"."payroll_processor" IS 'Payroll processor identifier (e.g. HRB, HF)';



COMMENT ON COLUMN "public"."hr_payroll"."is_standard" IS 'Auto-set: true if invoice total hours > 5000; false for off-cycle or adjustment runs';



COMMENT ON COLUMN "public"."hr_payroll"."employee_name" IS 'Name as it appears in the payroll processor data; hr_employee_id is matched by the import script';



COMMENT ON COLUMN "public"."hr_payroll"."hr_department_id" IS 'Snapshot from hr_employee.hr_department_id at time of import';



COMMENT ON COLUMN "public"."hr_payroll"."hr_work_authorization_id" IS 'Snapshot from hr_employee.hr_work_authorization_id at time of import';



COMMENT ON COLUMN "public"."hr_payroll"."wc" IS 'Snapshot from hr_employee.wc at time of import';



COMMENT ON COLUMN "public"."hr_payroll"."pay_structure" IS 'Snapshot from hr_employee.pay_structure at time of import';



COMMENT ON COLUMN "public"."hr_payroll"."hourly_rate" IS 'Snapshot from payroll processor NetPay data';



COMMENT ON COLUMN "public"."hr_payroll"."overtime_threshold" IS 'Snapshot from hr_employee.overtime_threshold at time of import';



COMMENT ON COLUMN "public"."hr_payroll"."discretionary_overtime_hours" IS 'Premium OT hours paid at employer discretion above statutory OT threshold; distinct from overtime_hours which covers legally-mandated OT';



COMMENT ON COLUMN "public"."hr_payroll"."discretionary_overtime_pay" IS 'Pay amount corresponding to discretionary_overtime_hours';



COMMENT ON COLUMN "public"."hr_payroll"."fit" IS 'Federal Income Tax withheld';



COMMENT ON COLUMN "public"."hr_payroll"."sit" IS 'State Income Tax withheld';



COMMENT ON COLUMN "public"."hr_payroll"."hawaii_get" IS 'Hawaii General Excise Tax';



COMMENT ON COLUMN "public"."hr_payroll"."tdi" IS 'Temporary Disability Insurance — employer portion';



CREATE TABLE IF NOT EXISTS "public"."ops_task" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "description" "text",
    "qb_account" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_task" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_task" IS 'Flat task catalog for labor tracking. Tasks can be org-wide or scoped to a specific farm.';



CREATE TABLE IF NOT EXISTS "public"."ops_task_schedule" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_task_id" "text" NOT NULL,
    "ops_task_tracker_id" "uuid",
    "hr_employee_id" "text" NOT NULL,
    "start_time" timestamp without time zone NOT NULL,
    "stop_time" timestamp without time zone,
    "total_hours" numeric,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_task_schedule" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_task_schedule" IS 'Employee task assignments for both planning and execution. When ops_task_tracker_id is null, the row is a planned schedule entry. When set, it is an executed activity. ops_task_id is always set — derived from the tracker when linked, or selected by the user for planned entries.';



COMMENT ON COLUMN "public"."ops_task_schedule"."farm_id" IS 'Inherited from ops_task_tracker.farm_id when linked to a tracker; user-selected for planned entries';



COMMENT ON COLUMN "public"."ops_task_schedule"."ops_task_id" IS 'Inherited from ops_task_tracker.ops_task_id when linked to a tracker; user-selected for planned entries';



COMMENT ON COLUMN "public"."ops_task_schedule"."start_time" IS 'Wall-clock shift start (no time zone). Inherited from ops_task_tracker.start_time when linked; user-picked otherwise.';



COMMENT ON COLUMN "public"."ops_task_schedule"."stop_time" IS 'Wall-clock shift end (no time zone). Inherited from ops_task_tracker.stop_time when linked; user-picked otherwise.';



CREATE OR REPLACE VIEW "public"."hr_payroll_by_task" WITH ("security_invoker"='true') AS
 WITH "payroll_agg" AS (
         SELECT "p"."org_id",
            "p"."hr_employee_id",
            "p"."check_date",
            "p"."pay_period_start",
            "p"."pay_period_end",
            "p"."hr_department_id",
            "p"."hr_work_authorization_id",
            "p"."wc",
            "sum"("p"."total_hours") AS "total_hours",
            "sum"("p"."regular_hours") AS "regular_hours",
            "sum"("p"."pto_hours") AS "pto_hours",
            "sum"("p"."discretionary_overtime_hours") AS "discretionary_overtime_hours",
            "sum"("p"."total_cost") AS "total_cost",
            "sum"("p"."regular_pay") AS "regular_pay",
            "sum"("p"."discretionary_overtime_pay") AS "discretionary_overtime_pay"
           FROM "public"."hr_payroll" "p"
          WHERE ((NOT "p"."is_deleted") AND ("p"."check_date" >= '2025-01-01'::"date") AND ("p"."payroll_processor" = 'HRB'::"text"))
          GROUP BY "p"."org_id", "p"."hr_employee_id", "p"."check_date", "p"."pay_period_start", "p"."pay_period_end", "p"."hr_department_id", "p"."hr_work_authorization_id", "p"."wc"
        ), "sched_by_acct" AS (
         SELECT "pa"."hr_employee_id",
            "pa"."check_date",
            COALESCE("t"."qb_account", "pa"."hr_department_id") AS "acct",
            "sum"(COALESCE("s"."total_hours", (EXTRACT(epoch FROM ("s"."stop_time" - "s"."start_time")) / 3600.0))) AS "scheduled_hours"
           FROM (("payroll_agg" "pa"
             JOIN "public"."ops_task_schedule" "s" ON ((("s"."org_id" = "pa"."org_id") AND ("s"."hr_employee_id" = "pa"."hr_employee_id") AND ((("s"."start_time")::"date" >= "pa"."pay_period_start") AND (("s"."start_time")::"date" <= "pa"."pay_period_end")) AND (NOT "s"."is_deleted"))))
             LEFT JOIN "public"."ops_task" "t" ON (("t"."id" = "s"."ops_task_id")))
          GROUP BY "pa"."hr_employee_id", "pa"."check_date", COALESCE("t"."qb_account", "pa"."hr_department_id")
        ), "sched_totals" AS (
         SELECT "sched_by_acct"."hr_employee_id",
            "sched_by_acct"."check_date",
            "sum"("sched_by_acct"."scheduled_hours") AS "sched_total"
           FROM "sched_by_acct"
          GROUP BY "sched_by_acct"."hr_employee_id", "sched_by_acct"."check_date"
        ), "with_schedule" AS (
         SELECT "pa"."org_id",
            "pa"."hr_employee_id",
            "pa"."check_date",
            "pa"."pay_period_start",
            "pa"."pay_period_end",
            "pa"."hr_department_id",
            "pa"."hr_work_authorization_id",
            "pa"."wc",
            "pa"."total_hours",
            "pa"."regular_hours",
            "pa"."pto_hours",
            "pa"."discretionary_overtime_hours",
            "pa"."total_cost",
            "pa"."regular_pay",
            "pa"."discretionary_overtime_pay",
            "sa"."acct",
            "sa"."scheduled_hours",
            "st"."sched_total"
           FROM (("payroll_agg" "pa"
             JOIN "sched_by_acct" "sa" ON ((("sa"."hr_employee_id" = "pa"."hr_employee_id") AND ("sa"."check_date" = "pa"."check_date"))))
             JOIN "sched_totals" "st" ON ((("st"."hr_employee_id" = "pa"."hr_employee_id") AND ("st"."check_date" = "pa"."check_date"))))
        ), "without_schedule" AS (
         SELECT "pa"."org_id",
            "pa"."hr_employee_id",
            "pa"."check_date",
            "pa"."pay_period_start",
            "pa"."pay_period_end",
            "pa"."hr_department_id",
            "pa"."hr_work_authorization_id",
            "pa"."wc",
            "pa"."total_hours",
            "pa"."regular_hours",
            "pa"."pto_hours",
            "pa"."discretionary_overtime_hours",
            "pa"."total_cost",
            "pa"."regular_pay",
            "pa"."discretionary_overtime_pay",
            "pa"."hr_department_id" AS "acct",
            (0)::numeric AS "scheduled_hours",
            NULL::numeric AS "sched_total"
           FROM "payroll_agg" "pa"
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM "sched_by_acct" "sa"
                  WHERE (("sa"."hr_employee_id" = "pa"."hr_employee_id") AND ("sa"."check_date" = "pa"."check_date")))))
        ), "allocated" AS (
         SELECT "with_schedule"."org_id",
            "with_schedule"."hr_employee_id",
            "with_schedule"."check_date",
            "with_schedule"."pay_period_start",
            "with_schedule"."pay_period_end",
            "with_schedule"."hr_department_id",
            "with_schedule"."hr_work_authorization_id",
            "with_schedule"."wc",
            "with_schedule"."total_hours",
            "with_schedule"."regular_hours",
            "with_schedule"."pto_hours",
            "with_schedule"."discretionary_overtime_hours",
            "with_schedule"."total_cost",
            "with_schedule"."regular_pay",
            "with_schedule"."discretionary_overtime_pay",
            "with_schedule"."acct",
            "with_schedule"."scheduled_hours",
            "with_schedule"."sched_total"
           FROM "with_schedule"
        UNION ALL
         SELECT "without_schedule"."org_id",
            "without_schedule"."hr_employee_id",
            "without_schedule"."check_date",
            "without_schedule"."pay_period_start",
            "without_schedule"."pay_period_end",
            "without_schedule"."hr_department_id",
            "without_schedule"."hr_work_authorization_id",
            "without_schedule"."wc",
            "without_schedule"."total_hours",
            "without_schedule"."regular_hours",
            "without_schedule"."pto_hours",
            "without_schedule"."discretionary_overtime_hours",
            "without_schedule"."total_cost",
            "without_schedule"."regular_pay",
            "without_schedule"."discretionary_overtime_pay",
            "without_schedule"."acct",
            "without_schedule"."scheduled_hours",
            "without_schedule"."sched_total"
           FROM "without_schedule"
        )
 SELECT "a"."org_id",
    "a"."hr_employee_id",
    "a"."check_date",
    "e"."compensation_manager_id",
    "a"."hr_work_authorization_id" AS "status",
    "a"."wc" AS "workers_compensation_code",
    "a"."acct" AS "task",
    "round"("a"."scheduled_hours", 2) AS "scheduled_hours",
    "round"(
        CASE
            WHEN (("a"."sched_total" IS NULL) AND ("a"."total_hours" = (0)::numeric) AND ("a"."pto_hours" > (0)::numeric)) THEN "a"."pto_hours"
            WHEN ("a"."sched_total" IS NULL) THEN "a"."total_hours"
            WHEN ("a"."sched_total" > (0)::numeric) THEN (("a"."total_hours" * "a"."scheduled_hours") / "a"."sched_total")
            ELSE (0)::numeric
        END, 2) AS "total_hours",
    "round"(
        CASE
            WHEN ("a"."sched_total" IS NULL) THEN "a"."regular_hours"
            WHEN ("a"."sched_total" > (0)::numeric) THEN (("a"."regular_hours" * "a"."scheduled_hours") / "a"."sched_total")
            ELSE (0)::numeric
        END, 2) AS "regular_hours",
    "round"(
        CASE
            WHEN ("a"."sched_total" IS NULL) THEN "a"."discretionary_overtime_hours"
            WHEN ("a"."sched_total" > (0)::numeric) THEN (("a"."discretionary_overtime_hours" * "a"."scheduled_hours") / "a"."sched_total")
            ELSE (0)::numeric
        END, 2) AS "discretionary_overtime_hours",
    "round"(
        CASE
            WHEN ("a"."sched_total" IS NULL) THEN "a"."total_cost"
            WHEN ("a"."sched_total" > (0)::numeric) THEN (("a"."total_cost" * "a"."scheduled_hours") / "a"."sched_total")
            ELSE "a"."total_cost"
        END, 2) AS "total_cost",
    "round"(
        CASE
            WHEN ("a"."sched_total" IS NULL) THEN "a"."regular_pay"
            WHEN ("a"."sched_total" > (0)::numeric) THEN (("a"."regular_pay" * "a"."scheduled_hours") / "a"."sched_total")
            ELSE (0)::numeric
        END, 2) AS "regular_pay",
    "round"(
        CASE
            WHEN ("a"."sched_total" IS NULL) THEN "a"."discretionary_overtime_pay"
            WHEN ("a"."sched_total" > (0)::numeric) THEN (("a"."discretionary_overtime_pay" * "a"."scheduled_hours") / "a"."sched_total")
            ELSE (0)::numeric
        END, 2) AS "discretionary_overtime_pay"
   FROM ("allocated" "a"
     JOIN "public"."hr_employee" "e" ON (("e"."id" = "a"."hr_employee_id")));


ALTER VIEW "public"."hr_payroll_by_task" OWNER TO "postgres";


COMMENT ON VIEW "public"."hr_payroll_by_task" IS 'Replicates the legacy payrollSchedComparison GAS output: payroll totals split across QuickBooks accounts proportionally to scheduled hours per pay period. Scheduled hours column is raw (unscaled) so variance vs paid can be computed downstream.';



CREATE OR REPLACE VIEW "public"."hr_payroll_data_secure" WITH ("security_invoker"='true') AS
 SELECT "id",
    "org_id",
    "hr_employee_id",
    "payroll_id",
    "pay_period_start",
    "pay_period_end",
    "check_date",
    "invoice_number",
    "payroll_processor",
    "is_standard",
    "employee_name",
    "hr_department_id",
    "hr_work_authorization_id",
    "wc",
    "pay_structure",
    "overtime_threshold",
    "regular_hours",
    "overtime_hours",
    "discretionary_overtime_hours",
    "holiday_hours",
    "pto_hours",
    "sick_hours",
    "funeral_hours",
    "total_hours",
    "pto_hours_accrued",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "hourly_rate"
        END AS "hourly_rate",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "regular_pay"
        END AS "regular_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "overtime_pay"
        END AS "overtime_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "discretionary_overtime_pay"
        END AS "discretionary_overtime_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "holiday_pay"
        END AS "holiday_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "pto_pay"
        END AS "pto_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "sick_pay"
        END AS "sick_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "funeral_pay"
        END AS "funeral_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "other_pay"
        END AS "other_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "bonus_pay"
        END AS "bonus_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "auto_allowance"
        END AS "auto_allowance",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "per_diem"
        END AS "per_diem",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "salary"
        END AS "salary",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "gross_wage"
        END AS "gross_wage",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "fit"
        END AS "fit",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "sit"
        END AS "sit",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "social_security"
        END AS "social_security",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "medicare"
        END AS "medicare",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "comp_plus"
        END AS "comp_plus",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "hds_dental"
        END AS "hds_dental",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "pre_tax_401k"
        END AS "pre_tax_401k",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "auto_deduction"
        END AS "auto_deduction",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "child_support"
        END AS "child_support",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "program_fees"
        END AS "program_fees",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "net_pay"
        END AS "net_pay",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "labor_tax"
        END AS "labor_tax",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "other_tax"
        END AS "other_tax",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "workers_compensation"
        END AS "workers_compensation",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "health_benefits"
        END AS "health_benefits",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "other_health_charges"
        END AS "other_health_charges",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "admin_fees"
        END AS "admin_fees",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "hawaii_get"
        END AS "hawaii_get",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "other_charges"
        END AS "other_charges",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "tdi"
        END AS "tdi",
        CASE
            WHEN ("public"."auth_access_level"("org_id") = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "total_cost"
        END AS "total_cost",
    "created_at",
    "created_by",
    "updated_at",
    "updated_by",
    "is_deleted"
   FROM "public"."hr_payroll"
  WHERE (("is_deleted" = false) AND (("public"."auth_access_level"("org_id") = ANY (ARRAY['Owner'::"text", 'Admin'::"text", 'Team Lead'::"text"])) OR (("public"."auth_access_level"("org_id") = 'Manager'::"text") AND (("hr_employee_id" = "public"."auth_employee_id"("org_id")) OR (EXISTS ( SELECT 1
           FROM "public"."hr_employee" "e"
          WHERE (("e"."id" = "hr_payroll"."hr_employee_id") AND ("e"."compensation_manager_id" = "public"."auth_employee_id"("e"."org_id")))))))));


ALTER VIEW "public"."hr_payroll_data_secure" OWNER TO "postgres";


COMMENT ON VIEW "public"."hr_payroll_data_secure" IS 'RBAC-gated wrapper over hr_payroll for the Payroll Data sub-module: row scope per access level (Owner/Admin/Team Lead see all; Manager sees direct reports + self), $ columns NULL for Team Lead. Reads via security_invoker so existing org-isolation RLS still applies. Frontend (hr-payroll-data.config.tsx views.list) reads this instead of the base table.';



CREATE OR REPLACE VIEW "public"."hr_payroll_employee_comparison" WITH ("security_invoker"='true') AS
 WITH "standard_dates" AS (
         SELECT DISTINCT "hr_payroll"."check_date"
           FROM "public"."hr_payroll"
          WHERE (("hr_payroll"."is_standard" = true) AND ("hr_payroll"."payroll_processor" = 'HRB'::"text") AND (NOT "hr_payroll"."is_deleted"))
        ), "ranked_dates" AS (
         SELECT "standard_dates"."check_date",
            "dense_rank"() OVER (ORDER BY "standard_dates"."check_date" DESC) AS "rnk"
           FROM "standard_dates"
        ), "periods" AS (
         SELECT "max"("ranked_dates"."check_date") FILTER (WHERE ("ranked_dates"."rnk" = 1)) AS "cur_date",
            "max"("ranked_dates"."check_date") FILTER (WHERE ("ranked_dates"."rnk" = 2)) AS "prev_date"
           FROM "ranked_dates"
        ), "current_p" AS (
         SELECT "v"."org_id",
            "v"."hr_employee_id",
            "max"("v"."compensation_manager_id") AS "compensation_manager_id",
            "max"("v"."status") AS "status",
            "max"("v"."workers_compensation_code") AS "workers_compensation_code",
            "sum"("v"."scheduled_hours") AS "scheduled_hours",
            "sum"("v"."total_hours") AS "total_hours",
            "sum"("v"."total_cost") AS "total_cost",
            "sum"("v"."regular_pay") AS "regular_pay",
            "sum"("v"."discretionary_overtime_hours") AS "discretionary_overtime_hours",
            "sum"("v"."discretionary_overtime_pay") AS "discretionary_overtime_pay"
           FROM "public"."hr_payroll_by_task" "v",
            "periods" "p"
          WHERE ("v"."check_date" = "p"."cur_date")
          GROUP BY "v"."org_id", "v"."hr_employee_id"
        ), "previous_p" AS (
         SELECT "v"."org_id",
            "v"."hr_employee_id",
            "max"("v"."compensation_manager_id") AS "compensation_manager_id",
            "max"("v"."status") AS "status",
            "max"("v"."workers_compensation_code") AS "workers_compensation_code",
            "sum"("v"."scheduled_hours") AS "scheduled_hours",
            "sum"("v"."total_hours") AS "total_hours",
            "sum"("v"."total_cost") AS "total_cost",
            "sum"("v"."regular_pay") AS "regular_pay",
            "sum"("v"."discretionary_overtime_hours") AS "discretionary_overtime_hours",
            "sum"("v"."discretionary_overtime_pay") AS "discretionary_overtime_pay"
           FROM "public"."hr_payroll_by_task" "v",
            "periods" "p"
          WHERE ("v"."check_date" = "p"."prev_date")
          GROUP BY "v"."org_id", "v"."hr_employee_id"
        )
 SELECT COALESCE("c"."org_id", "pr"."org_id") AS "org_id",
    COALESCE("c"."hr_employee_id", "pr"."hr_employee_id") AS "hr_employee_id",
    TRIM(BOTH FROM (("e"."first_name" || ' '::"text") || "e"."last_name")) AS "employee_full_name",
    COALESCE("c"."compensation_manager_id", "pr"."compensation_manager_id") AS "compensation_manager_id",
    COALESCE("c"."status", "pr"."status") AS "status",
    COALESCE("c"."workers_compensation_code", "pr"."workers_compensation_code") AS "workers_compensation_code",
    ( SELECT "periods"."cur_date"
           FROM "periods") AS "check_date",
    "round"(COALESCE("c"."scheduled_hours", (0)::numeric)) AS "scheduled_hours",
    "round"(COALESCE("c"."total_hours", (0)::numeric)) AS "total_hours",
    "round"((COALESCE("c"."scheduled_hours", (0)::numeric) - COALESCE("c"."total_hours", (0)::numeric))) AS "hours_variance",
    "round"(COALESCE("c"."discretionary_overtime_hours", (0)::numeric)) AS "discretionary_overtime_hours",
    "round"((COALESCE("c"."total_hours", (0)::numeric) - COALESCE("pr"."total_hours", (0)::numeric))) AS "hours_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"(COALESCE("c"."total_cost", (0)::numeric))
        END AS "total_cost",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"(COALESCE("c"."regular_pay", (0)::numeric))
        END AS "regular_pay",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"(COALESCE("c"."discretionary_overtime_pay", (0)::numeric))
        END AS "discretionary_overtime_pay",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((COALESCE("c"."total_cost", (0)::numeric) - COALESCE("pr"."total_cost", (0)::numeric)))
        END AS "total_cost_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((COALESCE("c"."regular_pay", (0)::numeric) - COALESCE("pr"."regular_pay", (0)::numeric)))
        END AS "regular_pay_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((COALESCE("c"."discretionary_overtime_pay", (0)::numeric) - COALESCE("pr"."discretionary_overtime_pay", (0)::numeric)))
        END AS "discretionary_overtime_pay_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((((COALESCE("c"."total_cost", (0)::numeric) - COALESCE("pr"."total_cost", (0)::numeric)) - (COALESCE("c"."regular_pay", (0)::numeric) - COALESCE("pr"."regular_pay", (0)::numeric))) - (COALESCE("c"."discretionary_overtime_pay", (0)::numeric) - COALESCE("pr"."discretionary_overtime_pay", (0)::numeric))))
        END AS "other_pay_delta"
   FROM (("current_p" "c"
     FULL JOIN "previous_p" "pr" ON ((("pr"."org_id" = "c"."org_id") AND ("pr"."hr_employee_id" = "c"."hr_employee_id"))))
     LEFT JOIN "public"."hr_employee" "e" ON ((("e"."org_id" = COALESCE("c"."org_id", "pr"."org_id")) AND ("e"."id" = COALESCE("c"."hr_employee_id", "pr"."hr_employee_id")))))
  WHERE (("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = ANY (ARRAY['Owner'::"text", 'Admin'::"text", 'Team Lead'::"text"])) OR (("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Manager'::"text") AND ((COALESCE("c"."compensation_manager_id", "pr"."compensation_manager_id") = "public"."auth_employee_id"(COALESCE("c"."org_id", "pr"."org_id"))) OR (COALESCE("c"."hr_employee_id", "pr"."hr_employee_id") = "public"."auth_employee_id"(COALESCE("c"."org_id", "pr"."org_id"))))));


ALTER VIEW "public"."hr_payroll_employee_comparison" OWNER TO "postgres";


COMMENT ON VIEW "public"."hr_payroll_employee_comparison" IS 'Per-employee snapshot (one row per employee, aggregated across tasks) for the most recent is_standard=TRUE HRB check_date with deltas vs the prior is_standard=TRUE check_date. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees direct reports + self; Team Lead has $ columns NULL-masked. Org isolation via security_invoker.';



CREATE OR REPLACE VIEW "public"."hr_payroll_task_comparison" WITH ("security_invoker"='true') AS
 WITH "standard_dates" AS (
         SELECT DISTINCT "hr_payroll"."check_date"
           FROM "public"."hr_payroll"
          WHERE (("hr_payroll"."is_standard" = true) AND ("hr_payroll"."payroll_processor" = 'HRB'::"text") AND (NOT "hr_payroll"."is_deleted"))
        ), "ranked_dates" AS (
         SELECT "standard_dates"."check_date",
            "dense_rank"() OVER (ORDER BY "standard_dates"."check_date" DESC) AS "rnk"
           FROM "standard_dates"
        ), "periods" AS (
         SELECT "max"("ranked_dates"."check_date") FILTER (WHERE ("ranked_dates"."rnk" = 1)) AS "cur_date",
            "max"("ranked_dates"."check_date") FILTER (WHERE ("ranked_dates"."rnk" = 2)) AS "prev_date"
           FROM "ranked_dates"
        ), "current_p" AS (
         SELECT "v"."org_id",
            "v"."compensation_manager_id",
            "v"."task",
            "v"."status",
            "sum"("v"."scheduled_hours") AS "scheduled_hours",
            "sum"("v"."total_hours") AS "total_hours",
            "sum"("v"."total_cost") AS "total_cost",
            "sum"("v"."regular_pay") AS "regular_pay",
            "sum"("v"."discretionary_overtime_hours") AS "discretionary_overtime_hours",
            "sum"("v"."discretionary_overtime_pay") AS "discretionary_overtime_pay"
           FROM "public"."hr_payroll_by_task" "v",
            "periods" "p"
          WHERE ("v"."check_date" = "p"."cur_date")
          GROUP BY "v"."org_id", "v"."compensation_manager_id", "v"."task", "v"."status"
        ), "previous_p" AS (
         SELECT "v"."org_id",
            "v"."compensation_manager_id",
            "v"."task",
            "v"."status",
            "sum"("v"."scheduled_hours") AS "scheduled_hours",
            "sum"("v"."total_hours") AS "total_hours",
            "sum"("v"."total_cost") AS "total_cost",
            "sum"("v"."regular_pay") AS "regular_pay",
            "sum"("v"."discretionary_overtime_hours") AS "discretionary_overtime_hours",
            "sum"("v"."discretionary_overtime_pay") AS "discretionary_overtime_pay"
           FROM "public"."hr_payroll_by_task" "v",
            "periods" "p"
          WHERE ("v"."check_date" = "p"."prev_date")
          GROUP BY "v"."org_id", "v"."compensation_manager_id", "v"."task", "v"."status"
        )
 SELECT COALESCE("c"."org_id", "pr"."org_id") AS "org_id",
    COALESCE("c"."compensation_manager_id", "pr"."compensation_manager_id") AS "compensation_manager_id",
    "m"."preferred_name" AS "compensation_manager_alias",
    COALESCE("c"."task", "pr"."task") AS "task",
    COALESCE("c"."status", "pr"."status") AS "status",
    ( SELECT "periods"."cur_date"
           FROM "periods") AS "check_date",
    "round"(COALESCE("c"."scheduled_hours", (0)::numeric)) AS "scheduled_hours",
    "round"(COALESCE("c"."total_hours", (0)::numeric)) AS "total_hours",
    "round"((COALESCE("c"."scheduled_hours", (0)::numeric) - COALESCE("c"."total_hours", (0)::numeric))) AS "hours_variance",
    "round"(COALESCE("c"."discretionary_overtime_hours", (0)::numeric)) AS "discretionary_overtime_hours",
    "round"((COALESCE("c"."total_hours", (0)::numeric) - COALESCE("pr"."total_hours", (0)::numeric))) AS "hours_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"(COALESCE("c"."total_cost", (0)::numeric))
        END AS "total_cost",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"(COALESCE("c"."regular_pay", (0)::numeric))
        END AS "regular_pay",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"(COALESCE("c"."discretionary_overtime_pay", (0)::numeric))
        END AS "discretionary_overtime_pay",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((COALESCE("c"."total_cost", (0)::numeric) - COALESCE("pr"."total_cost", (0)::numeric)))
        END AS "total_cost_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((COALESCE("c"."regular_pay", (0)::numeric) - COALESCE("pr"."regular_pay", (0)::numeric)))
        END AS "regular_pay_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((COALESCE("c"."discretionary_overtime_pay", (0)::numeric) - COALESCE("pr"."discretionary_overtime_pay", (0)::numeric)))
        END AS "discretionary_overtime_pay_delta",
        CASE
            WHEN ("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Team Lead'::"text") THEN NULL::numeric
            ELSE "round"((((COALESCE("c"."total_cost", (0)::numeric) - COALESCE("pr"."total_cost", (0)::numeric)) - (COALESCE("c"."regular_pay", (0)::numeric) - COALESCE("pr"."regular_pay", (0)::numeric))) - (COALESCE("c"."discretionary_overtime_pay", (0)::numeric) - COALESCE("pr"."discretionary_overtime_pay", (0)::numeric))))
        END AS "other_pay_delta"
   FROM (("current_p" "c"
     FULL JOIN "previous_p" "pr" ON ((("pr"."org_id" = "c"."org_id") AND (NOT ("pr"."compensation_manager_id" IS DISTINCT FROM "c"."compensation_manager_id")) AND ("pr"."task" = "c"."task") AND ("pr"."status" = "c"."status"))))
     LEFT JOIN "public"."hr_employee" "m" ON ((("m"."org_id" = COALESCE("c"."org_id", "pr"."org_id")) AND ("m"."id" = COALESCE("c"."compensation_manager_id", "pr"."compensation_manager_id")))))
  WHERE (("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = ANY (ARRAY['Owner'::"text", 'Admin'::"text", 'Team Lead'::"text"])) OR (("public"."auth_access_level"(COALESCE("c"."org_id", "pr"."org_id")) = 'Manager'::"text") AND (COALESCE("c"."compensation_manager_id", "pr"."compensation_manager_id") = "public"."auth_employee_id"(COALESCE("c"."org_id", "pr"."org_id")))));


ALTER VIEW "public"."hr_payroll_task_comparison" OWNER TO "postgres";


COMMENT ON VIEW "public"."hr_payroll_task_comparison" IS 'Per-task (no employee dimension) snapshot for the most recent is_standard=TRUE HRB check_date with deltas vs the prior period. RBAC-gated: Owner/Admin/Team Lead see all rows; Manager sees only rows where they are the compensation manager; Team Lead has $ columns NULL-masked.';



CREATE TABLE IF NOT EXISTS "public"."org_module" (
    "org_id" "text" NOT NULL,
    "sys_module_id" "text" NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_module" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_module" IS 'Org-scoped copy of system modules. Seeded when a new org is created. Org admins toggle is_enabled to control which modules are available to their users.';



COMMENT ON COLUMN "public"."org_module"."sys_module_id" IS 'Sourced from sys_module; identifies which system module this org copy represents';



COMMENT ON COLUMN "public"."org_module"."is_enabled" IS 'Auto-set to true when provisioned; toggled by org admins to enable/disable the module';



CREATE TABLE IF NOT EXISTS "public"."org_sub_module" (
    "org_id" "text" NOT NULL,
    "sys_module_id" "text" NOT NULL,
    "sys_sub_module_id" "text" NOT NULL,
    "sys_access_level_id" "text" NOT NULL,
    "is_enabled" boolean DEFAULT true NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_sub_module" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_sub_module" IS 'Org-scoped copy of system sub-modules. Seeded when a new org is created. Org admins toggle is_enabled to control which sub-modules are available within each enabled module. Composite PK (org_id, sys_sub_module_id) lets every org reuse the same canonical sys_sub_module ids without ID-namespace collisions. Note: "Packlot" was retired on 2026-05-18 when pack_lot table was dropped; rows are kept with is_enabled=false to preserve audit history.';



COMMENT ON COLUMN "public"."org_sub_module"."sys_module_id" IS 'Sourced from sys_sub_module.sys_module_id at provisioning time';



COMMENT ON COLUMN "public"."org_sub_module"."sys_sub_module_id" IS 'Sourced from sys_sub_module; identifies which system sub-module this org copy represents';



COMMENT ON COLUMN "public"."org_sub_module"."sys_access_level_id" IS 'Pre-filled from sys_sub_module.sys_access_level_id at provisioning time; editable by org admins';



COMMENT ON COLUMN "public"."org_sub_module"."is_enabled" IS 'Auto-set to true when provisioned; toggled by org admins to enable/disable the sub-module';



CREATE TABLE IF NOT EXISTS "public"."sys_access_level" (
    "id" "text" NOT NULL,
    "level" integer NOT NULL,
    "description" "text",
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sys_access_level" OWNER TO "postgres";


COMMENT ON TABLE "public"."sys_access_level" IS 'System-level lookup defining the access levels available for employee roles. The level integer is used to compare against sys_sub_module.sys_access_level_id for visibility control.';



COMMENT ON COLUMN "public"."sys_access_level"."id" IS 'Human-readable identifier (e.g. employee, team_lead, manager, admin, owner)';



CREATE TABLE IF NOT EXISTS "public"."sys_module" (
    "id" "text" NOT NULL,
    "description" "text",
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sys_module" OWNER TO "postgres";


COMMENT ON TABLE "public"."sys_module" IS 'System-level lookup defining the application modules available for access control (e.g. Inventory, HR, Operations, Pack, Sales, Maintenance, Food Safety).';



COMMENT ON COLUMN "public"."sys_module"."id" IS 'Human-readable identifier derived from module name (e.g. inventory, human_resources)';



CREATE TABLE IF NOT EXISTS "public"."sys_sub_module" (
    "id" "text" NOT NULL,
    "sys_module_id" "text" NOT NULL,
    "description" "text",
    "sys_access_level_id" "text" NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sys_sub_module" OWNER TO "postgres";


COMMENT ON TABLE "public"."sys_sub_module" IS 'System-level lookup defining sub-modules within each module. sys_access_level_id determines the minimum employee access level required to see this sub-module.';



COMMENT ON COLUMN "public"."sys_sub_module"."sys_access_level_id" IS 'Sourced from sys_access_level; defines the minimum access level required to view this sub-module';



CREATE OR REPLACE VIEW "public"."hr_rba_navigation" WITH ("security_invoker"='true') AS
 SELECT "om"."org_id",
    "om"."sys_module_id" AS "module_id",
    "om"."display_order" AS "module_display_order",
    "osm"."sys_sub_module_id" AS "sub_module_id",
    "osm"."display_order" AS "sub_module_display_order",
    "ma"."can_edit",
    "ma"."can_delete",
    "ma"."can_verify"
   FROM ((((((("public"."hr_employee" "e"
     JOIN "public"."sys_access_level" "emp_al" ON (("emp_al"."id" = "e"."sys_access_level_id")))
     JOIN "public"."org_sub_module" "osm" ON (("osm"."org_id" = "e"."org_id")))
     JOIN "public"."org_module" "om" ON ((("om"."org_id" = "osm"."org_id") AND ("om"."sys_module_id" = "osm"."sys_module_id"))))
     JOIN "public"."sys_module" "sm" ON (("sm"."id" = "osm"."sys_module_id")))
     JOIN "public"."sys_sub_module" "ssm" ON (("ssm"."id" = "osm"."sys_sub_module_id")))
     JOIN "public"."sys_access_level" "req_al" ON (("req_al"."id" = "osm"."sys_access_level_id")))
     JOIN "public"."hr_module_access" "ma" ON ((("ma"."hr_employee_id" = "e"."id") AND ("ma"."org_id" = "om"."org_id") AND ("ma"."sys_module_id" = "om"."sys_module_id"))))
  WHERE (("e"."user_id" = "auth"."uid"()) AND ("e"."is_deleted" = false) AND ("om"."is_enabled" = true) AND ("om"."is_deleted" = false) AND ("osm"."is_enabled" = true) AND ("osm"."is_deleted" = false) AND ("ma"."is_enabled" = true) AND ("ma"."is_deleted" = false) AND ("emp_al"."level" >= "req_al"."level"));


ALTER VIEW "public"."hr_rba_navigation" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."hr_staffing_pp_detail_v" WITH ("security_invoker"='false') AS
 WITH "ranked" AS (
         SELECT (EXTRACT(year FROM "p"."check_date"))::integer AS "year",
            "dense_rank"() OVER (PARTITION BY (EXTRACT(year FROM "p"."check_date")) ORDER BY "p"."check_date") AS "pp",
            "p"."check_date",
                CASE "p"."hr_work_authorization_id"
                    WHEN 'Local'::"text" THEN 'local'::"text"
                    WHEN 'WFE'::"text" THEN 'wfe'::"text"
                    WHEN 'H2A'::"text" THEN 'h2a'::"text"
                    WHEN 'FUERTE (Local)'::"text" THEN 'f_local'::"text"
                    WHEN 'FUERTE'::"text" THEN 'fuerte'::"text"
                    ELSE NULL::"text"
                END AS "labor_type",
            "p"."employee_name",
            "p"."hr_department_id",
            "p"."hr_work_authorization_id",
            "p"."total_hours",
            "p"."total_cost",
            "p"."gross_wage"
           FROM ("public"."hr_payroll" "p"
             LEFT JOIN "public"."hr_employee" "e" ON (("e"."id" = "p"."hr_employee_id")))
          WHERE (("p"."is_deleted" = false) AND ("p"."is_standard" = true) AND ("p"."hr_work_authorization_id" = ANY (ARRAY['Local'::"text", 'WFE'::"text", 'H2A'::"text", 'FUERTE (Local)'::"text", 'FUERTE'::"text"])) AND ("p"."hr_department_id" IS DISTINCT FROM 'Maintenance'::"text") AND ("e"."compensation_manager_id" IS NOT NULL) AND ("e"."compensation_manager_id" <> ALL (ARRAY['feder_leonard'::"text", 'cervantes_acosta_eric_abraham'::"text", 'batha_eric'::"text"])))
        )
 SELECT "year",
    ("pp")::integer AS "pp",
    "check_date",
    "labor_type",
    "employee_name",
    "hr_department_id",
    "hr_work_authorization_id",
    "total_hours",
    "total_cost",
    "gross_wage"
   FROM "ranked";


ALTER VIEW "public"."hr_staffing_pp_detail_v" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."hr_staffing_pp_v" WITH ("security_invoker"='false') AS
 WITH "ranked" AS (
         SELECT (EXTRACT(year FROM "p"."check_date"))::integer AS "year",
            "dense_rank"() OVER (PARTITION BY (EXTRACT(year FROM "p"."check_date")) ORDER BY "p"."check_date") AS "pp",
            "p"."check_date",
                CASE "p"."hr_work_authorization_id"
                    WHEN 'Local'::"text" THEN 'local'::"text"
                    WHEN 'WFE'::"text" THEN 'wfe'::"text"
                    WHEN 'H2A'::"text" THEN 'h2a'::"text"
                    WHEN 'FUERTE (Local)'::"text" THEN 'f_local'::"text"
                    WHEN 'FUERTE'::"text" THEN 'fuerte'::"text"
                    ELSE NULL::"text"
                END AS "labor_type",
            "p"."hr_employee_id",
            "p"."total_hours",
            "p"."total_cost",
            "p"."gross_wage",
            "p"."discretionary_overtime_hours"
           FROM ("public"."hr_payroll" "p"
             LEFT JOIN "public"."hr_employee" "e" ON (("e"."id" = "p"."hr_employee_id")))
          WHERE (("p"."is_deleted" = false) AND ("p"."is_standard" = true) AND ("p"."hr_work_authorization_id" = ANY (ARRAY['Local'::"text", 'WFE'::"text", 'H2A'::"text", 'FUERTE (Local)'::"text", 'FUERTE'::"text"])) AND ("p"."hr_department_id" IS DISTINCT FROM 'Maintenance'::"text") AND ("e"."compensation_manager_id" IS NOT NULL) AND ("e"."compensation_manager_id" <> ALL (ARRAY['feder_leonard'::"text", 'cervantes_acosta_eric_abraham'::"text", 'batha_eric'::"text"])))
        )
 SELECT "year",
    ("pp")::integer AS "pp",
    "min"("check_date") AS "check_date",
    "labor_type",
    ("count"(DISTINCT "hr_employee_id"))::integer AS "headcount",
    "sum"("total_hours") AS "hours",
    "sum"("total_cost") AS "cost_total",
    "sum"("gross_wage") AS "cost_gross",
    "sum"("discretionary_overtime_hours") AS "disc_ot"
   FROM "ranked"
  GROUP BY "year", "pp", "labor_type";


ALTER VIEW "public"."hr_staffing_pp_v" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hr_time_off_request" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "start_date" "date" NOT NULL,
    "return_date" "date",
    "non_pto_days" numeric,
    "pto_days" numeric,
    "sick_leave_days" numeric,
    "request_reason" "text",
    "denial_reason" "text",
    "notes" "text",
    "status" "text" DEFAULT 'Pending'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "requested_by" "text" NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "hr_time_off_request_status_check" CHECK (("status" = ANY (ARRAY['Pending'::"text", 'Approved'::"text", 'Denied'::"text"])))
);


ALTER TABLE "public"."hr_time_off_request" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_time_off_request" IS 'Employee time off requests with PTO and sick leave breakdown and a simple approval workflow.';



COMMENT ON COLUMN "public"."hr_time_off_request"."non_pto_days" IS 'Days not charged to PTO or sick leave (e.g. unpaid leave, personal days)';



COMMENT ON COLUMN "public"."hr_time_off_request"."status" IS 'pending, approved, denied';



COMMENT ON COLUMN "public"."hr_time_off_request"."requested_by" IS 'Auto-set to the logged-in employee when the request is created';



CREATE TABLE IF NOT EXISTS "public"."hr_travel_request" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "request_type" "text",
    "travel_purpose" "text",
    "travel_from" "text",
    "travel_to" "text",
    "travel_start_date" "date",
    "travel_return_date" "date",
    "denial_reason" "text",
    "notes" "text",
    "status" "text" DEFAULT 'Pending'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "requested_by" "text" NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "hr_travel_request_status_check" CHECK (("status" = ANY (ARRAY['Pending'::"text", 'Approved'::"text", 'Denied'::"text"])))
);


ALTER TABLE "public"."hr_travel_request" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_travel_request" IS 'Employee travel requests with a simple approval workflow. Captures trip details, purpose, and dates alongside a pending, approved, or denied status flow.';



COMMENT ON COLUMN "public"."hr_travel_request"."status" IS 'pending, approved, denied';



CREATE TABLE IF NOT EXISTS "public"."hr_work_authorization" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."hr_work_authorization" OWNER TO "postgres";


COMMENT ON TABLE "public"."hr_work_authorization" IS 'Org-specific work authorization types used to classify employees. Each org defines its own set of types. id is the display name (e.g. "Local", "FURTE", "WFE", "H1B").';



CREATE TABLE IF NOT EXISTS "public"."invnt_category" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "category_name" "text" NOT NULL,
    "sub_category_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."invnt_category" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_category" IS 'Two-level category hierarchy for inventory items in a single table. A row with sub_category_name IS NULL is a top-level category (e.g. Fertilizers). A row with sub_category_name set is a subcategory under that category_name (e.g. Nitrogen Fertilizers under Fertilizers). Both invnt_category_id and invnt_subcategory_id in invnt_item reference this table.';



COMMENT ON COLUMN "public"."invnt_category"."sub_category_name" IS 'NULL when this row represents a top-level category';



CREATE TABLE IF NOT EXISTS "public"."invnt_onhand" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "invnt_item_id" "text" NOT NULL,
    "onhand_date" "date" NOT NULL,
    "burn_uom" "text",
    "onhand_uom" "text",
    "onhand_quantity" numeric NOT NULL,
    "burn_per_onhand" numeric DEFAULT 0 NOT NULL,
    "invnt_lot_id" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."invnt_onhand" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_onhand" IS 'Records on-hand inventory snapshots per item. References invnt_lot for lot tracking. Source of truth for computed totals like current stock, burn-per-week, and weeks-on-hand.';



COMMENT ON COLUMN "public"."invnt_onhand"."farm_id" IS 'Inherited from invnt_item.farm_id when on-hand record is created';



COMMENT ON COLUMN "public"."invnt_onhand"."burn_uom" IS 'Pre-filled from invnt_item.burn_uom; read-only snapshot';



COMMENT ON COLUMN "public"."invnt_onhand"."onhand_uom" IS 'Pre-filled from invnt_item.onhand_uom; editable';



COMMENT ON COLUMN "public"."invnt_onhand"."burn_per_onhand" IS 'Snapshot from invnt_item.burn_per_onhand at record creation time';



CREATE TABLE IF NOT EXISTS "public"."invnt_po" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "request_type" "text" DEFAULT 'Inventory Item'::"text" NOT NULL,
    "urgency_level" "text",
    "invnt_category_id" "text" NOT NULL,
    "invnt_item_id" "text",
    "item_name" "text" NOT NULL,
    "burn_uom" "text" NOT NULL,
    "order_uom" "text" NOT NULL,
    "order_quantity" numeric NOT NULL,
    "burn_per_order" numeric DEFAULT 0 NOT NULL,
    "vendor_po_number" "text",
    "invnt_vendor_id" "text",
    "total_cost" numeric,
    "is_freight_included" boolean,
    "expected_delivery_date" "date",
    "tracking_number" "text",
    "notes" "text",
    "rejected_reason" "text",
    "request_photos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'Requested'::"text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "requested_by" "text" NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "text",
    "ordered_at" timestamp with time zone,
    "ordered_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "invnt_po_request_type_check" CHECK (("request_type" = ANY (ARRAY['Non Inventory Item'::"text", 'Inventory Item'::"text"]))),
    CONSTRAINT "invnt_po_status_check" CHECK (("status" = ANY (ARRAY['Requested'::"text", 'Approved'::"text", 'Rejected'::"text", 'Ordered'::"text", 'Partial'::"text", 'Received'::"text", 'Cancelled'::"text"]))),
    CONSTRAINT "invnt_po_urgency_level_check" CHECK (("urgency_level" = ANY (ARRAY['Today'::"text", '2 Days'::"text", '7 Days'::"text", 'Not Urgent'::"text"])))
);


ALTER TABLE "public"."invnt_po" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_po" IS 'Tracks purchase order requests through a workflow from request to receipt. Each order snapshots the item name, units, and cost at order time so the record stays accurate even if the item changes later.';



COMMENT ON COLUMN "public"."invnt_po"."request_type" IS 'non_inventory_item, inventory_item';



COMMENT ON COLUMN "public"."invnt_po"."urgency_level" IS 'today, 2_days, 7_days, not_urgent';



COMMENT ON COLUMN "public"."invnt_po"."invnt_category_id" IS 'Pre-filled from invnt_item for inventory_item; user-selected for non_inventory_item';



COMMENT ON COLUMN "public"."invnt_po"."item_name" IS 'Snapshot from invnt_item.id for inventory_item; manually entered for non_inventory_item';



COMMENT ON COLUMN "public"."invnt_po"."burn_uom" IS 'Snapshot from invnt_item.burn_uom for inventory_item; defaults to order_uom for non_inventory_item';



COMMENT ON COLUMN "public"."invnt_po"."order_uom" IS 'Snapshot from invnt_item.order_uom for inventory_item; user-selected for non_inventory_item';



COMMENT ON COLUMN "public"."invnt_po"."burn_per_order" IS 'Snapshot from invnt_item.burn_per_order for inventory_item; defaults to 1 for non_inventory_item';



COMMENT ON COLUMN "public"."invnt_po"."invnt_vendor_id" IS 'Pre-filled from invnt_item.invnt_vendor_id when item is selected; editable';



COMMENT ON COLUMN "public"."invnt_po"."status" IS 'requested, approved, rejected, ordered, partial, received, cancelled';



CREATE TABLE IF NOT EXISTS "public"."invnt_po_received" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "invnt_po_id" "uuid" NOT NULL,
    "received_date" "date" NOT NULL,
    "received_uom" "text" NOT NULL,
    "received_quantity" numeric NOT NULL,
    "burn_per_received" numeric DEFAULT 0 NOT NULL,
    "invnt_lot_id" "text",
    "fsafe_delivery_truck_clean" boolean,
    "fsafe_delivery_acceptable" boolean,
    "notes" "text",
    "received_photos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "received_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."invnt_po_received" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_po_received" IS 'Individual deliveries received against a purchase order. One order can have multiple received records to handle partial deliveries. References invnt_lot for lot tracking.';



COMMENT ON COLUMN "public"."invnt_po_received"."farm_id" IS 'Inherited from invnt_po.farm_id when receiving against a PO';



COMMENT ON COLUMN "public"."invnt_po_received"."received_uom" IS 'Pre-filled from invnt_po.order_uom; editable at receive time';



COMMENT ON COLUMN "public"."invnt_po_received"."burn_per_received" IS 'Snapshot from invnt_po.burn_per_order at receive time';



COMMENT ON COLUMN "public"."invnt_po_received"."received_photos" IS 'Photos taken at delivery for audit and quality verification';



CREATE OR REPLACE VIEW "public"."invnt_item_summary" WITH ("security_invoker"='true') AS
 WITH "latest_onhand" AS (
         SELECT DISTINCT ON ("invnt_onhand"."invnt_item_id") "invnt_onhand"."invnt_item_id",
            "invnt_onhand"."onhand_quantity",
            "invnt_onhand"."onhand_uom",
            "invnt_onhand"."burn_per_onhand",
            "invnt_onhand"."onhand_date"
           FROM "public"."invnt_onhand"
          WHERE ("invnt_onhand"."is_deleted" = false)
          ORDER BY "invnt_onhand"."invnt_item_id", "invnt_onhand"."onhand_date" DESC, "invnt_onhand"."created_at" DESC
        ), "open_orders" AS (
         SELECT "po"."invnt_item_id",
            COALESCE("sum"(("po"."order_quantity" * "po"."burn_per_order")), (0)::numeric) AS "ordered_quantity_in_burn",
            COALESCE("sum"("r"."received_quantity_in_burn"), (0)::numeric) AS "received_quantity_in_burn"
           FROM ("public"."invnt_po" "po"
             LEFT JOIN ( SELECT "invnt_po_received"."invnt_po_id",
                    "sum"(("invnt_po_received"."received_quantity" * "invnt_po_received"."burn_per_received")) AS "received_quantity_in_burn"
                   FROM "public"."invnt_po_received"
                  WHERE ("invnt_po_received"."is_deleted" = false)
                  GROUP BY "invnt_po_received"."invnt_po_id") "r" ON (("r"."invnt_po_id" = "po"."id")))
          WHERE (("po"."is_deleted" = false) AND ("po"."invnt_item_id" IS NOT NULL) AND ("po"."status" = ANY (ARRAY['approved'::"text", 'ordered'::"text", 'partial'::"text"])))
          GROUP BY "po"."invnt_item_id"
        )
 SELECT "i"."org_id",
    "i"."farm_id",
    "i"."id" AS "invnt_item_id",
    "i"."invnt_category_id",
    "i"."invnt_subcategory_id",
    "i"."invnt_vendor_id",
    "i"."burn_uom",
    "i"."onhand_uom",
    "i"."order_uom",
    "i"."burn_per_onhand",
    "i"."burn_per_order",
    "i"."is_frequently_used",
    "i"."burn_per_week",
    "i"."cushion_weeks",
    "i"."is_auto_reorder",
    "i"."reorder_point_in_burn",
    "i"."reorder_quantity_in_burn",
    COALESCE("lo"."onhand_quantity", (0)::numeric) AS "onhand_quantity",
    COALESCE(("lo"."onhand_quantity" * "lo"."burn_per_onhand"), (0)::numeric) AS "onhand_quantity_in_burn",
    "lo"."onhand_date",
    (CURRENT_DATE - "lo"."onhand_date") AS "days_since_onhand",
    COALESCE("oo"."ordered_quantity_in_burn", (0)::numeric) AS "ordered_quantity_in_burn",
    COALESCE("oo"."received_quantity_in_burn", (0)::numeric) AS "received_quantity_in_burn",
    (COALESCE("oo"."ordered_quantity_in_burn", (0)::numeric) - COALESCE("oo"."received_quantity_in_burn", (0)::numeric)) AS "remaining_quantity_in_burn",
        CASE
            WHEN (COALESCE("i"."burn_per_week", (0)::numeric) > (0)::numeric) THEN (COALESCE(("lo"."onhand_quantity" * "lo"."burn_per_onhand"), (0)::numeric) / "i"."burn_per_week")
            ELSE NULL::numeric
        END AS "weeks_on_hand",
        CASE
            WHEN ((COALESCE("i"."burn_per_week", (0)::numeric) > (0)::numeric) AND ("lo"."onhand_date" IS NOT NULL)) THEN ("lo"."onhand_date" + ((((COALESCE(("lo"."onhand_quantity" * "lo"."burn_per_onhand"), (0)::numeric) / "i"."burn_per_week") * (7)::numeric) - (COALESCE("i"."cushion_weeks", (0)::numeric) * (7)::numeric)))::integer)
            ELSE NULL::"date"
        END AS "next_order_date"
   FROM (("public"."invnt_item" "i"
     LEFT JOIN "latest_onhand" "lo" ON (("lo"."invnt_item_id" = "i"."id")))
     LEFT JOIN "open_orders" "oo" ON (("oo"."invnt_item_id" = "i"."id")))
  WHERE ("i"."is_deleted" = false);


ALTER VIEW "public"."invnt_item_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invnt_lot" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "invnt_item_id" "text" NOT NULL,
    "lot_number" "text" NOT NULL,
    "lot_expiry_date" "date",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."invnt_lot" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_lot" IS 'Tracks unique inventory lots by item and lot number. The id (PK) includes the item to ensure global uniqueness since different items can share the same lot number. The constraint on (org_id, invnt_item_id, lot_number) prevents duplicate lots per item.';



COMMENT ON COLUMN "public"."invnt_lot"."farm_id" IS 'Inherited from invnt_item.farm_id when lot is created';



COMMENT ON COLUMN "public"."invnt_lot"."is_active" IS 'Auto-set to false when latest invnt_onhand quantity is zero; can also be manually set to false by user';



CREATE TABLE IF NOT EXISTS "public"."invnt_vendor" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "contact_person" "text",
    "email" "text",
    "phone" "text",
    "address" "text",
    "payment_terms" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."invnt_vendor" OWNER TO "postgres";


COMMENT ON TABLE "public"."invnt_vendor" IS 'Organization-level suppliers used for procurement across all farms. Stores contact details, address, and payment terms.';



CREATE TABLE IF NOT EXISTS "public"."maint_request" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "site_id" "text",
    "equipment_id" "text",
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "request_description" "text",
    "recurring_frequency" "text",
    "due_date" "date",
    "completed_at" timestamp with time zone,
    "fixer_id" "text",
    "fixer_description" "text",
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "requested_by" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "maint_request_check" CHECK (((("site_id" IS NOT NULL) AND ("equipment_id" IS NULL)) OR (("site_id" IS NULL) AND ("equipment_id" IS NOT NULL)))),
    CONSTRAINT "maint_request_recurring_frequency_check" CHECK (("recurring_frequency" = ANY (ARRAY['Daily'::"text", 'Weekly'::"text", 'Monthly'::"text", 'Quarterly'::"text", 'Semi Annually'::"text", 'Annually'::"text"]))),
    CONSTRAINT "maint_request_status_check" CHECK (("status" = ANY (ARRAY['New'::"text", 'Pending'::"text", 'Priority'::"text", 'Done'::"text"])))
);


ALTER TABLE "public"."maint_request" OWNER TO "postgres";


COMMENT ON TABLE "public"."maint_request" IS 'Standalone maintenance work order requests. Each request targets either a site or equipment, never both. Equipment location is derived from org_equipment.site_id. Preventive maintenance is indicated by recurring_frequency being set.';



COMMENT ON COLUMN "public"."maint_request"."site_id" IS 'Any org_site regardless of category; set for site-specific requests, null for equipment requests';



COMMENT ON COLUMN "public"."maint_request"."equipment_id" IS 'The equipment needing maintenance; set for equipment requests, null for site requests';



COMMENT ON COLUMN "public"."maint_request"."status" IS 'new, pending, priority, done';



COMMENT ON COLUMN "public"."maint_request"."recurring_frequency" IS 'daily, weekly, monthly, quarterly, semi_annually, annually; null means not recurring; non-null implies preventive maintenance; auto-creates a new request after status is marked done';



CREATE TABLE IF NOT EXISTS "public"."maint_request_invnt_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "maint_request_id" "uuid" NOT NULL,
    "invnt_item_id" "text" NOT NULL,
    "uom" "text",
    "quantity_used" numeric,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."maint_request_invnt_item" OWNER TO "postgres";


COMMENT ON TABLE "public"."maint_request_invnt_item" IS 'Inventory items consumed during a maintenance request. One row per item per request.';



CREATE TABLE IF NOT EXISTS "public"."maint_request_photo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "maint_request_id" "uuid" NOT NULL,
    "photo_type" "text" NOT NULL,
    "photo_url" "text" NOT NULL,
    "caption" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "maint_request_photo_photo_type_check" CHECK (("photo_type" = ANY (ARRAY['Before'::"text", 'After'::"text"])))
);


ALTER TABLE "public"."maint_request_photo" OWNER TO "postgres";


COMMENT ON TABLE "public"."maint_request_photo" IS 'Photos attached to a maintenance request. One row per photo with before/after classification.';



COMMENT ON COLUMN "public"."maint_request_photo"."photo_type" IS 'before, after';



CREATE TABLE IF NOT EXISTS "public"."ops_corrective_action_choice" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_corrective_action_choice" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_corrective_action_choice" IS 'Org-defined reusable corrective action options available for selection when logging a corrective action. Users pick from this dropdown; if the action isn''t listed they provide a custom description instead.';



CREATE TABLE IF NOT EXISTS "public"."ops_corrective_action_taken" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_template_id" "text",
    "ops_template_result_id" "uuid",
    "fsafe_result_id" "uuid",
    "fsafe_pest_result_id" "uuid",
    "ops_corrective_action_choice_id" "text",
    "other_action" "text",
    "assigned_to" "text",
    "due_date" "date",
    "completed_at" timestamp with time zone,
    "is_resolved" boolean DEFAULT false NOT NULL,
    "notes" "text",
    "result_description" "text",
    "verified_at" timestamp with time zone,
    "verified_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_corrective_action_taken" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_corrective_action_taken" IS 'Corrective actions raised against a failing checklist response or EMP test result. Tracks the action required, who is responsible, and the resolution status.';



COMMENT ON COLUMN "public"."ops_corrective_action_taken"."ops_template_id" IS 'Inherited from ops_template_result.ops_template_id when sourced from a failing checklist response';



COMMENT ON COLUMN "public"."ops_corrective_action_taken"."ops_template_result_id" IS 'Sourced from the failing ops_template_result that triggered this corrective action';



COMMENT ON COLUMN "public"."ops_corrective_action_taken"."fsafe_result_id" IS 'Sourced from the failing fsafe_result that triggered this corrective action';



COMMENT ON COLUMN "public"."ops_corrective_action_taken"."fsafe_pest_result_id" IS 'Sourced from the pest activity observation that triggered this corrective action';



CREATE TABLE IF NOT EXISTS "public"."ops_task_template" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_task_id" "text" NOT NULL,
    "ops_template_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_task_template" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_task_template" IS 'Many-to-many link between tasks and checklist templates. One task can require multiple checklists and the same checklist can be reused across tasks (e.g. spraying → pre_spray_safety_check + ppe_checklist). When a user creates an activity, the app auto-loads all templates linked to that task.';



COMMENT ON COLUMN "public"."ops_task_template"."farm_id" IS 'Inherited from ops_task.farm_id or ops_template.farm_id when the link is created';



CREATE OR REPLACE VIEW "public"."ops_task_weekly_schedule" WITH ("security_invoker"='true') AS
 WITH "schedule_base" AS (
         SELECT "s"."hr_employee_id",
            "s"."ops_task_id",
            "s"."org_id",
            "s"."farm_id",
            "s"."start_time" AS "schedule_start",
            "s"."stop_time" AS "schedule_stop",
            "s"."total_hours" AS "schedule_total_hours",
            ("s"."start_time")::"date" AS "task_date",
            (EXTRACT(dow FROM "s"."start_time"))::integer AS "day_of_week",
            (("s"."start_time")::"date" - (EXTRACT(dow FROM "s"."start_time"))::integer) AS "week_start_date"
           FROM "public"."ops_task_schedule" "s"
          WHERE (("s"."ops_task_tracker_id" IS NULL) AND ("s"."start_time" IS NOT NULL) AND ("s"."is_deleted" = false))
        ), "per_task" AS (
         SELECT "sb"."org_id",
            "sb"."week_start_date",
            "e"."id" AS "hr_employee_id",
            TRIM(BOTH FROM (("e"."first_name" || ' '::"text") || "e"."last_name")) AS "full_name",
            "e"."profile_photo_url",
            "e"."overtime_threshold",
            "t"."id" AS "task",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 0) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "sunday",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 1) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "monday",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 2) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "tuesday",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 3) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "wednesday",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 4) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "thursday",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 5) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "friday",
            "max"(
                CASE
                    WHEN ("sb"."day_of_week" = 6) THEN ("to_char"(("sb"."schedule_start" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text") ||
                    CASE
                        WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (' - '::"text" || "to_char"(("sb"."schedule_stop" AT TIME ZONE 'UTC'::"text"), 'HH24:MI'::"text"))
                        ELSE ''::"text"
                    END)
                    ELSE NULL::"text"
                END) AS "saturday",
            "round"("sum"(COALESCE("sb"."schedule_total_hours",
                CASE
                    WHEN ("sb"."schedule_stop" IS NOT NULL) THEN (EXTRACT(epoch FROM ("sb"."schedule_stop" - "sb"."schedule_start")) / 3600.0)
                    ELSE (0)::numeric
                END))) AS "total_hours"
           FROM (("schedule_base" "sb"
             JOIN "public"."hr_employee" "e" ON (("e"."id" = "sb"."hr_employee_id")))
             JOIN "public"."ops_task" "t" ON (("t"."id" = "sb"."ops_task_id")))
          GROUP BY "sb"."week_start_date", "sb"."org_id", "sb"."farm_id", "e"."id", "e"."first_name", "e"."last_name", "e"."profile_photo_url", "e"."overtime_threshold", "t"."id"
        )
 SELECT "org_id",
    "week_start_date",
    "hr_employee_id",
    "full_name",
    "profile_photo_url",
    "task",
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "total_hours",
        CASE
            WHEN ("overtime_threshold" IS NOT NULL) THEN "round"(("overtime_threshold" / 2.0))
            ELSE NULL::numeric
        END AS "ot_threshold_weekly",
        CASE
            WHEN ("overtime_threshold" IS NULL) THEN NULL::"text"
            WHEN ("round"("sum"("total_hours") OVER (PARTITION BY "hr_employee_id", "week_start_date")) > "round"(("overtime_threshold" / 2.0))) THEN 'above'::"text"
            WHEN ("round"("sum"("total_hours") OVER (PARTITION BY "hr_employee_id", "week_start_date")) = "round"(("overtime_threshold" / 2.0))) THEN 'at'::"text"
            ELSE 'below'::"text"
        END AS "ot_status"
   FROM "per_task"
  ORDER BY "week_start_date", "full_name";


ALTER VIEW "public"."ops_task_weekly_schedule" OWNER TO "postgres";


COMMENT ON VIEW "public"."ops_task_weekly_schedule" IS 'Weekly schedule grid: one row per (employee, task, week) with day-by-day shift strings. total_hours is per-row (this task only); ot_status reflects the employee''s cumulative weekly hours across ALL tasks (''above'' / ''at'' / ''below'' / NULL) so an employee split across multiple tasks is evaluated on their week total. Joined employee display fields (full_name = first + last, profile_photo_url) are pre-flattened for the ag-grid renderer.';



CREATE TABLE IF NOT EXISTS "public"."ops_template" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "sys_module_id" "text",
    "description" "text",
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_template" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_template" IS 'Master checklist template. Defines the checklist and the questions employees answer during a task event.';



CREATE TABLE IF NOT EXISTS "public"."ops_template_question" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_template_id" "text" NOT NULL,
    "question_text" "text" NOT NULL,
    "response_type" "text" NOT NULL,
    "is_required" boolean DEFAULT true NOT NULL,
    "boolean_pass_value" boolean,
    "minimum_value" numeric,
    "maximum_value" numeric,
    "enum_options" "jsonb",
    "enum_pass_options" "jsonb",
    "warning_message" "text",
    "ops_corrective_action_choice_ids" "jsonb",
    "include_photo" boolean DEFAULT false NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "ops_template_question_response_type_check" CHECK (("response_type" = ANY (ARRAY['Boolean'::"text", 'Numeric'::"text", 'Enum'::"text"])))
);


ALTER TABLE "public"."ops_template_question" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_template_question" IS 'Questions within a checklist template. Ordered by display_order within each template.';



COMMENT ON COLUMN "public"."ops_template_question"."farm_id" IS 'Inherited from ops_template.farm_id when question is created';



COMMENT ON COLUMN "public"."ops_template_question"."response_type" IS 'boolean, numeric, enum';



COMMENT ON COLUMN "public"."ops_template_question"."boolean_pass_value" IS 'The boolean value that constitutes a pass';



COMMENT ON COLUMN "public"."ops_template_question"."enum_options" IS 'JSON array of available options when response_type is enum';



COMMENT ON COLUMN "public"."ops_template_question"."enum_pass_options" IS 'JSON array of enum values that constitute a pass';



COMMENT ON COLUMN "public"."ops_template_question"."ops_corrective_action_choice_ids" IS 'JSON array of suggested corrective action choice IDs when this question fails';



CREATE TABLE IF NOT EXISTS "public"."ops_template_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_task_tracker_id" "uuid" NOT NULL,
    "ops_template_id" "text" NOT NULL,
    "ops_template_question_id" "uuid",
    "site_id" "text",
    "equipment_id" "text",
    "response_boolean" boolean,
    "response_numeric" numeric,
    "response_enum" "text",
    "response_text" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_template_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_template_result" IS 'Employee responses to checklist questions. One row per question per task tracker session. Each result targets either a site or equipment, never both. The linked ops_task_tracker record acts as the header (who completed the checklist, when).';



COMMENT ON COLUMN "public"."ops_template_result"."farm_id" IS 'Inherited from ops_task_tracker.farm_id when response is created';



COMMENT ON COLUMN "public"."ops_template_result"."ops_template_id" IS 'Sourced from ops_task_template; identifies which template this response belongs to';



COMMENT ON COLUMN "public"."ops_template_result"."ops_template_question_id" IS 'Sourced from ops_template_question; null for ATP surface test results';



COMMENT ON COLUMN "public"."ops_template_result"."site_id" IS 'The site this checklist was completed for; null for equipment-specific checklists or standard responses without a site';



COMMENT ON COLUMN "public"."ops_template_result"."equipment_id" IS 'The equipment this checklist was completed for; null for site-specific checklists';



CREATE TABLE IF NOT EXISTS "public"."ops_template_result_photo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_template_result_id" "uuid" NOT NULL,
    "photo_url" "text" NOT NULL,
    "caption" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_template_result_photo" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_template_result_photo" IS 'Photos attached to a checklist response. One row per photo. Only used when ops_template_question.include_photo = true.';



CREATE TABLE IF NOT EXISTS "public"."ops_training" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_training_type_id" "text",
    "training_date" "date",
    "topics_covered" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "trainer_id" "text",
    "materials_url" "text",
    "notes" "text",
    "verified_at" timestamp with time zone,
    "verified_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_training" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_training" IS 'Staff training session records. Each row is one training event covering a specific topic for a group of employees.';



COMMENT ON COLUMN "public"."ops_training"."topics_covered" IS 'JSON array of topic strings covered during the training session';



COMMENT ON COLUMN "public"."ops_training"."trainer_id" IS 'Sourced from hr_employee; the employee who conducted the training session';



CREATE TABLE IF NOT EXISTS "public"."ops_training_attendee" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "ops_training_id" "uuid" NOT NULL,
    "hr_employee_id" "text" NOT NULL,
    "signed_at" timestamp with time zone,
    "certification_number" "text",
    "certificate_issuer" "text",
    "certification_issued_on" "date",
    "certification_expires_on" "date",
    "certificate_url" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_training_attendee" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_training_attendee" IS 'Individual attendance and certification records for each employee per training session. One row per employee per training.';



COMMENT ON COLUMN "public"."ops_training_attendee"."farm_id" IS 'Inherited from ops_training.farm_id when attendee record is created';



CREATE TABLE IF NOT EXISTS "public"."ops_training_type" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."ops_training_type" OWNER TO "postgres";


COMMENT ON TABLE "public"."ops_training_type" IS 'Org-specific training types used to classify training sessions. Each org defines its own set of types.';



CREATE TABLE IF NOT EXISTS "public"."org" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "currency" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org" OWNER TO "postgres";


COMMENT ON TABLE "public"."org" IS 'Root entity for multi-org support. Every org-scoped table references this. Stores org-level settings such as default currency.';



CREATE TABLE IF NOT EXISTS "public"."org_business_rule" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "rule_type" "text" NOT NULL,
    "module" "text",
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "rationale" "text",
    "applies_to" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "org_business_rule_rule_type_check" CHECK (("rule_type" = ANY (ARRAY['Business Rule'::"text", 'Workflow'::"text", 'Calculation'::"text", 'Requirement'::"text", 'Definition'::"text"])))
);


ALTER TABLE "public"."org_business_rule" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_business_rule" IS 'Org-scoped registry for business rules, workflows, calculations, requirements, and definitions. Queryable by employees (tooltips), developers (context), and AI (alignment).';



COMMENT ON COLUMN "public"."org_business_rule"."rule_type" IS 'business_rule, workflow, calculation, requirement, definition';



COMMENT ON COLUMN "public"."org_business_rule"."applies_to" IS 'JSON array of table.column references this rule applies to (e.g. ["invnt_onhand.invnt_lot_id"])';



CREATE TABLE IF NOT EXISTS "public"."org_equipment" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "type" "text",
    "description" "text",
    "manufacturer" "text",
    "model" "text",
    "serial_number" "text",
    "purchase_date" "date",
    "manual_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "org_equipment_type_check" CHECK (("type" = ANY (ARRAY['Vehicle'::"text", 'Tool'::"text", 'Machine'::"text", 'PPE'::"text", 'Bag Pack Sprayer'::"text", 'Fogger'::"text", 'Tank'::"text"])))
);


ALTER TABLE "public"."org_equipment" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_equipment" IS 'Equipment register for all physical assets across the organization. Farm-level or shared (farm_id null).';



COMMENT ON COLUMN "public"."org_equipment"."farm_id" IS 'Inherited from parent org_farm when equipment is farm-scoped; null for org-wide equipment';



COMMENT ON COLUMN "public"."org_equipment"."type" IS 'vehicle, tool, machine, ppe, bag_pack_sprayer, fogger, tank';



CREATE TABLE IF NOT EXISTS "public"."org_farm" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "weighing_uom" "text",
    "growing_uom" "text",
    "volume_uom" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_farm" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_farm" IS 'Represents a crop or product line within an organization (e.g. Cuke Farm, Lettuce Farm). Each farm has its own sites, varieties, grades, and products. Farm-level defaults reference units of measure for weighing and growing operations.';



COMMENT ON COLUMN "public"."org_farm"."weighing_uom" IS 'Default weight unit for this farm; pre-fills grow_harvest_container.weight_uom and sales_product.weight_uom';



COMMENT ON COLUMN "public"."org_farm"."growing_uom" IS 'Default growing unit for this farm; pre-fills grow_lettuce_seed_batch.seeding_uom (cuke batches do not carry a seeding unit)';



COMMENT ON COLUMN "public"."org_farm"."volume_uom" IS 'Default volume unit for this farm; pre-fills grow_spray_equipment.water_uom and grow_fertigation.volume_uom';



CREATE TABLE IF NOT EXISTS "public"."org_quickbooks_token" (
    "org_id" "text" NOT NULL,
    "realm_id" "text" NOT NULL,
    "access_token" "text" NOT NULL,
    "refresh_token" "text" NOT NULL,
    "access_expires_at" timestamp with time zone NOT NULL,
    "refresh_expires_at" timestamp with time zone NOT NULL,
    "connected_by" "text",
    "connected_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_quickbooks_token" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_quickbooks_token" IS 'OAuth tokens for the org''s connected QuickBooks Online company. Service-role-only -- not exposed via PostgREST to authenticated users. One row per org. realm_id, access_token, refresh_token rotate on every refresh; always overwrite with the latest values.';



COMMENT ON COLUMN "public"."org_quickbooks_token"."realm_id" IS 'Intuit-assigned company id used in every QB API path: /v3/company/{realmId}/...';



COMMENT ON COLUMN "public"."org_quickbooks_token"."access_token" IS 'OAuth bearer token. Expires after ~1 hour; refresh on demand using refresh_token.';



COMMENT ON COLUMN "public"."org_quickbooks_token"."refresh_token" IS 'Long-lived (~101 days). ROTATES on every refresh -- always persist the new value returned by Intuit. Reuse of an old refresh_token causes Intuit to invalidate the chain.';



COMMENT ON COLUMN "public"."org_quickbooks_token"."refresh_expires_at" IS 'After this time the user must reconnect from the UI; access_token cannot be refreshed.';



COMMENT ON COLUMN "public"."org_quickbooks_token"."connected_by" IS 'Composite-FK (org_id, connected_by) -> hr_employee. The operator who clicked "Connect to QuickBooks".';



CREATE TABLE IF NOT EXISTS "public"."org_site" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "name" "text" NOT NULL,
    "org_site_category_id" "text" NOT NULL,
    "org_site_subcategory_id" "text",
    "site_id_parent" "text",
    "acres" numeric,
    "monitoring_stations" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "zone" "text",
    "latitude" numeric,
    "longitude" numeric,
    "elevation" numeric,
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "org_site_zone_check" CHECK (("zone" = ANY (ARRAY['Zone 1'::"text", 'Zone 2'::"text", 'Zone 3'::"text", 'Zone 4'::"text", 'Water'::"text"])))
);


ALTER TABLE "public"."org_site" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site" IS 'Site register for growing sites, packhouses, and food-safety zones. Supports parent-child hierarchy via site_id_parent. Cuke greenhouses and housing facilities live in their own dedicated standalone tables (org_site_cuke_gh, org_site_housing).';



COMMENT ON COLUMN "public"."org_site"."farm_id" IS 'Inherited from parent org_farm when site is farm-scoped; null for org-wide sites';



COMMENT ON COLUMN "public"."org_site"."org_site_category_id" IS 'References org_site_category rows where sub_category_name IS NULL';



COMMENT ON COLUMN "public"."org_site"."org_site_subcategory_id" IS 'References org_site_category rows where sub_category_name IS NOT NULL';



COMMENT ON COLUMN "public"."org_site"."site_id_parent" IS 'Null for top-level sites; set for child locations within a parent site (e.g. food safety surfaces, pest traps, housing rooms)';



COMMENT ON COLUMN "public"."org_site"."acres" IS 'Only for growing sites with no subcategory, or subcategory greenhouse, pond, nursery; null for all other site types';



COMMENT ON COLUMN "public"."org_site"."monitoring_stations" IS 'JSON array of station names for monitoring; rendered as dropdown in grow_monitoring_result.monitoring_station';



COMMENT ON COLUMN "public"."org_site"."zone" IS 'zone_1 (food contact surface), zone_2, zone_3, zone_4, water; available on all sites regardless of category';



CREATE TABLE IF NOT EXISTS "public"."org_site_category" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "category_name" "text" NOT NULL,
    "sub_category_name" "text",
    "display_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_site_category" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site_category" IS 'Two-level site category hierarchy. Rows with sub_category_name IS NULL are top-level categories (e.g. growing, packing, housing). Rows with sub_category_name set are subcategories (e.g. greenhouse, nursery under growing). Both org_site_category_id and org_site_subcategory_id on org_site reference this table.';



COMMENT ON COLUMN "public"."org_site_category"."sub_category_name" IS 'NULL for top-level categories; set for subcategories under that category_name';



CREATE TABLE IF NOT EXISTS "public"."org_site_cuke_gh" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "farm_section" "text" NOT NULL,
    "acres" numeric,
    "rows_orientation" "text" NOT NULL,
    "sidewalk_position" "text" NOT NULL,
    "blocks_vertical" boolean DEFAULT false NOT NULL,
    "layout_grid_row" integer NOT NULL,
    "layout_grid_col" integer NOT NULL,
    "layout_stack_pos" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "org_site_cuke_gh_farm_section_check" CHECK (("farm_section" = ANY (ARRAY['JTL'::"text", 'BIP'::"text"]))),
    CONSTRAINT "org_site_cuke_gh_rows_orientation_check" CHECK (("rows_orientation" = ANY (ARRAY['Vertical'::"text", 'Horizontal'::"text"]))),
    CONSTRAINT "org_site_cuke_gh_sidewalk_position_check" CHECK (("sidewalk_position" = ANY (ARRAY['Middle'::"text", 'Top'::"text", 'Bottom'::"text", 'Left'::"text", 'Right'::"text", 'None'::"text"])))
);


ALTER TABLE "public"."org_site_cuke_gh" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site_cuke_gh" IS 'Cuke greenhouse registry — one row per GH with layout and display config for the plant-map dashboard and other GH-aware features. Standalone: id is a cuke-GH-scoped identifier and is not FK-linked to org_site.';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."farm_section" IS 'Physical farm area this GH belongs to. JTL = numbered greenhouses (GH1-GH8); BIP = named houses (Kona, Kohala, Hamakua, Waimea, Hilo). Drives dashboard grouping and layout';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."acres" IS 'Cultivated area of this greenhouse. Used by reporting / yield-per-acre calculations. Nullable so a GH can be registered before its acreage is measured';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."rows_orientation" IS 'vertical = rows run top-to-bottom; horizontal = rows run left-to-right';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."sidewalk_position" IS 'Where the sidewalk renders in the GH visual: middle, top, bottom, left, right, or none. Dashboard renders sidewalks in grey';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."blocks_vertical" IS 'When true the renderer stacks blocks vertically instead of placing them side-by-side';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."layout_grid_row" IS 'Dashboard grid row position. Controls top/bottom placement. GHs with lower values render higher. All GHs in the same grid row render at the same pixel height';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."layout_grid_col" IS 'Dashboard grid column position. Controls left/right placement. JTL houses have lower values, BIP houses have higher values';



COMMENT ON COLUMN "public"."org_site_cuke_gh"."layout_stack_pos" IS 'When multiple GHs share the same (grid_row, grid_col), this orders them within the shared cell. Null when no stacking';



CREATE TABLE IF NOT EXISTS "public"."org_site_cuke_gh_block" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text" NOT NULL,
    "block_number" integer NOT NULL,
    "name" "text" NOT NULL,
    "row_number_from" integer NOT NULL,
    "row_number_to" integer NOT NULL,
    "direction" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "org_site_cuke_gh_block_direction_check" CHECK (("direction" = ANY (ARRAY['Forward'::"text", 'Reverse'::"text"])))
);


ALTER TABLE "public"."org_site_cuke_gh_block" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site_cuke_gh_block" IS 'Block definitions per greenhouse. A block is a visually contiguous group of rows rendered together on the dashboard. Sidewalks render between blocks. GHs with no side divisions have a single block covering all rows.';



COMMENT ON COLUMN "public"."org_site_cuke_gh_block"."block_number" IS 'Block sequence (1, 2, 3...). The dashboard renders blocks in ascending block_number, with sidewalks between them';



COMMENT ON COLUMN "public"."org_site_cuke_gh_block"."name" IS 'Display label for the block header on the plant-map dashboard (e.g. North, Middle, South, East, West, Hamakua, Kohala, Main). For GHs that contain multiple physical structures sharing one org_site (HK = Hamakua+Kohala), each structure gets its own block with a distinct name';



COMMENT ON COLUMN "public"."org_site_cuke_gh_block"."row_number_from" IS 'First row_number in this block (inclusive). Block membership is defined by row_number range: a row belongs to the block where row_number_from <= row_number <= row_number_to';



COMMENT ON COLUMN "public"."org_site_cuke_gh_block"."row_number_to" IS 'Last row_number in this block (inclusive)';



COMMENT ON COLUMN "public"."org_site_cuke_gh_block"."direction" IS 'forward = rows render in ascending row_number order within the block. reverse = rows render in descending row_number order';



CREATE TABLE IF NOT EXISTS "public"."org_site_cuke_gh_row" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text" NOT NULL,
    "row_number" integer NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_site_cuke_gh_row" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site_cuke_gh_row" IS 'Physical greenhouse row infrastructure. One row per physical GH row — pure identity (site_id, row_number). Crop-agnostic and rendering-agnostic. Referenced by seeding, scouting, maintenance, and spraying activities when they target a specific row. Bag counts and planting state live on grow_cuke_gh_row_planting (per scenario). Block membership and render order are defined in org_site_cuke_gh_block.';



COMMENT ON COLUMN "public"."org_site_cuke_gh_row"."row_number" IS 'Physical row number. Unique within a greenhouse. Used on labels and for crew navigation. Block membership is derived by joining to org_site_cuke_gh_block on site_id where row_number is between row_num_from and row_num_to';



CREATE TABLE IF NOT EXISTS "public"."org_site_housing" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "maximum_beds" integer,
    "address" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_site_housing" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site_housing" IS 'Housing facility registry — one row per residence owned or managed by the organization. Org-scoped (no farm linkage). Standalone: id is the display name (e.g. "BIP (5)", "South Kohala") and is not FK-linked to org_site.';



COMMENT ON COLUMN "public"."org_site_housing"."maximum_beds" IS 'Total bed capacity of this facility. Informational';



COMMENT ON COLUMN "public"."org_site_housing"."address" IS 'Street address; used for HR mailings and pay stubs';



CREATE TABLE IF NOT EXISTS "public"."org_site_housing_area" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "housing_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."org_site_housing_area" OWNER TO "postgres";


COMMENT ON TABLE "public"."org_site_housing_area" IS 'Sub-areas within a housing facility (rooms, wings, floors). One row per nameable partition of a housing facility.';



COMMENT ON COLUMN "public"."org_site_housing_area"."id" IS 'Display label for the area (e.g. "Room 2A", "East Wing", "Upstairs"). Unique within a housing facility';



COMMENT ON COLUMN "public"."org_site_housing_area"."housing_id" IS 'The housing facility this area belongs to';



CREATE OR REPLACE VIEW "public"."org_site_housing_tenant_count" WITH ("security_invoker"='true') AS
 SELECT "h"."id",
    "h"."org_id",
    "h"."maximum_beds",
    COALESCE("t"."tenant_count", 0) AS "tenant_count",
        CASE
            WHEN ("h"."maximum_beds" IS NULL) THEN NULL::integer
            ELSE GREATEST(("h"."maximum_beds" - COALESCE("t"."tenant_count", 0)), 0)
        END AS "available_beds",
    "h"."created_at",
    "h"."created_by",
    "h"."updated_at",
    "h"."updated_by"
   FROM ("public"."org_site_housing" "h"
     LEFT JOIN ( SELECT "hr_employee"."housing_id",
            ("count"(*))::integer AS "tenant_count"
           FROM "public"."hr_employee"
          WHERE (("hr_employee"."housing_id" IS NOT NULL) AND ("hr_employee"."is_deleted" = false) AND (("hr_employee"."end_date" IS NULL) OR ("hr_employee"."end_date" > CURRENT_DATE)))
          GROUP BY "hr_employee"."housing_id") "t" ON (("t"."housing_id" = "h"."id")))
  WHERE ("h"."is_deleted" = false);


ALTER VIEW "public"."org_site_housing_tenant_count" OWNER TO "postgres";


COMMENT ON VIEW "public"."org_site_housing_tenant_count" IS 'org_site_housing rows extended with tenant_count (active hr_employee assignments — not deleted, end_date null or in the future) and available_beds (maximum_beds minus tenant_count, clamped to >= 0; null when maximum_beds is unset).';



CREATE OR REPLACE VIEW "public"."org_site_housing_tenants" WITH ("security_invoker"='true') AS
 SELECT "housing_id",
    "org_id",
    "id" AS "hr_employee_id",
    "first_name",
    "last_name",
    "preferred_name",
    "gender",
    "hr_department_id",
    "start_date",
    "end_date"
   FROM "public"."hr_employee" "e"
  WHERE (("housing_id" IS NOT NULL) AND ("is_deleted" = false) AND (("end_date" IS NULL) OR ("end_date" > CURRENT_DATE)));


ALTER VIEW "public"."org_site_housing_tenants" OWNER TO "postgres";


COMMENT ON VIEW "public"."org_site_housing_tenants" IS 'Active tenants per housing site. One row per (housing_id, employee). Active = hr_employee.is_deleted=false AND (end_date IS NULL OR end_date > current_date). Pairs with org_site_housing_tenant_count for aggregate counts.';



CREATE TABLE IF NOT EXISTS "public"."pack_fail_category" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "description" "text",
    "display_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."pack_fail_category" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_fail_category" IS 'Lookup for pack line fail categories (e.g. film, tray, printer, leaves, ridges). Referenced by pack_session_fails.pack_fail_category_id.';



CREATE TABLE IF NOT EXISTS "public"."pack_moisture" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "site_id" "text" NOT NULL,
    "grow_lettuce_seed_batch_id" "uuid",
    "invnt_item_id" "text",
    "check_at" timestamp with time zone NOT NULL,
    "dryer_temperature" numeric,
    "greenhouse_temperature" numeric,
    "packhouse_temperature" numeric,
    "pre_packing_leaf_temperature" numeric,
    "moisture_before_dryer" numeric,
    "moisture_after_dryer" numeric,
    "belt_speed" numeric,
    "tracking_code" "text",
    "pack_moisture_id_original" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."pack_moisture" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_moisture" IS 'Environmental and moisture readings taken during the packing process. One row per check at a specific time, tracking temperature and moisture conditions before and after the dryer.';



COMMENT ON COLUMN "public"."pack_moisture"."tracking_code" IS 'Human-readable code identifying this check for re-tracking';



COMMENT ON COLUMN "public"."pack_moisture"."pack_moisture_id_original" IS 'Self-referencing FK to the original check when this row is a re-check.';



CREATE TABLE IF NOT EXISTS "public"."pack_session" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "harvest_date" "date" NOT NULL,
    "started_at" timestamp with time zone,
    "stopped_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_date" "date" NOT NULL,
    "best_by_date" "date",
    "pack_lot" "text" NOT NULL
);


ALTER TABLE "public"."pack_session" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_session" IS 'Pack session: one row per (org, farm, pack_date, sales_product_id, harvest_date). Absorbs the prior pack_session_product_run + pack_lot rollup.';



COMMENT ON COLUMN "public"."pack_session"."started_at" IS 'Set when packing starts. Nullable for historical backfill where no run was recorded.';



COMMENT ON COLUMN "public"."pack_session"."stopped_at" IS 'Set-once when packing stops.';



COMMENT ON COLUMN "public"."pack_session"."pack_date" IS 'Day this product was packed. Editable; user can backdate to log prior days.';



COMMENT ON COLUMN "public"."pack_session"."best_by_date" IS 'Auto-set on insert as harvest_date + sales_product.shelf_life_days.';



COMMENT ON COLUMN "public"."pack_session"."pack_lot" IS 'Lot number TEXT (formerly pack_lot.lot_number). Auto-generated on INSERT as {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD; user-editable. NOT NULL — every session row has a lot identifier for FSMA traceability.';



CREATE TABLE IF NOT EXISTS "public"."pack_session_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "cases_packed" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_date" "date" NOT NULL,
    "pack_end_hour" timestamp with time zone NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "harvest_date" "date" NOT NULL
);


ALTER TABLE "public"."pack_session_cases" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_session_cases" IS 'Per-product per-hour cases packed. cases_packed is the count for THIS hour, not cumulative. Cukes use pack_end_hour=23:59 since they are day-totals, not hourly.';



COMMENT ON COLUMN "public"."pack_session_cases"."pack_end_hour" IS 'Clock hour bucket. For cuke products, set to 23:59 of pack_date (uniqueness still holds; no hourly cadence).';



COMMENT ON COLUMN "public"."pack_session_cases"."harvest_date" IS 'Matches the parent pack_session row''s harvest_date.';



CREATE TABLE IF NOT EXISTS "public"."pack_session_fails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "pack_fail_category_id" "text" NOT NULL,
    "fail_count" integer DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_date" "date" NOT NULL,
    "pack_end_hour" timestamp with time zone NOT NULL
);


ALTER TABLE "public"."pack_session_fails" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_session_fails" IS 'Fail counts per category per hour. One row per (org, farm, pack_date, pack_end_hour, fail_category).';



COMMENT ON COLUMN "public"."pack_session_fails"."pack_fail_category_id" IS 'Fail category (e.g. film, tray, printer, leaves, ridges) — references pack_fail_category (renamed from pack_productivity_fail_category in step 8).';



COMMENT ON COLUMN "public"."pack_session_fails"."fail_count" IS 'Number of fails for this category in this hour';



CREATE TABLE IF NOT EXISTS "public"."pack_session_labor_hour" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "pack_end_hour" timestamp with time zone NOT NULL,
    "catchers" integer DEFAULT 0 NOT NULL,
    "packers" integer DEFAULT 0 NOT NULL,
    "mixers" integer DEFAULT 0 NOT NULL,
    "boxers" integer DEFAULT 0 NOT NULL,
    "fsafe_metal_detected_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "fsafe_metal_detected" boolean DEFAULT false NOT NULL,
    "pack_date" "date" NOT NULL
);


ALTER TABLE "public"."pack_session_labor_hour" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_session_labor_hour" IS 'Hourly crew snapshot for a pack day. One row per (org, farm, pack_date, pack_end_hour). Crew counts (catchers/packers/mixers/boxers) and metal-detector flag are session-wide; per-product cases are in pack_session_cases.';



COMMENT ON COLUMN "public"."pack_session_labor_hour"."pack_end_hour" IS 'The hour being recorded (e.g. 2026-03-26 11:00); one row per clock hour.';



COMMENT ON COLUMN "public"."pack_session_labor_hour"."fsafe_metal_detected_at" IS 'Timestamp of food safety metal detection check during this packing hour; null means no detection was recorded';



COMMENT ON COLUMN "public"."pack_session_labor_hour"."fsafe_metal_detected" IS 'True when the required food-safety metal-detection process was performed during this packing hour; false (default) means not yet done. Captured separately from the timestamp so the UI can record a simple yes/no without needing to also stamp a time.';



COMMENT ON COLUMN "public"."pack_session_labor_hour"."pack_date" IS 'Day this hour belongs to (denormalized from pack_session — both are keyed by pack_date).';



CREATE TABLE IF NOT EXISTS "public"."pack_session_leftover" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "leftover_lettuce" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_date" "date" NOT NULL,
    "leftover_watercress" numeric DEFAULT 0 NOT NULL,
    "leftover_arugula" numeric DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."pack_session_leftover" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_session_leftover" IS 'End-of-day leftover pounds by fixed crop column (lettuce/watercress/arugula). One row per (org, farm, pack_date).';



COMMENT ON COLUMN "public"."pack_session_leftover"."leftover_lettuce" IS 'Leftover pounds — lettuce.';



COMMENT ON COLUMN "public"."pack_session_leftover"."leftover_watercress" IS 'Leftover pounds — watercress.';



COMMENT ON COLUMN "public"."pack_session_leftover"."leftover_arugula" IS 'Leftover pounds — arugula.';



CREATE OR REPLACE VIEW "public"."pack_session_summary_v" WITH ("security_invoker"='true') AS
 WITH "day_runs" AS (
         SELECT "s"."org_id",
            "s"."farm_id",
            "s"."pack_date",
            "min"("s"."started_at") AS "started_at",
            "max"("s"."stopped_at") AS "stopped_at"
           FROM "public"."pack_session" "s"
          WHERE ("s"."is_deleted" = false)
          GROUP BY "s"."org_id", "s"."farm_id", "s"."pack_date"
        ), "day_cases" AS (
         SELECT "c_1"."org_id",
            "c_1"."farm_id",
            "c_1"."pack_date",
            (COALESCE("sum"((("c_1"."cases_packed")::numeric * COALESCE("sp"."pack_per_case", (1)::numeric))), (0)::numeric))::integer AS "total_trays"
           FROM ("public"."pack_session_cases" "c_1"
             JOIN "public"."sales_product" "sp" ON (("sp"."id" = "c_1"."sales_product_id")))
          WHERE ("c_1"."is_deleted" = false)
          GROUP BY "c_1"."org_id", "c_1"."farm_id", "c_1"."pack_date"
        ), "day_fails" AS (
         SELECT "f_1"."org_id",
            "f_1"."farm_id",
            "f_1"."pack_date",
            (COALESCE("sum"("f_1"."fail_count"), (0)::bigint))::integer AS "total_fails"
           FROM "public"."pack_session_fails" "f_1"
          WHERE ("f_1"."is_deleted" = false)
          GROUP BY "f_1"."org_id", "f_1"."farm_id", "f_1"."pack_date"
        )
 SELECT "r"."org_id",
    "r"."farm_id",
    "r"."pack_date",
    "r"."started_at",
    "r"."stopped_at",
        CASE
            WHEN (("r"."started_at" IS NULL) OR ("r"."stopped_at" IS NULL) OR ("r"."stopped_at" = "r"."started_at")) THEN NULL::numeric
            ELSE (EXTRACT(epoch FROM ("r"."stopped_at" - "r"."started_at")) / (60)::numeric)
        END AS "minutes_total",
    COALESCE("c"."total_trays", 0) AS "total_trays",
    COALESCE("f"."total_fails", 0) AS "total_fails",
        CASE
            WHEN (("r"."started_at" IS NULL) OR ("r"."stopped_at" IS NULL) OR ("r"."stopped_at" = "r"."started_at")) THEN NULL::numeric
            ELSE ((COALESCE("c"."total_trays", 0))::numeric / (EXTRACT(epoch FROM ("r"."stopped_at" - "r"."started_at")) / (60)::numeric))
        END AS "trays_per_min"
   FROM (("day_runs" "r"
     LEFT JOIN "day_cases" "c" USING ("org_id", "farm_id", "pack_date"))
     LEFT JOIN "day_fails" "f" USING ("org_id", "farm_id", "pack_date"));


ALTER VIEW "public"."pack_session_summary_v" OWNER TO "postgres";


COMMENT ON VIEW "public"."pack_session_summary_v" IS 'One row per (org, farm, pack_date) with rollups: minutes_total (max-stop minus min-start across day''s product rows), total_trays (cases × pack_per_case), total_fails, trays_per_min.';



CREATE TABLE IF NOT EXISTS "public"."pack_shelf_life" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "sales_product_id" "text",
    "invnt_item_id" "text",
    "trial_number" integer,
    "trial_purpose" "text",
    "target_shelf_life_days" integer,
    "site_id" "text",
    "notes" "text",
    "is_terminated" boolean DEFAULT false NOT NULL,
    "termination_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_session_id" "uuid"
);


ALTER TABLE "public"."pack_shelf_life" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_shelf_life" IS 'Shelf life trial header. One row per trial. Tracks the product, lot, packaging type, target shelf life, and trial outcome.';



COMMENT ON COLUMN "public"."pack_shelf_life"."invnt_item_id" IS 'Pre-filled from sales_product.invnt_item_id; filtered to packaging items in inventory';



COMMENT ON COLUMN "public"."pack_shelf_life"."target_shelf_life_days" IS 'Pre-filled from sales_product.shelf_life_days; editable';



COMMENT ON COLUMN "public"."pack_shelf_life"."site_id" IS 'Filtered to org_site where category = storage; the storage location for this trial';



COMMENT ON COLUMN "public"."pack_shelf_life"."pack_session_id" IS 'Links the shelf-life trial to the specific pack_session it sampled from (pack_date + product + harvest_date). Replaces prior pack_lot_id FK.';



CREATE TABLE IF NOT EXISTS "public"."pack_shelf_life_metric" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "description" "text",
    "response_type" "text" NOT NULL,
    "enum_options" "jsonb",
    "fail_boolean" boolean,
    "fail_enum_values" "jsonb",
    "fail_minimum_value" numeric,
    "fail_maximum_value" numeric,
    "display_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "pack_shelf_life_metric_response_type_check" CHECK (("response_type" = ANY (ARRAY['Boolean'::"text", 'Numeric'::"text", 'Enum'::"text"])))
);


ALTER TABLE "public"."pack_shelf_life_metric" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_shelf_life_metric" IS 'Defines what gets checked during a shelf life observation (e.g. color, texture, moisture). Each metric specifies a response type and optional fail criteria that trigger trial termination.';



COMMENT ON COLUMN "public"."pack_shelf_life_metric"."response_type" IS 'boolean, numeric, enum';



COMMENT ON COLUMN "public"."pack_shelf_life_metric"."enum_options" IS 'JSON array of allowed observation values when response_type is enum (e.g. ["Green", "Yellow", "Brown"])';



COMMENT ON COLUMN "public"."pack_shelf_life_metric"."fail_boolean" IS 'Boolean value that triggers trial termination when matched; null if response_type is not boolean';



COMMENT ON COLUMN "public"."pack_shelf_life_metric"."fail_enum_values" IS 'JSON array of enum values that trigger trial termination; null if response_type is not enum';



COMMENT ON COLUMN "public"."pack_shelf_life_metric"."fail_minimum_value" IS 'Reading below this value triggers termination; use alone, with max for a range, or null if not numeric';



COMMENT ON COLUMN "public"."pack_shelf_life_metric"."fail_maximum_value" IS 'Reading above this value triggers termination; use alone, with min for a range, or null if not numeric';



CREATE TABLE IF NOT EXISTS "public"."pack_shelf_life_photo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "pack_shelf_life_id" "uuid" NOT NULL,
    "observation_date" "date" NOT NULL,
    "shelf_life_day" integer NOT NULL,
    "side" "text" NOT NULL,
    "photo_url" "text" NOT NULL,
    "caption" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "pack_shelf_life_photo_side_check" CHECK (("side" = ANY (ARRAY['Top'::"text", 'Side'::"text", 'Bottom'::"text"])))
);


ALTER TABLE "public"."pack_shelf_life_photo" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_shelf_life_photo" IS 'Photos taken during a shelf life trial observation. Multiple photos per observation date per trial.';



COMMENT ON COLUMN "public"."pack_shelf_life_photo"."shelf_life_day" IS 'Auto-calculated: observation_date minus pack_lot.pack_date';



COMMENT ON COLUMN "public"."pack_shelf_life_photo"."side" IS 'top, side, bottom';



CREATE TABLE IF NOT EXISTS "public"."pack_shelf_life_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "pack_shelf_life_id" "uuid" NOT NULL,
    "pack_shelf_life_metric_id" "text" NOT NULL,
    "observation_date" "date" NOT NULL,
    "shelf_life_day" integer NOT NULL,
    "response_boolean" boolean,
    "response_numeric" numeric,
    "response_enum" "text",
    "response_text" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."pack_shelf_life_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."pack_shelf_life_result" IS 'Individual observation responses for a shelf life trial. One row per check per observation date per trial.';



COMMENT ON COLUMN "public"."pack_shelf_life_result"."shelf_life_day" IS 'Auto-calculated: observation_date minus pack_lot.pack_date';



COMMENT ON COLUMN "public"."pack_shelf_life_result"."response_boolean" IS 'Used when pack_shelf_life_metric.response_type is boolean';



COMMENT ON COLUMN "public"."pack_shelf_life_result"."response_numeric" IS 'Used when pack_shelf_life_metric.response_type is numeric';



COMMENT ON COLUMN "public"."pack_shelf_life_result"."response_enum" IS 'Used when pack_shelf_life_metric.response_type is enum; value from metric enum_options';



CREATE TABLE IF NOT EXISTS "public"."sales_container_type" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "maximum_spaces" integer NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_container_type" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_container_type" IS 'Lookup table for shipping container types. Defines the available container types and their maximum pallet space capacity.';



CREATE TABLE IF NOT EXISTS "public"."sales_crm_external_product" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "display_order" integer DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_crm_external_product" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_crm_external_product" IS 'Competitor products observed during store visits. Simple name-based lookup (e.g. Nalo 14oz, Mainland 16oz, Sensei 4oz).';



CREATE TABLE IF NOT EXISTS "public"."sales_crm_store" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_customer_id" "text",
    "chain" "text",
    "location" "text",
    "island" "text",
    "contact_name" "text",
    "contact_title" "text",
    "contact_email" "text",
    "contact_phone" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_crm_store" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_crm_store" IS 'Physical retail locations where products are sold. Each store belongs to a chain and optionally links to a sales_customer for order tracking.';



CREATE TABLE IF NOT EXISTS "public"."sales_crm_store_visit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_crm_store_id" "text" NOT NULL,
    "visit_date" "date" NOT NULL,
    "notes" "text",
    "visited_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_crm_store_visit" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_crm_store_visit" IS 'Store visit records capturing field observations, notes from store managers, and action items.';



CREATE TABLE IF NOT EXISTS "public"."sales_crm_store_visit_photo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_crm_store_visit_id" "uuid" NOT NULL,
    "photo_url" "text" NOT NULL,
    "caption" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_crm_store_visit_photo" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_crm_store_visit_photo" IS 'Photos taken during a store visit. One row per photo.';



CREATE TABLE IF NOT EXISTS "public"."sales_crm_store_visit_result" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_crm_store_visit_id" "uuid" NOT NULL,
    "sales_product_id" "text",
    "sales_crm_external_product_id" "text",
    "shelf_price" numeric,
    "best_by_date" "date",
    "stock_level" "text",
    "cases_per_week" numeric,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "chk_sales_crm_visit_result_product" CHECK (((("sales_product_id" IS NOT NULL) AND ("sales_crm_external_product_id" IS NULL)) OR (("sales_product_id" IS NULL) AND ("sales_crm_external_product_id" IS NOT NULL)))),
    CONSTRAINT "sales_crm_store_visit_result_stock_level_check" CHECK (("stock_level" = ANY (ARRAY['Zero'::"text", 'Low'::"text", 'Medium'::"text", 'Full'::"text"])))
);


ALTER TABLE "public"."sales_crm_store_visit_result" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_crm_store_visit_result" IS 'Per-product observations collected during a store visit. Each row captures shelf price, best-by date, stock level, and weekly velocity for either an own product or a competitor product.';



CREATE TABLE IF NOT EXISTS "public"."sales_customer_group" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_customer_group" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_customer_group" IS 'Allows each organization to classify customers into groups for reporting and group-based pricing (e.g. Wholesale, Retail, Restaurant).';



CREATE TABLE IF NOT EXISTS "public"."sales_fob" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_fob" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_fob" IS 'Defines each organization''s available delivery methods (e.g. Farm Pick-up, Local Delivery, Distributor). Used in customer setup to set a preferred delivery and in pricing to set delivery-specific prices.';



CREATE TABLE IF NOT EXISTS "public"."sales_invoice" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text",
    "invoice_number" "text" NOT NULL,
    "invoice_date" "date" NOT NULL,
    "customer_name" "text" NOT NULL,
    "customer_group" "text",
    "product_code" "text",
    "variety" "text",
    "grade" "text",
    "cases" numeric,
    "pounds" numeric,
    "dollars" numeric NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_invoice" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_invoice" IS 'QuickBooks invoice line items (nightly-synced from the invoices spreadsheet today, moving to direct QB API later). One row per line item — a single invoice_number can appear across multiple rows with different product_code/variety/grade combinations. No uniqueness constraint until QB line-item numbers are included in the pull, at which point (org_id, invoice_number, line_number) will be unique.';



COMMENT ON COLUMN "public"."sales_invoice"."farm_id" IS 'Derived from the Farm column in the sheet (e.g. "Cuke" -> cuke, "Lettuce" -> lettuce)';



COMMENT ON COLUMN "public"."sales_invoice"."invoice_number" IS 'QB invoice number; not unique on its own because one invoice spans multiple line items';



COMMENT ON COLUMN "public"."sales_invoice"."invoice_date" IS 'Date the invoice was issued';



COMMENT ON COLUMN "public"."sales_invoice"."customer_name" IS 'Customer display name from QB';



COMMENT ON COLUMN "public"."sales_invoice"."customer_group" IS 'Broader grouping used by sales dashboards (e.g. Safeway Inc., Armstrong Produce, Small)';



COMMENT ON COLUMN "public"."sales_invoice"."product_code" IS 'Short product code as it appears on the invoice line (e.g. OK, OJ, LF, LR)';



COMMENT ON COLUMN "public"."sales_invoice"."variety" IS 'One-letter variety code pulled from the line (K, J, E, L, W, etc.). Free-text to allow future variations';



COMMENT ON COLUMN "public"."sales_invoice"."grade" IS 'Quality grade on the line (e.g. 1, 2)';



COMMENT ON COLUMN "public"."sales_invoice"."cases" IS 'Case count on the invoice line';



COMMENT ON COLUMN "public"."sales_invoice"."pounds" IS 'Weight in pounds on the invoice line';



COMMENT ON COLUMN "public"."sales_invoice"."dollars" IS 'Line total in dollars';



CREATE OR REPLACE VIEW "public"."sales_invoice_v" WITH ("security_invoker"='true') AS
 SELECT "id",
    "org_id",
    "farm_id",
    "invoice_number",
    "invoice_date",
    "customer_name",
    "customer_group",
    "product_code",
    "variety",
    "grade",
    "cases",
    "pounds",
    "dollars",
    "notes",
    "created_at",
    "created_by",
    "updated_at",
    "updated_by",
    "is_deleted",
    (EXTRACT(year FROM "invoice_date"))::integer AS "year",
    (EXTRACT(month FROM "invoice_date"))::integer AS "month",
    (EXTRACT(isoyear FROM "invoice_date"))::integer AS "iso_year",
    (EXTRACT(week FROM "invoice_date"))::integer AS "iso_week",
    (EXTRACT(dow FROM "invoice_date"))::integer AS "dow"
   FROM "public"."sales_invoice" "i"
  WHERE ("is_deleted" = false);


ALTER VIEW "public"."sales_invoice_v" OWNER TO "postgres";


COMMENT ON VIEW "public"."sales_invoice_v" IS 'sales_invoice with derived year/month/iso_year/iso_week/dow columns and soft-delete filter applied. Dashboards read from this view';



CREATE TABLE IF NOT EXISTS "public"."sales_pallet" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "target_invoice_date" "date" NOT NULL,
    "pallet_number" "text" NOT NULL,
    "pallet_type" "text" NOT NULL,
    "capacity_utilization" numeric DEFAULT 0 NOT NULL,
    "sales_sps_shipment_container_id" "uuid",
    "container_space_number" integer,
    "is_spillover" boolean DEFAULT false NOT NULL,
    "is_locked" boolean DEFAULT false NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "sales_pallet_capacity_utilization_check" CHECK ((("capacity_utilization" >= (0)::numeric) AND ("capacity_utilization" <= (1)::numeric))),
    CONSTRAINT "sales_pallet_container_space_number_check" CHECK (("container_space_number" > 0)),
    CONSTRAINT "sales_pallet_pallet_type_check" CHECK (("pallet_type" = ANY (ARRAY['Full'::"text", 'Shareable'::"text", 'Stackable'::"text"])))
);


ALTER TABLE "public"."sales_pallet" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_pallet" IS 'Physical pallet assembled for shipment. Generated by the three-step Palletize/Stack/Containerize workflow scoped per (farm, target_invoice_date). Allocations from PO fulfillment lines live on sales_pallet_allocation. Locked pallets are preserved across regenerations.';



COMMENT ON COLUMN "public"."sales_pallet"."target_invoice_date" IS 'Invoice date the pallet was built for. Regeneration runs scoped to (farm_id, target_invoice_date) wipe unlocked pallets in scope and rebuild.';



COMMENT ON COLUMN "public"."sales_pallet"."pallet_number" IS 'CP01..CPnn (cucumber container), LP01..LPnn (lettuce container), BP01..BPnn (box truck), or {customer}_01..{customer}_10 for Shareable pallets.';



COMMENT ON COLUMN "public"."sales_pallet"."pallet_type" IS 'Full = at or above the product full_pallet threshold (no further allocations accepted). Shareable = mixed by customer; user can drag allocations between shareable pallets in the UI. Stackable = partial pallet that can be vertically stacked with another partial in one container space.';



COMMENT ON COLUMN "public"."sales_pallet"."capacity_utilization" IS 'Fraction 0..1 of product max_pallet used by the allocations on this pallet. Display as percentage in the UI.';



COMMENT ON COLUMN "public"."sales_pallet"."sales_sps_shipment_container_id" IS 'Container the pallet ships in. NULL until Containerize runs. May not match the pallet''s preferred container when is_spillover=true.';



COMMENT ON COLUMN "public"."sales_pallet"."container_space_number" IS 'Position 1..N inside the container, where N = sales_container_type.maximum_spaces of the container''s type. Multiple Stackable pallets share a number when stacked.';



COMMENT ON COLUMN "public"."sales_pallet"."is_spillover" IS 'Pallet was overflowed out of its preferred container (e.g. cucumber pallet now in the lettuce container). Operator-visible flag.';



COMMENT ON COLUMN "public"."sales_pallet"."is_locked" IS 'When true, regeneration skips this pallet and its allocations. Operators bulk-lock after a run is finalized so subsequent runs preserve manual edits.';



CREATE TABLE IF NOT EXISTS "public"."sales_pallet_allocation" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_pallet_id" "uuid" NOT NULL,
    "sales_po_fulfillment_id" "uuid" NOT NULL,
    "allocated_quantity" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "sales_pallet_allocation_allocated_quantity_check" CHECK (("allocated_quantity" > (0)::numeric))
);


ALTER TABLE "public"."sales_pallet_allocation" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_pallet_allocation" IS 'Line items on a pallet. Each row = a slice of a sales_po_fulfillment rolling onto a sales_pallet, with allocated_quantity carrying that slice''s case count. A fulfillment may split across multiple pallets and a Shareable pallet may carry multiple fulfillments.';



COMMENT ON COLUMN "public"."sales_pallet_allocation"."allocated_quantity" IS 'Number of cases from the source fulfillment that ride on this pallet. Sum of all allocations for one fulfillment must equal sales_po_fulfillment.fulfilled_quantity (enforced by the app, not the DB, because partial allocations are valid mid-workflow).';



CREATE TABLE IF NOT EXISTS "public"."sales_po" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_customer_group_id" "text",
    "sales_customer_id" "text" NOT NULL,
    "sales_fob_id" "text",
    "po_number" "text",
    "order_date" "date" NOT NULL,
    "invoice_date" "date",
    "recurring_frequency" "text",
    "notes" "text",
    "status" "text" DEFAULT 'Draft'::"text" NOT NULL,
    "approved_at" timestamp with time zone,
    "approved_by" "text",
    "qb_uploaded_at" timestamp with time zone,
    "qb_uploaded_by" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "sales_sps_trading_partner_id" "text",
    "buyer_department" "text",
    "buyer_division" "text",
    "buyer_contact_name" "text",
    "buyer_contact_email" "text",
    "buyer_contact_phone" "text",
    "ship_to_name" "text",
    "ship_to_address1" "text",
    "ship_to_address2" "text",
    "ship_to_city" "text",
    "ship_to_state" "text",
    "ship_to_zip" "text",
    "ship_to_country" "text",
    "bill_to_name" "text",
    "bill_to_address1" "text",
    "bill_to_address2" "text",
    "bill_to_city" "text",
    "bill_to_state" "text",
    "bill_to_zip" "text",
    "bill_to_country" "text",
    "carrier_scac" "text",
    "carrier_routing" "text",
    "requested_ship_date" "date",
    "requested_delivery_date" "date",
    "payment_terms_net_days" integer,
    CONSTRAINT "sales_po_recurring_frequency_check" CHECK (("recurring_frequency" = ANY (ARRAY['Weekly'::"text", 'Biweekly'::"text", 'Monthly'::"text"]))),
    CONSTRAINT "sales_po_status_check" CHECK (("status" = ANY (ARRAY['Draft'::"text", 'Received'::"text", 'Acknowledged'::"text", 'Approved'::"text", 'Shipped'::"text", 'Invoiced'::"text", 'Fulfilled'::"text", 'Unfulfilled'::"text", 'Past Due'::"text"])))
);


ALTER TABLE "public"."sales_po" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_po" IS 'Customer order header. One row per order. Tracks customer, FOB, dates, approval workflow, optional recurring frequency, and EDI snapshot fields (buyer_*, ship_to_*, bill_to_*, carrier_*, payment_terms_*) populated from inbound SPS 850 documents.';



COMMENT ON COLUMN "public"."sales_po"."sales_customer_group_id" IS 'Auto-set from sales_customer.sales_customer_group_id; read-only';



COMMENT ON COLUMN "public"."sales_po"."sales_fob_id" IS 'Auto-set from sales_customer.sales_fob_id; read-only';



COMMENT ON COLUMN "public"."sales_po"."po_number" IS 'Customer PO number. For manual orders this is what the customer gave us. For EDI orders this is the buyer''s PO number from 850 BEG, echoed back on 856 BSN and 810 BIG.';



COMMENT ON COLUMN "public"."sales_po"."recurring_frequency" IS 'weekly, biweekly, monthly; null means not recurring; auto-creates a new order after status is marked fulfilled';



COMMENT ON COLUMN "public"."sales_po"."status" IS 'Lifecycle state. Manual orders flow Draft -> Approved -> Fulfilled/Unfulfilled (or Past Due). EDI orders flow Received -> Acknowledged -> Approved -> Shipped -> Invoiced.';



COMMENT ON COLUMN "public"."sales_po"."sales_sps_trading_partner_id" IS 'EDI-only. Set when this PO arrived via SPS Commerce 850. NULL for orders entered manually in the app.';



COMMENT ON COLUMN "public"."sales_po"."buyer_department" IS 'EDI-only. From 850 BEG09 / REF. Costco/Safeway use this to route receiving.';



COMMENT ON COLUMN "public"."sales_po"."buyer_division" IS 'EDI-only. Buyer''s division code from the 850 envelope.';



COMMENT ON COLUMN "public"."sales_po"."buyer_contact_name" IS 'EDI-only. Buyer-side contact from 850 PER segment.';



COMMENT ON COLUMN "public"."sales_po"."buyer_contact_email" IS 'EDI-only. Buyer contact email from 850 PER.';



COMMENT ON COLUMN "public"."sales_po"."buyer_contact_phone" IS 'EDI-only. Buyer contact phone from 850 PER.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_name" IS 'EDI-only. Ship-to party name from 850 N1*ST segment. Snapshot at PO receipt.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_address1" IS 'EDI-only. Ship-to address line 1 from 850 N3 segment.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_address2" IS 'EDI-only. Ship-to address line 2 from 850 N3 segment.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_city" IS 'EDI-only. Ship-to city from 850 N4 segment.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_state" IS 'EDI-only. Ship-to state code from 850 N4 segment.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_zip" IS 'EDI-only. Ship-to postal code from 850 N4 segment.';



COMMENT ON COLUMN "public"."sales_po"."ship_to_country" IS 'EDI-only. Ship-to country from 850 N4 segment.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_name" IS 'EDI-only. Bill-to party name from 850 N1*BT segment.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_address1" IS 'EDI-only. Bill-to address line 1 from 850 N3.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_address2" IS 'EDI-only. Bill-to address line 2 from 850 N3.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_city" IS 'EDI-only. Bill-to city from 850 N4.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_state" IS 'EDI-only. Bill-to state from 850 N4.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_zip" IS 'EDI-only. Bill-to postal code from 850 N4.';



COMMENT ON COLUMN "public"."sales_po"."bill_to_country" IS 'EDI-only. Bill-to country from 850 N4.';



COMMENT ON COLUMN "public"."sales_po"."carrier_scac" IS 'EDI-only. Standard Carrier Alpha Code from 850 TD5 segment. Also sent on outbound 856 TD5.';



COMMENT ON COLUMN "public"."sales_po"."carrier_routing" IS 'EDI-only. Carrier routing instructions from 850 TD5.';



COMMENT ON COLUMN "public"."sales_po"."requested_ship_date" IS 'EDI-only. Requested ship date from 850 DTM*002 segment.';



COMMENT ON COLUMN "public"."sales_po"."requested_delivery_date" IS 'EDI-only. Requested delivery date from 850 DTM*002 / DTM*010 segment.';



COMMENT ON COLUMN "public"."sales_po"."payment_terms_net_days" IS 'EDI-only. Net days from 850 ITD segment (e.g. 30 for Net 30). Drives invoice due date on outbound 810.';



CREATE TABLE IF NOT EXISTS "public"."sales_po_fulfillment" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "sales_po_id" "uuid" NOT NULL,
    "sales_po_line_id" "uuid" NOT NULL,
    "fulfilled_quantity" numeric NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_session_id" "uuid"
);


ALTER TABLE "public"."sales_po_fulfillment" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_po_fulfillment" IS 'Fulfillment records linking order lines to pack lots. One row per lot per order line, supporting partial fulfillment across multiple lots. Pallet/container assignment lives downstream on sales_pallet + sales_pallet_allocation.';



COMMENT ON COLUMN "public"."sales_po_fulfillment"."pack_session_id" IS 'Links fulfilled quantity to the specific pack_session (pack_date + product + harvest_date). Replaces the prior pack_lot_id FK. NULL for historical rows whose pack_lot had no associated pack_lot_item product mapping.';



CREATE TABLE IF NOT EXISTS "public"."sales_po_line" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "sales_po_id" "uuid" NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "order_quantity" numeric NOT NULL,
    "price_per_case" numeric NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "buyer_part_number" "text",
    "buyer_description" "text",
    "buyer_uom" "text",
    "buyer_line_sequence" integer,
    "gtin_case" "text"
);


ALTER TABLE "public"."sales_po_line" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_po_line" IS 'Individual products within an order. One row per product per order with snapshot pricing at time of order. Buyer-side identifiers (buyer_part_number, buyer_description, buyer_uom, buyer_line_sequence, gtin_case) are populated from inbound SPS 850 documents and echoed on outbound 856/810.';



COMMENT ON COLUMN "public"."sales_po_line"."price_per_case" IS 'Snapshot from sales_product_price; resolved by customer_id first, then customer_group_id, then default fob price; read-only';



COMMENT ON COLUMN "public"."sales_po_line"."buyer_part_number" IS 'EDI-only. Snapshot from 850 LineItem BuyerPartNumber. Resolved against sales_product_buyer_part to set sales_product_id at PO receipt; preserved here so outbound 856/810 echo the original.';



COMMENT ON COLUMN "public"."sales_po_line"."buyer_description" IS 'EDI-only. Snapshot of the buyer''s line description from 850. Echoed on 810 invoice lines.';



COMMENT ON COLUMN "public"."sales_po_line"."buyer_uom" IS 'EDI-only. Buyer''s ordering UOM from 850 LineItem (e.g. CA, EA). Free text - buyers'' codes don''t always map to sys_uom.';



COMMENT ON COLUMN "public"."sales_po_line"."buyer_line_sequence" IS 'EDI-only. Line sequence number from 850 LineItem PO101. Required on outbound 856 LIN and 810 IT1 to maintain line correlation.';



COMMENT ON COLUMN "public"."sales_po_line"."gtin_case" IS 'EDI-only. Case-level GTIN-14 snapshot at PO receipt. Pulled from sales_product_buyer_part.gtin_case; copied here so outbound 856/810 don''t depend on the lookup row still existing.';



CREATE TABLE IF NOT EXISTS "public"."sales_product_price" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "sales_fob_id" "text" NOT NULL,
    "sales_customer_group_id" "text",
    "sales_customer_id" "text",
    "price_per_case" numeric NOT NULL,
    "effective_from" "date" NOT NULL,
    "effective_to" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_product_price" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_product_price" IS 'Manages product pricing with three tiers of specificity and date ranges to track price changes over time. When a price changes, the current row gets an effective_to date and a new row is created. Currency always uses the org default from org.currency.';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_edi_inbound_message" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_sps_trading_partner_id" "text",
    "document_type" "text" NOT NULL,
    "sps_message_id" "text",
    "source_filename" "text",
    "raw_body" "text" NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "parsed_at" timestamp with time zone,
    "parse_error" "text",
    "sales_po_id" "uuid",
    "acknowledgement_sent_at" timestamp with time zone,
    "acknowledgement_status" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "sales_sps_edi_inbound_message_acknowledgement_status_check" CHECK (("acknowledgement_status" = ANY (ARRAY['Accepted'::"text", 'AcceptedWithErrors'::"text", 'Rejected'::"text"])))
);


ALTER TABLE "public"."sales_sps_edi_inbound_message" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_edi_inbound_message" IS 'SPS-only. Immutable archive of every inbound EDI document from SPS Commerce. Parser writes raw payload first, then attempts to apply; parsed_at + sales_po_id are filled in on success. Failed parses keep raw_body for replay. Used for compliance / audit (proving what the buyer actually sent) and for replay after parser bugs.';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."document_type" IS 'X12 transaction set number (e.g. 850, 860, 870, 997).';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."sps_message_id" IS 'SPS Commerce message identifier from the API or SFTP filename. Used to deduplicate retries.';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."source_filename" IS 'Original filename when delivered via SFTP. Useful for support requests to SPS.';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."raw_body" IS 'Verbatim payload as received. Do not modify. Replay parser against this if upstream code changes.';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."parse_error" IS 'Set when parse fails. Operator triages, fixes mapping (often a missing sales_product_buyer_part row), then replays.';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."sales_po_id" IS 'Resolved PO once the parse succeeds and the document is applied. NULL for unparsed messages and for non-PO document types (e.g. 997 acknowledgements).';



COMMENT ON COLUMN "public"."sales_sps_edi_inbound_message"."acknowledgement_status" IS 'Status of the 997 Functional Acknowledgement we sent in response. Required by SPS within 24h of receipt.';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_po_asn" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_sps_shipment_container_id" "uuid" NOT NULL,
    "sales_po_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'Pending'::"text" NOT NULL,
    "sent_at" timestamp with time zone,
    "acknowledged_at" timestamp with time zone,
    "sps_message_id" "text",
    "raw_outbound" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    CONSTRAINT "sales_sps_po_asn_status_check" CHECK (("status" = ANY (ARRAY['Pending'::"text", 'Sent'::"text", 'Acknowledged'::"text", 'Rejected'::"text", 'Cancelled'::"text"])))
);


ALTER TABLE "public"."sales_sps_po_asn" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_po_asn" IS 'SPS-only. Outbound 856 Advance Ship Notice header. One row per PO per container. Truck-/voyage-level info (BOL, carrier, ship_date) lives on sales_shipment; container info (number, seal, type) lives on sales_shipment_container; carton-level detail lives on sales_po_asn_carton. A PO split across two containers gets two ASN rows.';



COMMENT ON COLUMN "public"."sales_sps_po_asn"."sales_sps_shipment_container_id" IS 'Container this PO is loaded in. Reach the booking via sales_shipment_container.sales_shipment_id.';



COMMENT ON COLUMN "public"."sales_sps_po_asn"."status" IS 'Outbound lifecycle: Pending (built but not sent) -> Sent (transmitted to SPS) -> Acknowledged (SPS 997 received) | Rejected (functional acknowledgement failed). Cancelled if voided before send.';



COMMENT ON COLUMN "public"."sales_sps_po_asn"."sent_at" IS 'Timestamp the 856 was transmitted to SPS. Drives buyer SLA windows (most retailers require ASN within 1h of departure).';



COMMENT ON COLUMN "public"."sales_sps_po_asn"."sps_message_id" IS 'SPS-assigned identifier returned at submission. Used to correlate inbound 997 acknowledgements back to this row.';



COMMENT ON COLUMN "public"."sales_sps_po_asn"."raw_outbound" IS 'Verbatim payload we transmitted. Kept for audit and for replay if SPS reports loss.';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_po_asn_carton" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_sps_po_asn_id" "uuid" NOT NULL,
    "sales_po_line_id" "uuid" NOT NULL,
    "sales_po_fulfillment_id" "uuid",
    "parent_carton_id" "uuid",
    "carton_type" "text" DEFAULT 'Pack'::"text" NOT NULL,
    "sscc" "text" NOT NULL,
    "quantity" numeric NOT NULL,
    "actual_net_weight" numeric,
    "weight_uom" "text",
    "pack_date" "date",
    "best_by_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL,
    "pack_session_id" "uuid",
    CONSTRAINT "sales_sps_po_asn_carton_carton_type_check" CHECK (("carton_type" = ANY (ARRAY['Tare'::"text", 'Pack'::"text", 'Item'::"text"])))
);


ALTER TABLE "public"."sales_sps_po_asn_carton" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_po_asn_carton" IS 'SPS-only. Carton-level detail for an outbound 856 ASN. One row per physical carton/pallet bearing a UCC-128 SSCC label. Self-referencing parent_carton_id models pallet→case nesting; flat (case-only) ASNs leave it NULL. SSCC is globally unique per GS1 spec — never reuse, even after a carton is consumed.';



COMMENT ON COLUMN "public"."sales_sps_po_asn_carton"."parent_carton_id" IS 'Self-FK for pallet→case nesting. NULL = top-level carton on the ASN. Points at a row whose carton_type is Tare. Cascade delete keeps a pallet and its cases consistent.';



COMMENT ON COLUMN "public"."sales_sps_po_asn_carton"."carton_type" IS 'GS1 Hierarchy Level: Tare (pallet, HL*P*T), Pack (case, HL*P*P), Item (each, HL*P*I). Drives the 856 HL segment hierarchy code.';



COMMENT ON COLUMN "public"."sales_sps_po_asn_carton"."sscc" IS 'GS1 Serial Shipping Container Code (SSCC-18). Printed as the UCC-128 barcode on the carton and transmitted on 856 MAN*GM. Globally unique — must never be reused, including across cancelled shipments.';



COMMENT ON COLUMN "public"."sales_sps_po_asn_carton"."actual_net_weight" IS 'Required only for catch-weight (is_catch_weight) products where the actual carton weight differs from the sales_product spec. NULL for fixed-weight cases.';



COMMENT ON COLUMN "public"."sales_sps_po_asn_carton"."pack_session_id" IS 'Lot traceability link via pack_session. Required when sales_product.is_fsma_traceable is true so a recall can be enacted from a buyer scan back to the production lot. Replaces prior pack_lot_id FK.';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_product_buyer_part" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "sales_customer_id" "text" NOT NULL,
    "buyer_part_number" "text" NOT NULL,
    "buyer_description" "text",
    "buyer_uom" "text",
    "gtin_case" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_sps_product_buyer_part" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_product_buyer_part" IS 'SPS-only. Cross-reference from a buyer''s part number to our sales_product. Inbound 850 line items carry the buyer''s SKU; we look it up here (sales_customer_id + buyer_part_number) to resolve the line to a sales_product. The unique constraint enforces that a buyer''s part number maps to exactly one of our products.';



COMMENT ON COLUMN "public"."sales_sps_product_buyer_part"."buyer_part_number" IS 'The buyer''s SKU/item number for this product. Sent in 850 LineItem and echoed on 856/810.';



COMMENT ON COLUMN "public"."sales_sps_product_buyer_part"."buyer_description" IS 'Buyer''s description text snapshot; useful for human review of EDI documents but not authoritative.';



COMMENT ON COLUMN "public"."sales_sps_product_buyer_part"."buyer_uom" IS 'Buyer''s ordering unit of measure as it appears in their 850 (e.g. CA, EA). Free text, not FK''d to sys_uom because buyer codes don''t always align.';



COMMENT ON COLUMN "public"."sales_sps_product_buyer_part"."gtin_case" IS 'Case-level GTIN-14 used on 856 cartons and 810 invoice lines. Distinct from sales_product.gtin which is the consumer-unit GTIN.';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_shipment" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "bol_number" "text" NOT NULL,
    "booking_number" "text",
    "carrier_scac" "text",
    "carrier_pro_number" "text",
    "ship_date" "date" NOT NULL,
    "estimated_delivery_date" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_sps_shipment" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_shipment" IS 'SPS-only. Booking / voyage record. One row per carrier dispatch. For ocean carriers (Young Brothers) one booking carries multiple physical containers; for trucking one booking is one trailer. Container-level data lives on sales_shipment_container. Per-PO EDI state lives on sales_po_asn.';



COMMENT ON COLUMN "public"."sales_sps_shipment"."bol_number" IS 'Master Bill of Lading number for the booking. Echoed on every 856 BSN02 for POs riding this booking. Unique within the org.';



COMMENT ON COLUMN "public"."sales_sps_shipment"."booking_number" IS 'Carrier booking / reservation identifier (e.g. Young Brothers booking number). Distinct from bol_number for ocean carriers; NULL for trucking where BOL serves both purposes.';



COMMENT ON COLUMN "public"."sales_sps_shipment"."carrier_scac" IS 'Standard Carrier Alpha Code for the carrier (e.g. YOBR for Young Brothers). Sent on 856 TD5.';



COMMENT ON COLUMN "public"."sales_sps_shipment"."carrier_pro_number" IS 'Carrier''s PRO / tracking number for the booking. Sent on 856 TD3 segment.';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_shipment_container" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_sps_shipment_id" "uuid" NOT NULL,
    "container_number" "text" NOT NULL,
    "seal_number" "text",
    "sales_container_type_id" "text",
    "temperature_uom" "text",
    "temperature_setpoint" numeric,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_sps_shipment_container" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_shipment_container" IS 'SPS-only. Physical container or trailer in a booking. One row per container; an ocean booking with Young Brothers carrying separate reefers for cucumbers and lettuce yields two rows under one sales_shipment. Trucking shipments yield one row (the trailer).';



COMMENT ON COLUMN "public"."sales_sps_shipment_container"."container_number" IS 'Container number stenciled on the box (ocean) or trailer number (trucking). Sent on 856 TD3 / Equipment segment. Unique within a shipment so the same booking can''t have two rows for the same container.';



COMMENT ON COLUMN "public"."sales_sps_shipment_container"."seal_number" IS 'Seal number applied at loading. Required by Costco and most retail buyers for receiving; sent on 856 TD3.';



COMMENT ON COLUMN "public"."sales_sps_shipment_container"."sales_container_type_id" IS 'Container type (20-foot dry, 40-foot reefer, etc.) from the existing sales_container_type lookup. Drives capacity (maximum_spaces) and dimensions on the 856.';



COMMENT ON COLUMN "public"."sales_sps_shipment_container"."temperature_setpoint" IS 'Reefer setpoint temperature. Required on 856 TD4 by buyers with cold-chain compliance (Costco, Whole Foods).';



CREATE TABLE IF NOT EXISTS "public"."sales_sps_trading_partner" (
    "id" "text" NOT NULL,
    "org_id" "text" NOT NULL,
    "sales_customer_id" "text" NOT NULL,
    "sps_partner_id" "text" NOT NULL,
    "sps_vendor_number" "text",
    "acknowledgement_required" boolean DEFAULT false NOT NULL,
    "asn_required" boolean DEFAULT false NOT NULL,
    "invoice_required" boolean DEFAULT false NOT NULL,
    "default_carrier_scac" "text",
    "default_payment_terms_net_days" integer,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sales_sps_trading_partner" OWNER TO "postgres";


COMMENT ON TABLE "public"."sales_sps_trading_partner" IS 'SPS-only. EDI trading partner registry. Bridges an SPS partner identity (Costco, Safeway, etc.) to a sales_customer and declares which document flows (PO Acknowledgment / ASN / Invoice) are required for that partner. Inbound 850 routes to a partner via sps_partner_id; outbound 856/810 use the partner''s flags to decide whether to send.';



COMMENT ON COLUMN "public"."sales_sps_trading_partner"."sps_partner_id" IS 'SPS Commerce partner identifier; matches the buyer code in the 850 envelope. Used to route inbound documents to the correct sales_customer.';



COMMENT ON COLUMN "public"."sales_sps_trading_partner"."sps_vendor_number" IS 'Our vendor number assigned by the buyer (e.g. Costco vendor #). Echoed back on outbound 856/810.';



COMMENT ON COLUMN "public"."sales_sps_trading_partner"."acknowledgement_required" IS 'Send 855 Purchase Order Acknowledgement after receiving 850.';



COMMENT ON COLUMN "public"."sales_sps_trading_partner"."asn_required" IS 'Send 856 Advance Ship Notice when the PO ships.';



COMMENT ON COLUMN "public"."sales_sps_trading_partner"."invoice_required" IS 'Send 810 Invoice after the ASN is sent. Some partners self-invoice from receipt.';



COMMENT ON COLUMN "public"."sales_sps_trading_partner"."default_carrier_scac" IS 'Fallback Standard Carrier Alpha Code used on outbound 856 when the inbound 850 omits routing.';



CREATE TABLE IF NOT EXISTS "public"."sys_uom" (
    "id" "text" NOT NULL,
    "category" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."sys_uom" OWNER TO "postgres";


COMMENT ON TABLE "public"."sys_uom" IS 'Standardized measurement units shared across all organizations for consistent data entry and calculations throughout the system.';



ALTER TABLE ONLY "public"."edi_crodeon_weather"
    ADD CONSTRAINT "edi_crodeon_weather_pkey" PRIMARY KEY ("org_id", "reading_at");



ALTER TABLE ONLY "public"."edi_qb_expense_line"
    ADD CONSTRAINT "edi_qb_expense_line_pkey" PRIMARY KEY ("org_id", "expense_id", "line_num");



ALTER TABLE ONLY "public"."edi_qb_expense"
    ADD CONSTRAINT "edi_qb_expense_pkey" PRIMARY KEY ("org_id", "id");



ALTER TABLE ONLY "public"."edi_qb_invoice_line"
    ADD CONSTRAINT "edi_qb_invoice_line_pkey" PRIMARY KEY ("org_id", "invoice_id", "line_num");



ALTER TABLE ONLY "public"."edi_qb_invoice"
    ADD CONSTRAINT "edi_qb_invoice_pkey" PRIMARY KEY ("org_id", "id");



ALTER TABLE ONLY "public"."fin_expense"
    ADD CONSTRAINT "fin_expense_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_lab"
    ADD CONSTRAINT "fsafe_lab_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_lab_test"
    ADD CONSTRAINT "fsafe_lab_test_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_pest_result"
    ADD CONSTRAINT "fsafe_pest_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_test_hold"
    ADD CONSTRAINT "fsafe_test_hold_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_test_hold_po"
    ADD CONSTRAINT "fsafe_test_hold_po_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_chemistry_result"
    ADD CONSTRAINT "grow_chemistry_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "grow_cuke_gh_row_planting_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_cuke_rotation"
    ADD CONSTRAINT "grow_cuke_rotation_org_id_farm_id_slot_num_key" UNIQUE ("org_id", "farm_id", "slot_num");



ALTER TABLE ONLY "public"."grow_cuke_rotation"
    ADD CONSTRAINT "grow_cuke_rotation_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_cuke_seed_batch"
    ADD CONSTRAINT "grow_cuke_seed_batch_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_cycle_pattern"
    ADD CONSTRAINT "grow_cycle_pattern_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe"
    ADD CONSTRAINT "grow_fertigation_recipe_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_site"
    ADD CONSTRAINT "grow_fertigation_recipe_site_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_grade"
    ADD CONSTRAINT "grow_grade_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "grow_harvest_container_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "grow_lettuce_seed_mix_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix"
    ADD CONSTRAINT "grow_lettuce_seed_mix_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_monitoring_metric"
    ADD CONSTRAINT "grow_monitoring_metric_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "grow_monitoring_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_spray_compliance"
    ADD CONSTRAINT "grow_spray_compliance_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "grow_spray_equipment_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_task_photo"
    ADD CONSTRAINT "grow_task_photo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_task_seed_batch"
    ADD CONSTRAINT "grow_task_seed_batch_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_trial_type"
    ADD CONSTRAINT "grow_trial_type_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_variety"
    ADD CONSTRAINT "grow_variety_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_department"
    ADD CONSTRAINT "hr_department_pkey" PRIMARY KEY ("org_id", "id");



ALTER TABLE ONLY "public"."hr_disciplinary_warning"
    ADD CONSTRAINT "hr_disciplinary_warning_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_pkey" PRIMARY KEY ("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "hr_employee_review_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_module_access"
    ADD CONSTRAINT "hr_module_access_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_payroll"
    ADD CONSTRAINT "hr_payroll_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_time_off_request"
    ADD CONSTRAINT "hr_time_off_request_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_travel_request"
    ADD CONSTRAINT "hr_travel_request_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hr_work_authorization"
    ADD CONSTRAINT "hr_work_authorization_pkey" PRIMARY KEY ("org_id", "id");



ALTER TABLE ONLY "public"."invnt_category"
    ADD CONSTRAINT "invnt_category_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invnt_lot"
    ADD CONSTRAINT "invnt_lot_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invnt_po_received"
    ADD CONSTRAINT "invnt_po_received_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invnt_vendor"
    ADD CONSTRAINT "invnt_vendor_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "maint_request_invnt_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maint_request_photo"
    ADD CONSTRAINT "maint_request_photo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_corrective_action_choice"
    ADD CONSTRAINT "ops_corrective_action_choice_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_task"
    ADD CONSTRAINT "ops_task_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_task_schedule"
    ADD CONSTRAINT "ops_task_schedule_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_task_template"
    ADD CONSTRAINT "ops_task_template_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_template"
    ADD CONSTRAINT "ops_template_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_template_question"
    ADD CONSTRAINT "ops_template_question_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_template_result_photo"
    ADD CONSTRAINT "ops_template_result_photo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_training_attendee"
    ADD CONSTRAINT "ops_training_attendee_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_training"
    ADD CONSTRAINT "ops_training_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ops_training_type"
    ADD CONSTRAINT "ops_training_type_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_business_rule"
    ADD CONSTRAINT "org_business_rule_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_equipment"
    ADD CONSTRAINT "org_equipment_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_farm"
    ADD CONSTRAINT "org_farm_pkey" PRIMARY KEY ("org_id", "id");



ALTER TABLE ONLY "public"."org_module"
    ADD CONSTRAINT "org_module_pkey" PRIMARY KEY ("org_id", "sys_module_id");



ALTER TABLE ONLY "public"."org"
    ADD CONSTRAINT "org_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_quickbooks_token"
    ADD CONSTRAINT "org_quickbooks_token_pkey" PRIMARY KEY ("org_id");



ALTER TABLE ONLY "public"."org_site_category"
    ADD CONSTRAINT "org_site_category_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_block"
    ADD CONSTRAINT "org_site_cuke_gh_block_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh"
    ADD CONSTRAINT "org_site_cuke_gh_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_row"
    ADD CONSTRAINT "org_site_cuke_gh_row_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_site_housing_area"
    ADD CONSTRAINT "org_site_housing_area_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_site_housing"
    ADD CONSTRAINT "org_site_housing_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_site"
    ADD CONSTRAINT "org_site_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."org_sub_module"
    ADD CONSTRAINT "org_sub_module_pkey" PRIMARY KEY ("org_id", "sys_sub_module_id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_fail_category"
    ADD CONSTRAINT "pack_productivity_fail_category_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_session_labor_hour"
    ADD CONSTRAINT "pack_productivity_hour_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "pack_session_leftover_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_shelf_life_metric"
    ADD CONSTRAINT "pack_shelf_life_metric_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_container_type"
    ADD CONSTRAINT "sales_container_type_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_crm_external_product"
    ADD CONSTRAINT "sales_crm_external_product_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_crm_store"
    ADD CONSTRAINT "sales_crm_store_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_photo"
    ADD CONSTRAINT "sales_crm_store_visit_photo_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit"
    ADD CONSTRAINT "sales_crm_store_visit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_result"
    ADD CONSTRAINT "sales_crm_store_visit_result_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_customer_group"
    ADD CONSTRAINT "sales_customer_group_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_customer"
    ADD CONSTRAINT "sales_customer_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_fob"
    ADD CONSTRAINT "sales_fob_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_invoice"
    ADD CONSTRAINT "sales_invoice_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_pallet_allocation"
    ADD CONSTRAINT "sales_pallet_allocation_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_pallet"
    ADD CONSTRAINT "sales_pallet_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_po_fulfillment"
    ADD CONSTRAINT "sales_po_fulfillment_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_po_line"
    ADD CONSTRAINT "sales_po_line_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_edi_inbound_message"
    ADD CONSTRAINT "sales_sps_edi_inbound_message_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn"
    ADD CONSTRAINT "sales_sps_po_asn_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_product_buyer_part"
    ADD CONSTRAINT "sales_sps_product_buyer_part_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_shipment_container"
    ADD CONSTRAINT "sales_sps_shipment_container_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_shipment"
    ADD CONSTRAINT "sales_sps_shipment_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales_sps_trading_partner"
    ADD CONSTRAINT "sales_sps_trading_partner_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sys_access_level"
    ADD CONSTRAINT "sys_access_level_level_key" UNIQUE ("level");



ALTER TABLE ONLY "public"."sys_sub_module"
    ADD CONSTRAINT "sys_sub_module_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sys_uom"
    ADD CONSTRAINT "sys_uom_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fsafe_lab"
    ADD CONSTRAINT "uq_fsafe_lab" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_lab_test"
    ADD CONSTRAINT "uq_fsafe_lab_test" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_test_hold_po"
    ADD CONSTRAINT "uq_fsafe_test_hold_po" UNIQUE ("fsafe_test_hold_id", "sales_po_id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "uq_grow_cuke_gh_row_planting_row_scenario" UNIQUE ("org_site_cuke_gh_row_id", "scenario");



ALTER TABLE ONLY "public"."grow_cycle_pattern"
    ADD CONSTRAINT "uq_grow_cycle_pattern" UNIQUE ("org_id", "farm_id", "id");



ALTER TABLE ONLY "public"."grow_disease"
    ADD CONSTRAINT "uq_grow_disease" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "uq_grow_fertigation" UNIQUE ("ops_task_tracker_id", "equipment_id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe"
    ADD CONSTRAINT "uq_grow_fertigation_recipe" UNIQUE ("org_id", "farm_id", "id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_site"
    ADD CONSTRAINT "uq_grow_fertigation_recipe_site" UNIQUE ("grow_fertigation_recipe_id", "site_id");



ALTER TABLE ONLY "public"."grow_grade"
    ADD CONSTRAINT "uq_grow_grade_name" UNIQUE ("farm_id", "name");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "uq_grow_harvest_container" UNIQUE ("org_id", "farm_id", "id", "grow_variety_id", "grow_grade_id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "uq_grow_lettuce_seed_batch" UNIQUE ("org_id", "batch_code");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix"
    ADD CONSTRAINT "uq_grow_lettuce_seed_mix" UNIQUE ("org_id", "farm_id", "id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "uq_grow_lettuce_seed_mix_item" UNIQUE ("grow_lettuce_seed_mix_id", "invnt_item_id");



ALTER TABLE ONLY "public"."grow_monitoring_metric"
    ADD CONSTRAINT "uq_grow_monitoring_metric" UNIQUE ("org_id", "farm_id", "site_category", "name");



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "uq_grow_monitoring_result" UNIQUE ("ops_task_tracker_id", "grow_monitoring_metric_id", "monitoring_station");



ALTER TABLE ONLY "public"."grow_pest"
    ADD CONSTRAINT "uq_grow_pest" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "uq_grow_spray_equipment" UNIQUE ("ops_task_tracker_id", "equipment_id");



ALTER TABLE ONLY "public"."grow_trial_type"
    ADD CONSTRAINT "uq_grow_trial_type" UNIQUE ("org_id", "farm_id", "id");



ALTER TABLE ONLY "public"."grow_variety"
    ADD CONSTRAINT "uq_grow_variety_name" UNIQUE ("farm_id", "name");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "uq_hr_employee_name" UNIQUE ("org_id", "first_name", "last_name");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "uq_hr_employee_review_quarter" UNIQUE ("org_id", "hr_employee_id", "review_year", "review_quarter");



ALTER TABLE ONLY "public"."hr_module_access"
    ADD CONSTRAINT "uq_hr_module_access" UNIQUE ("hr_employee_id", "sys_module_id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "uq_invnt_item" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."invnt_lot"
    ADD CONSTRAINT "uq_invnt_lot" UNIQUE ("org_id", "invnt_item_id", "lot_number");



ALTER TABLE ONLY "public"."invnt_vendor"
    ADD CONSTRAINT "uq_invnt_vendor" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "uq_maint_request_invnt_item" UNIQUE ("maint_request_id", "invnt_item_id");



ALTER TABLE ONLY "public"."ops_corrective_action_choice"
    ADD CONSTRAINT "uq_ops_corrective_action_choice" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."ops_task"
    ADD CONSTRAINT "uq_ops_task_name" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."ops_task_template"
    ADD CONSTRAINT "uq_ops_task_template" UNIQUE ("ops_task_id", "ops_template_id");



ALTER TABLE ONLY "public"."ops_training_attendee"
    ADD CONSTRAINT "uq_ops_training_attendee" UNIQUE ("ops_training_id", "hr_employee_id");



ALTER TABLE ONLY "public"."ops_training_type"
    ADD CONSTRAINT "uq_ops_training_type" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."org"
    ADD CONSTRAINT "uq_org_name" UNIQUE ("name");



ALTER TABLE ONLY "public"."org_site_cuke_gh_block"
    ADD CONSTRAINT "uq_org_site_cuke_gh_block_site_block" UNIQUE ("site_id", "block_number");



ALTER TABLE ONLY "public"."org_site_cuke_gh_row"
    ADD CONSTRAINT "uq_org_site_cuke_gh_row_site_row" UNIQUE ("site_id", "row_number");



ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "uq_pack_session" UNIQUE ("org_id", "farm_id", "pack_date", "sales_product_id", "harvest_date");



ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "uq_pack_session_leftover" UNIQUE ("org_id", "farm_id", "pack_date");



ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "uq_pack_shelf_life_result" UNIQUE ("pack_shelf_life_id", "pack_shelf_life_metric_id", "observation_date");



ALTER TABLE ONLY "public"."sales_container_type"
    ADD CONSTRAINT "uq_sales_container_type" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."sales_crm_external_product"
    ADD CONSTRAINT "uq_sales_crm_external_product" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."sales_crm_store"
    ADD CONSTRAINT "uq_sales_crm_store" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."sales_customer_group"
    ADD CONSTRAINT "uq_sales_customer_group" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."sales_customer"
    ADD CONSTRAINT "uq_sales_customer_org_name" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."sales_fob"
    ADD CONSTRAINT "uq_sales_fob" UNIQUE ("org_id", "id");



ALTER TABLE ONLY "public"."sales_pallet"
    ADD CONSTRAINT "uq_sales_pallet_number" UNIQUE ("org_id", "target_invoice_date", "pallet_number");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "uq_sales_po_asn_carton_sscc" UNIQUE ("sscc");



ALTER TABLE ONLY "public"."sales_sps_po_asn"
    ADD CONSTRAINT "uq_sales_po_asn_container_po" UNIQUE ("sales_sps_shipment_container_id", "sales_po_id");



ALTER TABLE ONLY "public"."sales_po_line"
    ADD CONSTRAINT "uq_sales_po_line" UNIQUE ("sales_po_id", "sales_product_id");



ALTER TABLE ONLY "public"."sales_sps_product_buyer_part"
    ADD CONSTRAINT "uq_sales_product_buyer_part" UNIQUE ("sales_customer_id", "buyer_part_number");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "uq_sales_product_name" UNIQUE ("farm_id", "name");



ALTER TABLE ONLY "public"."sales_sps_shipment"
    ADD CONSTRAINT "uq_sales_shipment_bol" UNIQUE ("org_id", "bol_number");



ALTER TABLE ONLY "public"."sales_sps_shipment_container"
    ADD CONSTRAINT "uq_sales_shipment_container" UNIQUE ("sales_sps_shipment_id", "container_number");



ALTER TABLE ONLY "public"."sales_sps_trading_partner"
    ADD CONSTRAINT "uq_sales_trading_partner_sps" UNIQUE ("org_id", "sps_partner_id");



ALTER TABLE ONLY "public"."sys_access_level"
    ADD CONSTRAINT "uq_sys_access_level_name" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sys_module"
    ADD CONSTRAINT "uq_sys_module_name" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sys_sub_module"
    ADD CONSTRAINT "uq_sys_sub_module" UNIQUE ("sys_module_id", "id");



CREATE UNIQUE INDEX "grow_cuke_rotation_one_anchor" ON "public"."grow_cuke_rotation" USING "btree" ("org_id", "farm_id") WHERE ("is_anchor" = true);



CREATE INDEX "idx_edi_qb_expense_line_account" ON "public"."edi_qb_expense_line" USING "btree" ("org_id", "account_name");



CREATE INDEX "idx_edi_qb_expense_line_class" ON "public"."edi_qb_expense_line" USING "btree" ("org_id", "class_name");



CREATE INDEX "idx_edi_qb_expense_org_payee" ON "public"."edi_qb_expense" USING "btree" ("org_id", "payee_name");



CREATE INDEX "idx_edi_qb_expense_org_transaction_date" ON "public"."edi_qb_expense" USING "btree" ("org_id", "transaction_date" DESC);



CREATE INDEX "idx_edi_qb_invoice_invoice_number" ON "public"."edi_qb_invoice" USING "btree" ("org_id", "invoice_number");



CREATE INDEX "idx_edi_qb_invoice_line_item" ON "public"."edi_qb_invoice_line" USING "btree" ("org_id", "item_name");



CREATE INDEX "idx_edi_qb_invoice_org_customer" ON "public"."edi_qb_invoice" USING "btree" ("org_id", "customer_id");



CREATE INDEX "idx_edi_qb_invoice_org_invoice_date" ON "public"."edi_qb_invoice" USING "btree" ("org_id", "invoice_date" DESC);



CREATE INDEX "idx_fin_expense_farm" ON "public"."fin_expense" USING "btree" ("farm_id");



CREATE INDEX "idx_fsafe_lab_org" ON "public"."fsafe_lab" USING "btree" ("org_id");



CREATE INDEX "idx_fsafe_lab_test_org" ON "public"."fsafe_lab_test" USING "btree" ("org_id");



CREATE INDEX "idx_fsafe_pest_result_site" ON "public"."fsafe_pest_result" USING "btree" ("site_id");



CREATE INDEX "idx_fsafe_pest_result_tracker" ON "public"."fsafe_pest_result" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_fsafe_result_lab" ON "public"."fsafe_result" USING "btree" ("fsafe_lab_id");



CREATE INDEX "idx_fsafe_result_org" ON "public"."fsafe_result" USING "btree" ("org_id");



CREATE INDEX "idx_fsafe_result_original" ON "public"."fsafe_result" USING "btree" ("fsafe_result_id_original");



CREATE INDEX "idx_fsafe_result_site" ON "public"."fsafe_result" USING "btree" ("site_id");



CREATE INDEX "idx_fsafe_result_status" ON "public"."fsafe_result" USING "btree" ("org_id", "status");



CREATE INDEX "idx_fsafe_result_test" ON "public"."fsafe_result" USING "btree" ("fsafe_lab_test_id");



CREATE INDEX "idx_fsafe_result_test_hold" ON "public"."fsafe_result" USING "btree" ("fsafe_test_hold_id");



CREATE INDEX "idx_fsafe_test_hold_customer" ON "public"."fsafe_test_hold" USING "btree" ("sales_customer_id");



CREATE INDEX "idx_fsafe_test_hold_farm" ON "public"."fsafe_test_hold" USING "btree" ("farm_id");



CREATE INDEX "idx_fsafe_test_hold_org" ON "public"."fsafe_test_hold" USING "btree" ("org_id");



CREATE INDEX "idx_fsafe_test_hold_pack_date" ON "public"."fsafe_test_hold" USING "btree" ("org_id", "farm_id", "pack_date", "harvest_date");



CREATE INDEX "idx_fsafe_test_hold_po_org" ON "public"."fsafe_test_hold_po" USING "btree" ("org_id");



CREATE INDEX "idx_fsafe_test_hold_po_sales_po" ON "public"."fsafe_test_hold_po" USING "btree" ("sales_po_id");



CREATE INDEX "idx_fsafe_test_hold_po_test_hold" ON "public"."fsafe_test_hold_po" USING "btree" ("fsafe_test_hold_id");



CREATE INDEX "idx_grow_chemistry_result_nutrient" ON "public"."grow_chemistry_result" USING "btree" ("nutrient");



CREATE INDEX "idx_grow_chemistry_result_org_date" ON "public"."grow_chemistry_result" USING "btree" ("org_id", "sample_date");



CREATE INDEX "idx_grow_chemistry_result_site" ON "public"."grow_chemistry_result" USING "btree" ("site_id");



CREATE INDEX "idx_grow_cuke_gh_row_planting_org" ON "public"."grow_cuke_gh_row_planting" USING "btree" ("org_id");



CREATE INDEX "idx_grow_cuke_gh_row_planting_row" ON "public"."grow_cuke_gh_row_planting" USING "btree" ("org_site_cuke_gh_row_id");



CREATE INDEX "idx_grow_cuke_gh_row_planting_scenario" ON "public"."grow_cuke_gh_row_planting" USING "btree" ("scenario");



CREATE INDEX "idx_grow_cuke_seed_batch_date" ON "public"."grow_cuke_seed_batch" USING "btree" ("seeding_date");



CREATE INDEX "idx_grow_cuke_seed_batch_item" ON "public"."grow_cuke_seed_batch" USING "btree" ("invnt_item_id");



CREATE INDEX "idx_grow_cuke_seed_batch_org" ON "public"."grow_cuke_seed_batch" USING "btree" ("org_id");



CREATE INDEX "idx_grow_cuke_seed_batch_site_date" ON "public"."grow_cuke_seed_batch" USING "btree" ("site_id", "seeding_date");



CREATE INDEX "idx_grow_cuke_seed_batch_tracker" ON "public"."grow_cuke_seed_batch" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_fertigation_recipe_item_recipe" ON "public"."grow_fertigation_recipe_item" USING "btree" ("grow_fertigation_recipe_id");



CREATE INDEX "idx_grow_fertigation_recipe_site_recipe" ON "public"."grow_fertigation_recipe_site" USING "btree" ("grow_fertigation_recipe_id");



CREATE INDEX "idx_grow_fertigation_tracker" ON "public"."grow_fertigation" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_harvest_weight_container" ON "public"."grow_harvest_weight" USING "btree" ("grow_harvest_container_id");



CREATE INDEX "idx_grow_harvest_weight_cuke_batch" ON "public"."grow_harvest_weight" USING "btree" ("grow_cuke_seed_batch_id");



CREATE INDEX "idx_grow_harvest_weight_lettuce_batch" ON "public"."grow_harvest_weight" USING "btree" ("grow_lettuce_seed_batch_id");



CREATE INDEX "idx_grow_harvest_weight_tracker" ON "public"."grow_harvest_weight" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_lettuce_seed_batch_item" ON "public"."grow_lettuce_seed_batch" USING "btree" ("invnt_item_id");



CREATE INDEX "idx_grow_lettuce_seed_batch_mix" ON "public"."grow_lettuce_seed_batch" USING "btree" ("grow_lettuce_seed_mix_id");



CREATE INDEX "idx_grow_lettuce_seed_batch_org" ON "public"."grow_lettuce_seed_batch" USING "btree" ("org_id");



CREATE INDEX "idx_grow_lettuce_seed_batch_tracker" ON "public"."grow_lettuce_seed_batch" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_monitoring_metric_farm" ON "public"."grow_monitoring_metric" USING "btree" ("org_id", "farm_id", "site_category");



CREATE INDEX "idx_grow_monitoring_result_site" ON "public"."grow_monitoring_result" USING "btree" ("site_id");



CREATE INDEX "idx_grow_monitoring_result_tracker" ON "public"."grow_monitoring_result" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_scout_result_scouting" ON "public"."grow_scout_result" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_spray_compliance_item" ON "public"."grow_spray_compliance" USING "btree" ("invnt_item_id");



CREATE INDEX "idx_grow_spray_equipment_equip" ON "public"."grow_spray_equipment" USING "btree" ("equipment_id");



CREATE INDEX "idx_grow_spray_equipment_spraying" ON "public"."grow_spray_equipment" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_spray_input_compliance" ON "public"."grow_spray_input" USING "btree" ("grow_spray_compliance_id");



CREATE INDEX "idx_grow_spray_input_spraying" ON "public"."grow_spray_input" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_task_photo_tracker" ON "public"."grow_task_photo" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_task_seed_batch_tracker" ON "public"."grow_task_seed_batch" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_grow_weather_reading_at" ON "public"."edi_crodeon_weather" USING "btree" ("reading_at" DESC);



CREATE INDEX "idx_grow_weather_reading_org_at" ON "public"."edi_crodeon_weather" USING "btree" ("org_id", "reading_at" DESC);



CREATE INDEX "idx_hr_department_active" ON "public"."hr_department" USING "btree" ("org_id", "is_deleted");



CREATE INDEX "idx_hr_department_org_id" ON "public"."hr_department" USING "btree" ("org_id");



CREATE INDEX "idx_hr_disciplinary_warning_date" ON "public"."hr_disciplinary_warning" USING "btree" ("hr_employee_id", "warning_date");



CREATE INDEX "idx_hr_disciplinary_warning_employee" ON "public"."hr_disciplinary_warning" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_hr_disciplinary_warning_org_id" ON "public"."hr_disciplinary_warning" USING "btree" ("org_id");



CREATE INDEX "idx_hr_disciplinary_warning_status" ON "public"."hr_disciplinary_warning" USING "btree" ("org_id", "status");



CREATE INDEX "idx_hr_employee_active" ON "public"."hr_employee" USING "btree" ("org_id", "is_deleted");



CREATE INDEX "idx_hr_employee_department" ON "public"."hr_employee" USING "btree" ("hr_department_id");



CREATE INDEX "idx_hr_employee_org_id" ON "public"."hr_employee" USING "btree" ("org_id");



CREATE INDEX "idx_hr_employee_review_employee" ON "public"."hr_employee_review" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_hr_employee_review_org" ON "public"."hr_employee_review" USING "btree" ("org_id");



CREATE INDEX "idx_hr_employee_review_period" ON "public"."hr_employee_review" USING "btree" ("org_id", "review_year", "review_quarter");



CREATE INDEX "idx_hr_employee_team_lead" ON "public"."hr_employee" USING "btree" ("team_lead_id");



CREATE INDEX "idx_hr_employee_user_id" ON "public"."hr_employee" USING "btree" ("user_id");



CREATE INDEX "idx_hr_module_access_employee" ON "public"."hr_module_access" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_hr_module_access_employee_module" ON "public"."hr_module_access" USING "btree" ("hr_employee_id", "sys_module_id");



CREATE INDEX "idx_hr_module_access_module" ON "public"."hr_module_access" USING "btree" ("sys_module_id");



CREATE INDEX "idx_hr_payroll_check_date" ON "public"."hr_payroll" USING "btree" ("org_id", "check_date");



CREATE INDEX "idx_hr_payroll_employee" ON "public"."hr_payroll" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_hr_payroll_org" ON "public"."hr_payroll" USING "btree" ("org_id");



CREATE INDEX "idx_hr_payroll_org_id_pk" ON "public"."hr_payroll" USING "btree" ("org_id", "id") WHERE ("is_deleted" = false);



CREATE INDEX "idx_hr_payroll_period" ON "public"."hr_payroll" USING "btree" ("org_id", "pay_period_start", "pay_period_end");



CREATE INDEX "idx_hr_payroll_processor_check_date" ON "public"."hr_payroll" USING "btree" ("payroll_processor", "check_date") WHERE ("is_deleted" = false);



CREATE INDEX "idx_hr_time_off_request_dates" ON "public"."hr_time_off_request" USING "btree" ("hr_employee_id", "start_date");



CREATE INDEX "idx_hr_time_off_request_employee" ON "public"."hr_time_off_request" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_hr_time_off_request_org_id" ON "public"."hr_time_off_request" USING "btree" ("org_id");



CREATE INDEX "idx_hr_time_off_request_status" ON "public"."hr_time_off_request" USING "btree" ("org_id", "status");



CREATE INDEX "idx_hr_travel_request_dates" ON "public"."hr_travel_request" USING "btree" ("hr_employee_id", "travel_start_date");



CREATE INDEX "idx_hr_travel_request_employee" ON "public"."hr_travel_request" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_hr_travel_request_org_id" ON "public"."hr_travel_request" USING "btree" ("org_id");



CREATE INDEX "idx_hr_travel_request_status" ON "public"."hr_travel_request" USING "btree" ("org_id", "status");



CREATE INDEX "idx_hr_work_authorization_active" ON "public"."hr_work_authorization" USING "btree" ("org_id", "is_deleted");



CREATE INDEX "idx_hr_work_authorization_org_id" ON "public"."hr_work_authorization" USING "btree" ("org_id");



CREATE INDEX "idx_invnt_category_org_id" ON "public"."invnt_category" USING "btree" ("org_id");



CREATE INDEX "idx_invnt_item_category" ON "public"."invnt_item" USING "btree" ("invnt_category_id");



CREATE INDEX "idx_invnt_item_equipment" ON "public"."invnt_item" USING "btree" ("equipment_id");



CREATE INDEX "idx_invnt_item_org_id" ON "public"."invnt_item" USING "btree" ("org_id");



CREATE INDEX "idx_invnt_item_site" ON "public"."invnt_item" USING "btree" ("site_id");



CREATE INDEX "idx_invnt_item_subcategory" ON "public"."invnt_item" USING "btree" ("invnt_subcategory_id");



CREATE INDEX "idx_invnt_item_vendor" ON "public"."invnt_item" USING "btree" ("invnt_vendor_id");



CREATE INDEX "idx_invnt_onhand_item" ON "public"."invnt_onhand" USING "btree" ("invnt_item_id", "onhand_date");



CREATE INDEX "idx_invnt_onhand_org_id" ON "public"."invnt_onhand" USING "btree" ("org_id");



CREATE INDEX "idx_invnt_po_item" ON "public"."invnt_po" USING "btree" ("invnt_item_id");



CREATE INDEX "idx_invnt_po_org_id" ON "public"."invnt_po" USING "btree" ("org_id");



CREATE INDEX "idx_invnt_po_received_org" ON "public"."invnt_po_received" USING "btree" ("org_id");



CREATE INDEX "idx_invnt_po_received_po" ON "public"."invnt_po_received" USING "btree" ("invnt_po_id");



CREATE INDEX "idx_invnt_po_status" ON "public"."invnt_po" USING "btree" ("org_id", "status");



CREATE INDEX "idx_maint_request_due" ON "public"."maint_request" USING "btree" ("org_id", "due_date");



CREATE INDEX "idx_maint_request_fixer" ON "public"."maint_request" USING "btree" ("fixer_id");



CREATE INDEX "idx_maint_request_invnt_item_item" ON "public"."maint_request_invnt_item" USING "btree" ("invnt_item_id");



CREATE INDEX "idx_maint_request_invnt_item_request" ON "public"."maint_request_invnt_item" USING "btree" ("maint_request_id");



CREATE INDEX "idx_maint_request_org_id" ON "public"."maint_request" USING "btree" ("org_id");



CREATE INDEX "idx_maint_request_photo_request" ON "public"."maint_request_photo" USING "btree" ("maint_request_id");



CREATE INDEX "idx_maint_request_site" ON "public"."maint_request" USING "btree" ("site_id");



CREATE INDEX "idx_maint_request_status" ON "public"."maint_request" USING "btree" ("org_id", "status");



CREATE INDEX "idx_ops_corrective_action_choice_org_id" ON "public"."ops_corrective_action_choice" USING "btree" ("org_id");



CREATE INDEX "idx_ops_corrective_action_taken_assigned" ON "public"."ops_corrective_action_taken" USING "btree" ("assigned_to");



CREATE INDEX "idx_ops_corrective_action_taken_org_id" ON "public"."ops_corrective_action_taken" USING "btree" ("org_id");



CREATE INDEX "idx_ops_corrective_action_taken_pest_result" ON "public"."ops_corrective_action_taken" USING "btree" ("fsafe_pest_result_id");



CREATE INDEX "idx_ops_corrective_action_taken_resolved" ON "public"."ops_corrective_action_taken" USING "btree" ("org_id", "is_resolved");



CREATE INDEX "idx_ops_corrective_action_taken_response" ON "public"."ops_corrective_action_taken" USING "btree" ("ops_template_result_id");



CREATE INDEX "idx_ops_corrective_action_taken_result" ON "public"."ops_corrective_action_taken" USING "btree" ("fsafe_result_id");



CREATE INDEX "idx_ops_task_org_id" ON "public"."ops_task" USING "btree" ("org_id");



CREATE INDEX "idx_ops_task_schedule_emp_start_date" ON "public"."ops_task_schedule" USING "btree" ("hr_employee_id", (("start_time")::"date")) WHERE ("is_deleted" = false);



CREATE INDEX "idx_ops_task_schedule_employee" ON "public"."ops_task_schedule" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_ops_task_schedule_org_id" ON "public"."ops_task_schedule" USING "btree" ("org_id");



CREATE INDEX "idx_ops_task_schedule_task" ON "public"."ops_task_schedule" USING "btree" ("ops_task_id");



CREATE INDEX "idx_ops_task_schedule_tracker" ON "public"."ops_task_schedule" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_ops_task_template_task" ON "public"."ops_task_template" USING "btree" ("ops_task_id");



CREATE INDEX "idx_ops_task_template_template" ON "public"."ops_task_template" USING "btree" ("ops_template_id");



CREATE INDEX "idx_ops_task_tracker_completed" ON "public"."ops_task_tracker" USING "btree" ("org_id", "is_completed");



CREATE INDEX "idx_ops_task_tracker_org_id" ON "public"."ops_task_tracker" USING "btree" ("org_id");



CREATE INDEX "idx_ops_task_tracker_site" ON "public"."ops_task_tracker" USING "btree" ("site_id");



CREATE INDEX "idx_ops_task_tracker_task" ON "public"."ops_task_tracker" USING "btree" ("ops_task_id");



CREATE INDEX "idx_ops_template_org_id" ON "public"."ops_template" USING "btree" ("org_id");



CREATE INDEX "idx_ops_template_question_org_id" ON "public"."ops_template_question" USING "btree" ("org_id");



CREATE INDEX "idx_ops_template_question_template" ON "public"."ops_template_question" USING "btree" ("ops_template_id", "display_order");



CREATE INDEX "idx_ops_template_result_org_id" ON "public"."ops_template_result" USING "btree" ("org_id");



CREATE INDEX "idx_ops_template_result_photo_result" ON "public"."ops_template_result_photo" USING "btree" ("ops_template_result_id");



CREATE INDEX "idx_ops_template_result_question" ON "public"."ops_template_result" USING "btree" ("ops_template_question_id");



CREATE INDEX "idx_ops_template_result_tracker" ON "public"."ops_template_result" USING "btree" ("ops_task_tracker_id");



CREATE INDEX "idx_ops_training_attendee_employee" ON "public"."ops_training_attendee" USING "btree" ("hr_employee_id");



CREATE INDEX "idx_ops_training_attendee_org" ON "public"."ops_training_attendee" USING "btree" ("org_id");



CREATE INDEX "idx_ops_training_attendee_training" ON "public"."ops_training_attendee" USING "btree" ("ops_training_id");



CREATE INDEX "idx_ops_training_date" ON "public"."ops_training" USING "btree" ("org_id", "training_date");



CREATE INDEX "idx_ops_training_farm" ON "public"."ops_training" USING "btree" ("farm_id");



CREATE INDEX "idx_ops_training_org_id" ON "public"."ops_training" USING "btree" ("org_id");



CREATE INDEX "idx_ops_training_type" ON "public"."ops_training" USING "btree" ("ops_training_type_id");



CREATE INDEX "idx_ops_training_type_active" ON "public"."ops_training_type" USING "btree" ("org_id", "is_deleted");



CREATE INDEX "idx_ops_training_type_org_id" ON "public"."ops_training_type" USING "btree" ("org_id");



CREATE INDEX "idx_org_business_rule_module" ON "public"."org_business_rule" USING "btree" ("module");



CREATE INDEX "idx_org_business_rule_type" ON "public"."org_business_rule" USING "btree" ("rule_type");



CREATE INDEX "idx_org_module_org" ON "public"."org_module" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_category" ON "public"."org_site" USING "btree" ("org_site_category_id");



CREATE INDEX "idx_org_site_cuke_gh_block_org" ON "public"."org_site_cuke_gh_block" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_cuke_gh_block_site" ON "public"."org_site_cuke_gh_block" USING "btree" ("site_id");



CREATE INDEX "idx_org_site_cuke_gh_farm" ON "public"."org_site_cuke_gh" USING "btree" ("farm_id");



CREATE INDEX "idx_org_site_cuke_gh_org" ON "public"."org_site_cuke_gh" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_cuke_gh_row_org" ON "public"."org_site_cuke_gh_row" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_cuke_gh_row_site" ON "public"."org_site_cuke_gh_row" USING "btree" ("site_id");



CREATE INDEX "idx_org_site_farm" ON "public"."org_site" USING "btree" ("farm_id");



CREATE INDEX "idx_org_site_housing_area_housing" ON "public"."org_site_housing_area" USING "btree" ("housing_id");



CREATE INDEX "idx_org_site_housing_area_org" ON "public"."org_site_housing_area" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_housing_org" ON "public"."org_site_housing" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_org_id" ON "public"."org_site" USING "btree" ("org_id");



CREATE INDEX "idx_org_site_parent" ON "public"."org_site" USING "btree" ("site_id_parent");



CREATE INDEX "idx_org_sub_module_module" ON "public"."org_sub_module" USING "btree" ("sys_module_id");



CREATE INDEX "idx_org_sub_module_org" ON "public"."org_sub_module" USING "btree" ("org_id");



CREATE INDEX "idx_pack_moisture_batch" ON "public"."pack_moisture" USING "btree" ("grow_lettuce_seed_batch_id");



CREATE INDEX "idx_pack_moisture_date" ON "public"."pack_moisture" USING "btree" ("check_at");



CREATE INDEX "idx_pack_moisture_farm" ON "public"."pack_moisture" USING "btree" ("farm_id");



CREATE INDEX "idx_pack_moisture_org" ON "public"."pack_moisture" USING "btree" ("org_id");



CREATE INDEX "idx_pack_moisture_original" ON "public"."pack_moisture" USING "btree" ("pack_moisture_id_original");



CREATE INDEX "idx_pack_session_cases_pack_date" ON "public"."pack_session_cases" USING "btree" ("org_id", "farm_id", "pack_date");



CREATE INDEX "idx_pack_session_cases_pack_end_hour" ON "public"."pack_session_cases" USING "btree" ("pack_end_hour");



CREATE INDEX "idx_pack_session_cases_product" ON "public"."pack_session_cases" USING "btree" ("sales_product_id");



CREATE INDEX "idx_pack_session_fails_category" ON "public"."pack_session_fails" USING "btree" ("pack_fail_category_id");



CREATE INDEX "idx_pack_session_fails_pack_date" ON "public"."pack_session_fails" USING "btree" ("org_id", "farm_id", "pack_date");



CREATE INDEX "idx_pack_session_fails_pack_end_hour" ON "public"."pack_session_fails" USING "btree" ("pack_end_hour");



CREATE INDEX "idx_pack_session_farm_id" ON "public"."pack_session" USING "btree" ("farm_id");



CREATE INDEX "idx_pack_session_labor_hour_farm_id" ON "public"."pack_session_labor_hour" USING "btree" ("farm_id");



CREATE INDEX "idx_pack_session_labor_hour_org_id" ON "public"."pack_session_labor_hour" USING "btree" ("org_id");



CREATE INDEX "idx_pack_session_labor_hour_pack_date" ON "public"."pack_session_labor_hour" USING "btree" ("pack_date");



CREATE INDEX "idx_pack_session_leftover_pack_date" ON "public"."pack_session_leftover" USING "btree" ("pack_date");



CREATE INDEX "idx_pack_session_org_id" ON "public"."pack_session" USING "btree" ("org_id");



CREATE INDEX "idx_pack_session_pack_date" ON "public"."pack_session" USING "btree" ("pack_date");



CREATE INDEX "idx_pack_session_product" ON "public"."pack_session" USING "btree" ("sales_product_id");



CREATE INDEX "idx_pack_shelf_life_metric_org_id" ON "public"."pack_shelf_life_metric" USING "btree" ("org_id");



CREATE INDEX "idx_pack_shelf_life_org_id" ON "public"."pack_shelf_life" USING "btree" ("org_id");



CREATE INDEX "idx_pack_shelf_life_pack_session" ON "public"."pack_shelf_life" USING "btree" ("pack_session_id");



CREATE INDEX "idx_pack_shelf_life_photo_org_id" ON "public"."pack_shelf_life_photo" USING "btree" ("org_id");



CREATE INDEX "idx_pack_shelf_life_photo_trial" ON "public"."pack_shelf_life_photo" USING "btree" ("pack_shelf_life_id");



CREATE INDEX "idx_pack_shelf_life_product" ON "public"."pack_shelf_life" USING "btree" ("sales_product_id");



CREATE INDEX "idx_pack_shelf_life_result_check" ON "public"."pack_shelf_life_result" USING "btree" ("pack_shelf_life_metric_id");



CREATE INDEX "idx_pack_shelf_life_result_org_id" ON "public"."pack_shelf_life_result" USING "btree" ("org_id");



CREATE INDEX "idx_pack_shelf_life_result_trial" ON "public"."pack_shelf_life_result" USING "btree" ("pack_shelf_life_id");



CREATE INDEX "idx_sales_crm_ext_product_org" ON "public"."sales_crm_external_product" USING "btree" ("org_id");



CREATE INDEX "idx_sales_crm_store_customer" ON "public"."sales_crm_store" USING "btree" ("sales_customer_id");



CREATE INDEX "idx_sales_crm_store_org" ON "public"."sales_crm_store" USING "btree" ("org_id");



CREATE INDEX "idx_sales_crm_store_visit_date" ON "public"."sales_crm_store_visit" USING "btree" ("visit_date");



CREATE INDEX "idx_sales_crm_store_visit_org" ON "public"."sales_crm_store_visit" USING "btree" ("org_id");



CREATE INDEX "idx_sales_crm_store_visit_store" ON "public"."sales_crm_store_visit" USING "btree" ("sales_crm_store_id");



CREATE INDEX "idx_sales_crm_visit_photo_visit" ON "public"."sales_crm_store_visit_photo" USING "btree" ("sales_crm_store_visit_id");



CREATE INDEX "idx_sales_crm_visit_result_ext" ON "public"."sales_crm_store_visit_result" USING "btree" ("sales_crm_external_product_id");



CREATE INDEX "idx_sales_crm_visit_result_product" ON "public"."sales_crm_store_visit_result" USING "btree" ("sales_product_id");



CREATE INDEX "idx_sales_crm_visit_result_visit" ON "public"."sales_crm_store_visit_result" USING "btree" ("sales_crm_store_visit_id");



CREATE INDEX "idx_sales_customer_org_id" ON "public"."sales_customer" USING "btree" ("org_id");



CREATE INDEX "idx_sales_edi_inbound_document_type" ON "public"."sales_sps_edi_inbound_message" USING "btree" ("document_type", "received_at");



CREATE INDEX "idx_sales_edi_inbound_org" ON "public"."sales_sps_edi_inbound_message" USING "btree" ("org_id");



CREATE INDEX "idx_sales_edi_inbound_partner" ON "public"."sales_sps_edi_inbound_message" USING "btree" ("sales_sps_trading_partner_id");



CREATE INDEX "idx_sales_edi_inbound_unparsed" ON "public"."sales_sps_edi_inbound_message" USING "btree" ("received_at") WHERE (("parsed_at" IS NULL) AND ("parse_error" IS NULL));



CREATE INDEX "idx_sales_invoice_date" ON "public"."sales_invoice" USING "btree" ("invoice_date");



CREATE INDEX "idx_sales_invoice_farm" ON "public"."sales_invoice" USING "btree" ("farm_id");



CREATE INDEX "idx_sales_invoice_org" ON "public"."sales_invoice" USING "btree" ("org_id");



CREATE INDEX "idx_sales_pallet_allocation_fulfillment" ON "public"."sales_pallet_allocation" USING "btree" ("sales_po_fulfillment_id");



CREATE INDEX "idx_sales_pallet_allocation_org" ON "public"."sales_pallet_allocation" USING "btree" ("org_id");



CREATE INDEX "idx_sales_pallet_allocation_pallet" ON "public"."sales_pallet_allocation" USING "btree" ("sales_pallet_id");



CREATE INDEX "idx_sales_pallet_container" ON "public"."sales_pallet" USING "btree" ("sales_sps_shipment_container_id");



CREATE INDEX "idx_sales_pallet_farm_date" ON "public"."sales_pallet" USING "btree" ("farm_id", "target_invoice_date");



CREATE INDEX "idx_sales_pallet_org" ON "public"."sales_pallet" USING "btree" ("org_id");



CREATE INDEX "idx_sales_pallet_unlocked_scope" ON "public"."sales_pallet" USING "btree" ("org_id", "farm_id", "target_invoice_date") WHERE ("is_locked" = false);



CREATE INDEX "idx_sales_po_asn_carton_asn" ON "public"."sales_sps_po_asn_carton" USING "btree" ("sales_sps_po_asn_id");



CREATE INDEX "idx_sales_po_asn_carton_line" ON "public"."sales_sps_po_asn_carton" USING "btree" ("sales_po_line_id");



CREATE INDEX "idx_sales_po_asn_carton_org" ON "public"."sales_sps_po_asn_carton" USING "btree" ("org_id");



CREATE INDEX "idx_sales_po_asn_carton_parent" ON "public"."sales_sps_po_asn_carton" USING "btree" ("parent_carton_id");



CREATE INDEX "idx_sales_po_asn_container" ON "public"."sales_sps_po_asn" USING "btree" ("sales_sps_shipment_container_id");



CREATE INDEX "idx_sales_po_asn_org" ON "public"."sales_sps_po_asn" USING "btree" ("org_id");



CREATE INDEX "idx_sales_po_asn_po" ON "public"."sales_sps_po_asn" USING "btree" ("sales_po_id");



CREATE INDEX "idx_sales_po_asn_status" ON "public"."sales_sps_po_asn" USING "btree" ("status", "created_at");



CREATE INDEX "idx_sales_po_customer" ON "public"."sales_po" USING "btree" ("sales_customer_id");



CREATE INDEX "idx_sales_po_fulfillment_order_line" ON "public"."sales_po_fulfillment" USING "btree" ("sales_po_line_id");



CREATE INDEX "idx_sales_po_fulfillment_org_id" ON "public"."sales_po_fulfillment" USING "btree" ("org_id");



CREATE INDEX "idx_sales_po_fulfillment_pack_session" ON "public"."sales_po_fulfillment" USING "btree" ("pack_session_id");



CREATE INDEX "idx_sales_po_line_order" ON "public"."sales_po_line" USING "btree" ("sales_po_id");



CREATE INDEX "idx_sales_po_line_org_id" ON "public"."sales_po_line" USING "btree" ("org_id");



CREATE INDEX "idx_sales_po_line_product" ON "public"."sales_po_line" USING "btree" ("sales_product_id");



CREATE INDEX "idx_sales_po_org_id" ON "public"."sales_po" USING "btree" ("org_id");



CREATE INDEX "idx_sales_po_status" ON "public"."sales_po" USING "btree" ("org_id", "status");



CREATE INDEX "idx_sales_po_trading_partner" ON "public"."sales_po" USING "btree" ("sales_sps_trading_partner_id");



CREATE INDEX "idx_sales_product_buyer_part_org" ON "public"."sales_sps_product_buyer_part" USING "btree" ("org_id");



CREATE INDEX "idx_sales_product_buyer_part_product" ON "public"."sales_sps_product_buyer_part" USING "btree" ("sales_product_id");



CREATE INDEX "idx_sales_product_farm_id" ON "public"."sales_product" USING "btree" ("farm_id");



CREATE INDEX "idx_sales_product_price_lookup" ON "public"."sales_product_price" USING "btree" ("sales_product_id", "sales_fob_id");



CREATE INDEX "idx_sales_product_price_org" ON "public"."sales_product_price" USING "btree" ("org_id");



CREATE INDEX "idx_sales_shipment_container_org" ON "public"."sales_sps_shipment_container" USING "btree" ("org_id");



CREATE INDEX "idx_sales_shipment_container_shipment" ON "public"."sales_sps_shipment_container" USING "btree" ("sales_sps_shipment_id");



CREATE INDEX "idx_sales_shipment_org" ON "public"."sales_sps_shipment" USING "btree" ("org_id");



CREATE INDEX "idx_sales_shipment_ship_date" ON "public"."sales_sps_shipment" USING "btree" ("org_id", "ship_date");



CREATE INDEX "idx_sales_sps_carton_pack_session" ON "public"."sales_sps_po_asn_carton" USING "btree" ("pack_session_id");



CREATE INDEX "idx_sales_trading_partner_customer" ON "public"."sales_sps_trading_partner" USING "btree" ("sales_customer_id");



CREATE INDEX "idx_sales_trading_partner_org" ON "public"."sales_sps_trading_partner" USING "btree" ("org_id");



CREATE INDEX "idx_sys_uom_category" ON "public"."sys_uom" USING "btree" ("category");



CREATE UNIQUE INDEX "uq_grow_task_seed_batch_cuke" ON "public"."grow_task_seed_batch" USING "btree" ("ops_task_tracker_id", "grow_cuke_seed_batch_id") WHERE ("grow_cuke_seed_batch_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_grow_task_seed_batch_lettuce" ON "public"."grow_task_seed_batch" USING "btree" ("ops_task_tracker_id", "grow_lettuce_seed_batch_id") WHERE ("grow_lettuce_seed_batch_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_invnt_category_sub_level" ON "public"."invnt_category" USING "btree" ("org_id", "category_name", "sub_category_name") WHERE ("sub_category_name" IS NOT NULL);



CREATE UNIQUE INDEX "uq_invnt_category_top_level" ON "public"."invnt_category" USING "btree" ("org_id", "category_name") WHERE ("sub_category_name" IS NULL);



CREATE UNIQUE INDEX "uq_ops_task_schedule_executed" ON "public"."ops_task_schedule" USING "btree" ("ops_task_tracker_id", "hr_employee_id") WHERE ("ops_task_tracker_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_ops_task_schedule_planned" ON "public"."ops_task_schedule" USING "btree" ("ops_task_id", "hr_employee_id", "start_time") WHERE ("ops_task_tracker_id" IS NULL);



CREATE UNIQUE INDEX "uq_ops_template_farm_level" ON "public"."ops_template" USING "btree" ("org_id", "farm_id", "id") WHERE ("farm_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_ops_template_org_level" ON "public"."ops_template" USING "btree" ("org_id", "id") WHERE ("farm_id" IS NULL);



CREATE UNIQUE INDEX "uq_ops_template_result_atp" ON "public"."ops_template_result" USING "btree" ("ops_task_tracker_id", "site_id") WHERE (("ops_template_question_id" IS NULL) AND ("site_id" IS NOT NULL));



CREATE UNIQUE INDEX "uq_ops_template_result_checklist" ON "public"."ops_template_result" USING "btree" ("ops_task_tracker_id", "ops_template_question_id") WHERE (("ops_template_question_id" IS NOT NULL) AND ("equipment_id" IS NULL));



CREATE UNIQUE INDEX "uq_ops_template_result_checklist_equipment" ON "public"."ops_template_result" USING "btree" ("ops_task_tracker_id", "ops_template_question_id", "equipment_id") WHERE (("ops_template_question_id" IS NOT NULL) AND ("equipment_id" IS NOT NULL));



CREATE UNIQUE INDEX "uq_org_site_category_sub" ON "public"."org_site_category" USING "btree" ("org_id", "category_name", "sub_category_name") WHERE ("sub_category_name" IS NOT NULL);



CREATE UNIQUE INDEX "uq_org_site_category_top" ON "public"."org_site_category" USING "btree" ("org_id", "category_name") WHERE ("sub_category_name" IS NULL);



CREATE UNIQUE INDEX "uq_org_site_farm_level" ON "public"."org_site" USING "btree" ("org_id", "farm_id", "name") WHERE ("farm_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_org_site_org_level" ON "public"."org_site" USING "btree" ("org_id", "name") WHERE ("farm_id" IS NULL);



CREATE UNIQUE INDEX "uq_pack_fail_category_farm" ON "public"."pack_fail_category" USING "btree" ("org_id", "farm_id", "id") WHERE ("farm_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_pack_fail_category_org" ON "public"."pack_fail_category" USING "btree" ("org_id", "id") WHERE ("farm_id" IS NULL);



CREATE UNIQUE INDEX "uq_pack_session_cases" ON "public"."pack_session_cases" USING "btree" ("org_id", "farm_id", "pack_date", "pack_end_hour", "sales_product_id", "harvest_date");



CREATE UNIQUE INDEX "uq_pack_session_fails" ON "public"."pack_session_fails" USING "btree" ("org_id", "farm_id", "pack_date", "pack_end_hour", "pack_fail_category_id");



CREATE UNIQUE INDEX "uq_pack_session_labor_hour" ON "public"."pack_session_labor_hour" USING "btree" ("org_id", "farm_id", "pack_date", "pack_end_hour");



CREATE UNIQUE INDEX "uq_pack_shelf_life_metric_farm_level" ON "public"."pack_shelf_life_metric" USING "btree" ("org_id", "farm_id", "id") WHERE ("farm_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_pack_shelf_life_metric_org_level" ON "public"."pack_shelf_life_metric" USING "btree" ("org_id", "id") WHERE ("farm_id" IS NULL);



CREATE OR REPLACE TRIGGER "pack_session_before_insert_defaults" BEFORE INSERT ON "public"."pack_session" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_set_defaults"();



CREATE OR REPLACE TRIGGER "pack_session_before_update_guard" BEFORE UPDATE ON "public"."pack_session" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_guard_immutable"();



CREATE OR REPLACE TRIGGER "pack_session_cases_before_update_guard" BEFORE UPDATE ON "public"."pack_session_cases" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_cases_guard_immutable"();



CREATE OR REPLACE TRIGGER "pack_session_fails_before_update_guard" BEFORE UPDATE ON "public"."pack_session_fails" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_fails_guard_immutable"();



CREATE OR REPLACE TRIGGER "pack_session_labor_hour_before_update_guard" BEFORE UPDATE ON "public"."pack_session_labor_hour" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_labor_hour_guard_immutable"();



CREATE OR REPLACE TRIGGER "pack_session_leftover_before_update_guard" BEFORE UPDATE ON "public"."pack_session_leftover" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_leftover_guard_immutable"();



CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_cascade_day" AFTER UPDATE OF "pack_session_id" ON "public"."pack_shelf_life" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_cascade_day"();



CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_check_termination" AFTER INSERT OR UPDATE ON "public"."pack_shelf_life_result" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_check_termination"();



CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_photo_set_day" BEFORE INSERT OR UPDATE OF "observation_date", "pack_shelf_life_id" ON "public"."pack_shelf_life_photo" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_set_day"();



CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_result_set_day" BEFORE INSERT OR UPDATE OF "observation_date", "pack_shelf_life_id" ON "public"."pack_shelf_life_result" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_set_day"();



ALTER TABLE ONLY "public"."edi_qb_expense_line"
    ADD CONSTRAINT "edi_qb_expense_line_org_id_expense_id_fkey" FOREIGN KEY ("org_id", "expense_id") REFERENCES "public"."edi_qb_expense"("org_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."edi_qb_expense_line"
    ADD CONSTRAINT "edi_qb_expense_line_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."edi_qb_expense"
    ADD CONSTRAINT "edi_qb_expense_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."edi_qb_invoice_line"
    ADD CONSTRAINT "edi_qb_invoice_line_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."edi_qb_invoice_line"
    ADD CONSTRAINT "edi_qb_invoice_line_org_id_invoice_id_fkey" FOREIGN KEY ("org_id", "invoice_id") REFERENCES "public"."edi_qb_invoice"("org_id", "id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."edi_qb_invoice"
    ADD CONSTRAINT "edi_qb_invoice_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fin_expense"
    ADD CONSTRAINT "fin_expense_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."fin_expense"
    ADD CONSTRAINT "fin_expense_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "fk_grow_cuke_gh_row_planting_row" FOREIGN KEY ("org_site_cuke_gh_row_id") REFERENCES "public"."org_site_cuke_gh_row"("id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "fk_grow_cuke_gh_row_planting_variety_primary" FOREIGN KEY ("grow_variety_id") REFERENCES "public"."grow_variety"("id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "fk_grow_cuke_gh_row_planting_variety_secondary" FOREIGN KEY ("grow_variety_id_2") REFERENCES "public"."grow_variety"("id");



ALTER TABLE ONLY "public"."org_site"
    ADD CONSTRAINT "fk_org_site_category" FOREIGN KEY ("org_site_category_id") REFERENCES "public"."org_site_category"("id");



ALTER TABLE ONLY "public"."org_site"
    ADD CONSTRAINT "fk_org_site_subcategory" FOREIGN KEY ("org_site_subcategory_id") REFERENCES "public"."org_site_category"("id");



ALTER TABLE ONLY "public"."fsafe_lab"
    ADD CONSTRAINT "fsafe_lab_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fsafe_lab_test"
    ADD CONSTRAINT "fsafe_lab_test_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_lab_test"
    ADD CONSTRAINT "fsafe_lab_test_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fsafe_pest_result"
    ADD CONSTRAINT "fsafe_pest_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_pest_result"
    ADD CONSTRAINT "fsafe_pest_result_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."fsafe_pest_result"
    ADD CONSTRAINT "fsafe_pest_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fsafe_pest_result"
    ADD CONSTRAINT "fsafe_pest_result_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_fsafe_lab_id_fkey" FOREIGN KEY ("fsafe_lab_id") REFERENCES "public"."fsafe_lab"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_fsafe_lab_test_id_fkey" FOREIGN KEY ("fsafe_lab_test_id") REFERENCES "public"."fsafe_lab_test"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_fsafe_result_id_original_fkey" FOREIGN KEY ("fsafe_result_id_original") REFERENCES "public"."fsafe_result"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_fsafe_test_hold_id_fkey" FOREIGN KEY ("fsafe_test_hold_id") REFERENCES "public"."fsafe_test_hold"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_sampled_by_emp_fkey" FOREIGN KEY ("org_id", "sampled_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."fsafe_result"
    ADD CONSTRAINT "fsafe_result_verified_by_emp_fkey" FOREIGN KEY ("org_id", "verified_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_test_hold"
    ADD CONSTRAINT "fsafe_test_hold_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_test_hold"
    ADD CONSTRAINT "fsafe_test_hold_fsafe_lab_id_fkey" FOREIGN KEY ("fsafe_lab_id") REFERENCES "public"."fsafe_lab"("id");



ALTER TABLE ONLY "public"."fsafe_test_hold"
    ADD CONSTRAINT "fsafe_test_hold_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fsafe_test_hold_po"
    ADD CONSTRAINT "fsafe_test_hold_po_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."fsafe_test_hold_po"
    ADD CONSTRAINT "fsafe_test_hold_po_fsafe_test_hold_id_fkey" FOREIGN KEY ("fsafe_test_hold_id") REFERENCES "public"."fsafe_test_hold"("id");



ALTER TABLE ONLY "public"."fsafe_test_hold_po"
    ADD CONSTRAINT "fsafe_test_hold_po_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."fsafe_test_hold_po"
    ADD CONSTRAINT "fsafe_test_hold_po_sales_po_id_fkey" FOREIGN KEY ("sales_po_id") REFERENCES "public"."sales_po"("id");



ALTER TABLE ONLY "public"."fsafe_test_hold"
    ADD CONSTRAINT "fsafe_test_hold_sales_customer_group_id_fkey" FOREIGN KEY ("sales_customer_group_id") REFERENCES "public"."sales_customer_group"("id");



ALTER TABLE ONLY "public"."fsafe_test_hold"
    ADD CONSTRAINT "fsafe_test_hold_sales_customer_id_fkey" FOREIGN KEY ("sales_customer_id") REFERENCES "public"."sales_customer"("id");



ALTER TABLE ONLY "public"."grow_chemistry_result"
    ADD CONSTRAINT "grow_chemistry_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_chemistry_result"
    ADD CONSTRAINT "grow_chemistry_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "grow_cuke_gh_row_planting_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_cuke_gh_row_planting"
    ADD CONSTRAINT "grow_cuke_gh_row_planting_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_cuke_rotation"
    ADD CONSTRAINT "grow_cuke_rotation_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site_cuke_gh"("id");



ALTER TABLE ONLY "public"."grow_cuke_seed_batch"
    ADD CONSTRAINT "grow_cuke_seed_batch_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_cuke_seed_batch"
    ADD CONSTRAINT "grow_cuke_seed_batch_grow_trial_type_id_fkey" FOREIGN KEY ("grow_trial_type_id") REFERENCES "public"."grow_trial_type"("id");



ALTER TABLE ONLY "public"."grow_cuke_seed_batch"
    ADD CONSTRAINT "grow_cuke_seed_batch_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."grow_cuke_seed_batch"
    ADD CONSTRAINT "grow_cuke_seed_batch_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_cuke_seed_batch"
    ADD CONSTRAINT "grow_cuke_seed_batch_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site_cuke_gh"("id");



ALTER TABLE ONLY "public"."grow_cycle_pattern"
    ADD CONSTRAINT "grow_cycle_pattern_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_cycle_pattern"
    ADD CONSTRAINT "grow_cycle_pattern_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_equipment_id_fkey" FOREIGN KEY ("equipment_id") REFERENCES "public"."org_equipment"("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_grow_fertigation_recipe_id_fkey" FOREIGN KEY ("grow_fertigation_recipe_id") REFERENCES "public"."grow_fertigation_recipe"("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe"
    ADD CONSTRAINT "grow_fertigation_recipe_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_application_uom_fkey" FOREIGN KEY ("application_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_burn_uom_fkey" FOREIGN KEY ("burn_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_equipment_id_fkey" FOREIGN KEY ("equipment_id") REFERENCES "public"."org_equipment"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_grow_fertigation_recipe_id_fkey" FOREIGN KEY ("grow_fertigation_recipe_id") REFERENCES "public"."grow_fertigation_recipe"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_item"
    ADD CONSTRAINT "grow_fertigation_recipe_item_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe"
    ADD CONSTRAINT "grow_fertigation_recipe_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_site"
    ADD CONSTRAINT "grow_fertigation_recipe_site_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_site"
    ADD CONSTRAINT "grow_fertigation_recipe_site_grow_fertigation_recipe_id_fkey" FOREIGN KEY ("grow_fertigation_recipe_id") REFERENCES "public"."grow_fertigation_recipe"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_site"
    ADD CONSTRAINT "grow_fertigation_recipe_site_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_fertigation_recipe_site"
    ADD CONSTRAINT "grow_fertigation_recipe_site_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."grow_fertigation"
    ADD CONSTRAINT "grow_fertigation_volume_uom_fkey" FOREIGN KEY ("volume_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_grade"
    ADD CONSTRAINT "grow_grade_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_grade"
    ADD CONSTRAINT "grow_grade_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "grow_harvest_container_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "grow_harvest_container_grow_grade_id_fkey" FOREIGN KEY ("grow_grade_id") REFERENCES "public"."grow_grade"("id");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "grow_harvest_container_grow_variety_id_fkey" FOREIGN KEY ("grow_variety_id") REFERENCES "public"."grow_variety"("id");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "grow_harvest_container_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_harvest_container"
    ADD CONSTRAINT "grow_harvest_container_weight_uom_fkey" FOREIGN KEY ("weight_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_grow_cuke_seed_batch_id_fkey" FOREIGN KEY ("grow_cuke_seed_batch_id") REFERENCES "public"."grow_cuke_seed_batch"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_grow_grade_id_fkey" FOREIGN KEY ("grow_grade_id") REFERENCES "public"."grow_grade"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_grow_harvest_container_id_fkey" FOREIGN KEY ("grow_harvest_container_id") REFERENCES "public"."grow_harvest_container"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_grow_lettuce_seed_batch_id_fkey" FOREIGN KEY ("grow_lettuce_seed_batch_id") REFERENCES "public"."grow_lettuce_seed_batch"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."grow_harvest_weight"
    ADD CONSTRAINT "grow_harvest_weight_weight_uom_fkey" FOREIGN KEY ("weight_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_grow_cycle_pattern_id_fkey" FOREIGN KEY ("grow_cycle_pattern_id") REFERENCES "public"."grow_cycle_pattern"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_grow_lettuce_seed_mix_id_fkey" FOREIGN KEY ("grow_lettuce_seed_mix_id") REFERENCES "public"."grow_lettuce_seed_mix"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_grow_trial_type_id_fkey" FOREIGN KEY ("grow_trial_type_id") REFERENCES "public"."grow_trial_type"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_invnt_lot_id_fkey" FOREIGN KEY ("invnt_lot_id") REFERENCES "public"."invnt_lot"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_seeding_uom_fkey" FOREIGN KEY ("seeding_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_lettuce_seed_batch"
    ADD CONSTRAINT "grow_lettuce_seed_batch_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix"
    ADD CONSTRAINT "grow_lettuce_seed_mix_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "grow_lettuce_seed_mix_item_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "grow_lettuce_seed_mix_item_grow_lettuce_seed_mix_id_fkey" FOREIGN KEY ("grow_lettuce_seed_mix_id") REFERENCES "public"."grow_lettuce_seed_mix"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "grow_lettuce_seed_mix_item_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "grow_lettuce_seed_mix_item_invnt_lot_id_fkey" FOREIGN KEY ("invnt_lot_id") REFERENCES "public"."invnt_lot"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix_item"
    ADD CONSTRAINT "grow_lettuce_seed_mix_item_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_lettuce_seed_mix"
    ADD CONSTRAINT "grow_lettuce_seed_mix_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_monitoring_metric"
    ADD CONSTRAINT "grow_monitoring_metric_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_monitoring_metric"
    ADD CONSTRAINT "grow_monitoring_metric_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_monitoring_metric"
    ADD CONSTRAINT "grow_monitoring_metric_reading_uom_fkey" FOREIGN KEY ("reading_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "grow_monitoring_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "grow_monitoring_result_grow_monitoring_metric_id_fkey" FOREIGN KEY ("grow_monitoring_metric_id") REFERENCES "public"."grow_monitoring_metric"("id");



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "grow_monitoring_result_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "grow_monitoring_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_monitoring_result"
    ADD CONSTRAINT "grow_monitoring_result_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_grow_disease_id_fkey" FOREIGN KEY ("grow_disease_id") REFERENCES "public"."grow_disease"("id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_grow_pest_id_fkey" FOREIGN KEY ("grow_pest_id") REFERENCES "public"."grow_pest"("id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_scout_result"
    ADD CONSTRAINT "grow_scout_result_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."grow_spray_compliance"
    ADD CONSTRAINT "grow_spray_compliance_application_uom_fkey" FOREIGN KEY ("application_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_spray_compliance"
    ADD CONSTRAINT "grow_spray_compliance_burn_uom_fkey" FOREIGN KEY ("burn_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_spray_compliance"
    ADD CONSTRAINT "grow_spray_compliance_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_spray_compliance"
    ADD CONSTRAINT "grow_spray_compliance_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."grow_spray_compliance"
    ADD CONSTRAINT "grow_spray_compliance_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "grow_spray_equipment_equipment_id_fkey" FOREIGN KEY ("equipment_id") REFERENCES "public"."org_equipment"("id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "grow_spray_equipment_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "grow_spray_equipment_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "grow_spray_equipment_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_spray_equipment"
    ADD CONSTRAINT "grow_spray_equipment_water_uom_fkey" FOREIGN KEY ("water_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_application_uom_fkey" FOREIGN KEY ("application_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_grow_spray_compliance_id_fkey" FOREIGN KEY ("grow_spray_compliance_id") REFERENCES "public"."grow_spray_compliance"("id");



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_invnt_lot_id_fkey" FOREIGN KEY ("invnt_lot_id") REFERENCES "public"."invnt_lot"("id");



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_spray_input"
    ADD CONSTRAINT "grow_spray_input_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_task_photo"
    ADD CONSTRAINT "grow_task_photo_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_task_photo"
    ADD CONSTRAINT "grow_task_photo_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_task_photo"
    ADD CONSTRAINT "grow_task_photo_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_task_seed_batch"
    ADD CONSTRAINT "grow_task_seed_batch_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_task_seed_batch"
    ADD CONSTRAINT "grow_task_seed_batch_grow_cuke_seed_batch_id_fkey" FOREIGN KEY ("grow_cuke_seed_batch_id") REFERENCES "public"."grow_cuke_seed_batch"("id");



ALTER TABLE ONLY "public"."grow_task_seed_batch"
    ADD CONSTRAINT "grow_task_seed_batch_grow_lettuce_seed_batch_id_fkey" FOREIGN KEY ("grow_lettuce_seed_batch_id") REFERENCES "public"."grow_lettuce_seed_batch"("id");



ALTER TABLE ONLY "public"."grow_task_seed_batch"
    ADD CONSTRAINT "grow_task_seed_batch_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."grow_task_seed_batch"
    ADD CONSTRAINT "grow_task_seed_batch_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_trial_type"
    ADD CONSTRAINT "grow_trial_type_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_trial_type"
    ADD CONSTRAINT "grow_trial_type_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."grow_variety"
    ADD CONSTRAINT "grow_variety_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."grow_variety"
    ADD CONSTRAINT "grow_variety_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."edi_crodeon_weather"
    ADD CONSTRAINT "grow_weather_reading_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_department"
    ADD CONSTRAINT "hr_department_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_disciplinary_warning"
    ADD CONSTRAINT "hr_disciplinary_warning_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_disciplinary_warning"
    ADD CONSTRAINT "hr_disciplinary_warning_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_disciplinary_warning"
    ADD CONSTRAINT "hr_disciplinary_warning_reported_by_emp_fkey" FOREIGN KEY ("org_id", "reported_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_disciplinary_warning"
    ADD CONSTRAINT "hr_disciplinary_warning_reviewed_by_emp_fkey" FOREIGN KEY ("org_id", "reviewed_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_compensation_manager_id_emp_fkey" FOREIGN KEY ("org_id", "compensation_manager_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_housing_id_fkey" FOREIGN KEY ("housing_id") REFERENCES "public"."org_site_housing"("id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_hr_department_fkey" FOREIGN KEY ("org_id", "hr_department_id") REFERENCES "public"."hr_department"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_hr_work_authorization_fkey" FOREIGN KEY ("org_id", "hr_work_authorization_id") REFERENCES "public"."hr_work_authorization"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "hr_employee_review_created_by_emp_fkey" FOREIGN KEY ("org_id", "created_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "hr_employee_review_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "hr_employee_review_lead_id_emp_fkey" FOREIGN KEY ("org_id", "lead_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "hr_employee_review_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_employee_review"
    ADD CONSTRAINT "hr_employee_review_updated_by_emp_fkey" FOREIGN KEY ("org_id", "updated_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_sys_access_level_id_fkey" FOREIGN KEY ("sys_access_level_id") REFERENCES "public"."sys_access_level"("id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_team_lead_id_emp_fkey" FOREIGN KEY ("org_id", "team_lead_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_employee"
    ADD CONSTRAINT "hr_employee_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."hr_module_access"
    ADD CONSTRAINT "hr_module_access_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_module_access"
    ADD CONSTRAINT "hr_module_access_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_module_access"
    ADD CONSTRAINT "hr_module_access_org_module_fkey" FOREIGN KEY ("org_id", "sys_module_id") REFERENCES "public"."org_module"("org_id", "sys_module_id");



ALTER TABLE ONLY "public"."hr_payroll"
    ADD CONSTRAINT "hr_payroll_hr_department_fkey" FOREIGN KEY ("org_id", "hr_department_id") REFERENCES "public"."hr_department"("org_id", "id");



ALTER TABLE ONLY "public"."hr_payroll"
    ADD CONSTRAINT "hr_payroll_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_payroll"
    ADD CONSTRAINT "hr_payroll_hr_work_authorization_fkey" FOREIGN KEY ("org_id", "hr_work_authorization_id") REFERENCES "public"."hr_work_authorization"("org_id", "id");



ALTER TABLE ONLY "public"."hr_payroll"
    ADD CONSTRAINT "hr_payroll_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_time_off_request"
    ADD CONSTRAINT "hr_time_off_request_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_time_off_request"
    ADD CONSTRAINT "hr_time_off_request_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_time_off_request"
    ADD CONSTRAINT "hr_time_off_request_requested_by_emp_fkey" FOREIGN KEY ("org_id", "requested_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_time_off_request"
    ADD CONSTRAINT "hr_time_off_request_reviewed_by_emp_fkey" FOREIGN KEY ("org_id", "reviewed_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_travel_request"
    ADD CONSTRAINT "hr_travel_request_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_travel_request"
    ADD CONSTRAINT "hr_travel_request_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."hr_travel_request"
    ADD CONSTRAINT "hr_travel_request_requested_by_emp_fkey" FOREIGN KEY ("org_id", "requested_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_travel_request"
    ADD CONSTRAINT "hr_travel_request_reviewed_by_emp_fkey" FOREIGN KEY ("org_id", "reviewed_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."hr_work_authorization"
    ADD CONSTRAINT "hr_work_authorization_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_category"
    ADD CONSTRAINT "invnt_category_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_burn_uom_fkey" FOREIGN KEY ("burn_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_equipment_id_fkey" FOREIGN KEY ("equipment_id") REFERENCES "public"."org_equipment"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_grow_variety_id_fkey" FOREIGN KEY ("grow_variety_id") REFERENCES "public"."grow_variety"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_invnt_category_id_fkey" FOREIGN KEY ("invnt_category_id") REFERENCES "public"."invnt_category"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_invnt_subcategory_id_fkey" FOREIGN KEY ("invnt_subcategory_id") REFERENCES "public"."invnt_category"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_invnt_vendor_id_fkey" FOREIGN KEY ("invnt_vendor_id") REFERENCES "public"."invnt_vendor"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_onhand_uom_fkey" FOREIGN KEY ("onhand_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_order_uom_fkey" FOREIGN KEY ("order_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_item"
    ADD CONSTRAINT "invnt_item_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."invnt_lot"
    ADD CONSTRAINT "invnt_lot_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_lot"
    ADD CONSTRAINT "invnt_lot_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."invnt_lot"
    ADD CONSTRAINT "invnt_lot_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_burn_uom_fkey" FOREIGN KEY ("burn_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_invnt_lot_id_fkey" FOREIGN KEY ("invnt_lot_id") REFERENCES "public"."invnt_lot"("id");



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_onhand_uom_fkey" FOREIGN KEY ("onhand_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_onhand"
    ADD CONSTRAINT "invnt_onhand_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_burn_uom_fkey" FOREIGN KEY ("burn_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_invnt_category_id_fkey" FOREIGN KEY ("invnt_category_id") REFERENCES "public"."invnt_category"("id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_invnt_vendor_id_fkey" FOREIGN KEY ("invnt_vendor_id") REFERENCES "public"."invnt_vendor"("id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_order_uom_fkey" FOREIGN KEY ("order_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_ordered_by_emp_fkey" FOREIGN KEY ("org_id", "ordered_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_po_received"
    ADD CONSTRAINT "invnt_po_received_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_po_received"
    ADD CONSTRAINT "invnt_po_received_invnt_lot_id_fkey" FOREIGN KEY ("invnt_lot_id") REFERENCES "public"."invnt_lot"("id");



ALTER TABLE ONLY "public"."invnt_po_received"
    ADD CONSTRAINT "invnt_po_received_invnt_po_id_fkey" FOREIGN KEY ("invnt_po_id") REFERENCES "public"."invnt_po"("id");



ALTER TABLE ONLY "public"."invnt_po_received"
    ADD CONSTRAINT "invnt_po_received_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."invnt_po_received"
    ADD CONSTRAINT "invnt_po_received_received_uom_fkey" FOREIGN KEY ("received_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_requested_by_emp_fkey" FOREIGN KEY ("org_id", "requested_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_po"
    ADD CONSTRAINT "invnt_po_reviewed_by_emp_fkey" FOREIGN KEY ("org_id", "reviewed_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."invnt_vendor"
    ADD CONSTRAINT "invnt_vendor_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_equipment_id_fkey" FOREIGN KEY ("equipment_id") REFERENCES "public"."org_equipment"("id");



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_fixer_id_emp_fkey" FOREIGN KEY ("org_id", "fixer_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "maint_request_invnt_item_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "maint_request_invnt_item_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "maint_request_invnt_item_maint_request_id_fkey" FOREIGN KEY ("maint_request_id") REFERENCES "public"."maint_request"("id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "maint_request_invnt_item_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."maint_request_invnt_item"
    ADD CONSTRAINT "maint_request_invnt_item_uom_fkey" FOREIGN KEY ("uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."maint_request_photo"
    ADD CONSTRAINT "maint_request_photo_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."maint_request_photo"
    ADD CONSTRAINT "maint_request_photo_maint_request_id_fkey" FOREIGN KEY ("maint_request_id") REFERENCES "public"."maint_request"("id");



ALTER TABLE ONLY "public"."maint_request_photo"
    ADD CONSTRAINT "maint_request_photo_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_requested_by_emp_fkey" FOREIGN KEY ("org_id", "requested_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."maint_request"
    ADD CONSTRAINT "maint_request_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_choice"
    ADD CONSTRAINT "ops_corrective_action_choice_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_assigned_to_emp_fkey" FOREIGN KEY ("org_id", "assigned_to") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_fsafe_pest_result_id_fkey" FOREIGN KEY ("fsafe_pest_result_id") REFERENCES "public"."fsafe_pest_result"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_fsafe_result_id_fkey" FOREIGN KEY ("fsafe_result_id") REFERENCES "public"."fsafe_result"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_ops_corrective_action_choice_i_fkey" FOREIGN KEY ("ops_corrective_action_choice_id") REFERENCES "public"."ops_corrective_action_choice"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_ops_template_id_fkey" FOREIGN KEY ("ops_template_id") REFERENCES "public"."ops_template"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_ops_template_result_id_fkey" FOREIGN KEY ("ops_template_result_id") REFERENCES "public"."ops_template_result"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_corrective_action_taken"
    ADD CONSTRAINT "ops_corrective_action_taken_verified_by_emp_fkey" FOREIGN KEY ("org_id", "verified_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."ops_task"
    ADD CONSTRAINT "ops_task_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_task"
    ADD CONSTRAINT "ops_task_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_task_schedule"
    ADD CONSTRAINT "ops_task_schedule_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_task_schedule"
    ADD CONSTRAINT "ops_task_schedule_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."ops_task_schedule"
    ADD CONSTRAINT "ops_task_schedule_ops_task_id_fkey" FOREIGN KEY ("ops_task_id") REFERENCES "public"."ops_task"("id");



ALTER TABLE ONLY "public"."ops_task_schedule"
    ADD CONSTRAINT "ops_task_schedule_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."ops_task_schedule"
    ADD CONSTRAINT "ops_task_schedule_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_task_template"
    ADD CONSTRAINT "ops_task_template_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_task_template"
    ADD CONSTRAINT "ops_task_template_ops_task_id_fkey" FOREIGN KEY ("ops_task_id") REFERENCES "public"."ops_task"("id");



ALTER TABLE ONLY "public"."ops_task_template"
    ADD CONSTRAINT "ops_task_template_ops_template_id_fkey" FOREIGN KEY ("ops_template_id") REFERENCES "public"."ops_template"("id");



ALTER TABLE ONLY "public"."ops_task_template"
    ADD CONSTRAINT "ops_task_template_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_ops_task_id_fkey" FOREIGN KEY ("ops_task_id") REFERENCES "public"."ops_task"("id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."ops_task_tracker"
    ADD CONSTRAINT "ops_task_tracker_verified_by_emp_fkey" FOREIGN KEY ("org_id", "verified_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."ops_template"
    ADD CONSTRAINT "ops_template_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_template"
    ADD CONSTRAINT "ops_template_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_template"
    ADD CONSTRAINT "ops_template_org_module_fkey" FOREIGN KEY ("org_id", "sys_module_id") REFERENCES "public"."org_module"("org_id", "sys_module_id");



ALTER TABLE ONLY "public"."ops_template_question"
    ADD CONSTRAINT "ops_template_question_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_template_question"
    ADD CONSTRAINT "ops_template_question_ops_template_id_fkey" FOREIGN KEY ("ops_template_id") REFERENCES "public"."ops_template"("id");



ALTER TABLE ONLY "public"."ops_template_question"
    ADD CONSTRAINT "ops_template_question_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_equipment_id_fkey" FOREIGN KEY ("equipment_id") REFERENCES "public"."org_equipment"("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_ops_task_tracker_id_fkey" FOREIGN KEY ("ops_task_tracker_id") REFERENCES "public"."ops_task_tracker"("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_ops_template_id_fkey" FOREIGN KEY ("ops_template_id") REFERENCES "public"."ops_template"("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_ops_template_question_id_fkey" FOREIGN KEY ("ops_template_question_id") REFERENCES "public"."ops_template_question"("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_template_result_photo"
    ADD CONSTRAINT "ops_template_result_photo_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_template_result_photo"
    ADD CONSTRAINT "ops_template_result_photo_ops_template_result_id_fkey" FOREIGN KEY ("ops_template_result_id") REFERENCES "public"."ops_template_result"("id");



ALTER TABLE ONLY "public"."ops_template_result_photo"
    ADD CONSTRAINT "ops_template_result_photo_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_template_result"
    ADD CONSTRAINT "ops_template_result_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."ops_training_attendee"
    ADD CONSTRAINT "ops_training_attendee_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_training_attendee"
    ADD CONSTRAINT "ops_training_attendee_hr_employee_id_emp_fkey" FOREIGN KEY ("org_id", "hr_employee_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."ops_training_attendee"
    ADD CONSTRAINT "ops_training_attendee_ops_training_id_fkey" FOREIGN KEY ("ops_training_id") REFERENCES "public"."ops_training"("id");



ALTER TABLE ONLY "public"."ops_training_attendee"
    ADD CONSTRAINT "ops_training_attendee_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_training"
    ADD CONSTRAINT "ops_training_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."ops_training"
    ADD CONSTRAINT "ops_training_ops_training_type_id_fkey" FOREIGN KEY ("ops_training_type_id") REFERENCES "public"."ops_training_type"("id");



ALTER TABLE ONLY "public"."ops_training"
    ADD CONSTRAINT "ops_training_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_training"
    ADD CONSTRAINT "ops_training_trainer_id_emp_fkey" FOREIGN KEY ("org_id", "trainer_id") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."ops_training_type"
    ADD CONSTRAINT "ops_training_type_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."ops_training"
    ADD CONSTRAINT "ops_training_verified_by_emp_fkey" FOREIGN KEY ("org_id", "verified_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."org_business_rule"
    ADD CONSTRAINT "org_business_rule_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_equipment"
    ADD CONSTRAINT "org_equipment_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."org_equipment"
    ADD CONSTRAINT "org_equipment_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_farm"
    ADD CONSTRAINT "org_farm_growing_uom_fkey" FOREIGN KEY ("growing_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."org_farm"
    ADD CONSTRAINT "org_farm_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_farm"
    ADD CONSTRAINT "org_farm_volume_uom_fkey" FOREIGN KEY ("volume_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."org_farm"
    ADD CONSTRAINT "org_farm_weighing_uom_fkey" FOREIGN KEY ("weighing_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."org_module"
    ADD CONSTRAINT "org_module_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_module"
    ADD CONSTRAINT "org_module_sys_module_id_fkey" FOREIGN KEY ("sys_module_id") REFERENCES "public"."sys_module"("id");



ALTER TABLE ONLY "public"."org_quickbooks_token"
    ADD CONSTRAINT "org_quickbooks_token_connected_by_fkey" FOREIGN KEY ("org_id", "connected_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."org_quickbooks_token"
    ADD CONSTRAINT "org_quickbooks_token_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site_category"
    ADD CONSTRAINT "org_site_category_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_block"
    ADD CONSTRAINT "org_site_cuke_gh_block_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_block"
    ADD CONSTRAINT "org_site_cuke_gh_block_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_block"
    ADD CONSTRAINT "org_site_cuke_gh_block_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site_cuke_gh"("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh"
    ADD CONSTRAINT "org_site_cuke_gh_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."org_site_cuke_gh"
    ADD CONSTRAINT "org_site_cuke_gh_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_row"
    ADD CONSTRAINT "org_site_cuke_gh_row_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_row"
    ADD CONSTRAINT "org_site_cuke_gh_row_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site_cuke_gh_row"
    ADD CONSTRAINT "org_site_cuke_gh_row_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site_cuke_gh"("id");



ALTER TABLE ONLY "public"."org_site"
    ADD CONSTRAINT "org_site_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."org_site_housing_area"
    ADD CONSTRAINT "org_site_housing_area_housing_id_fkey" FOREIGN KEY ("housing_id") REFERENCES "public"."org_site_housing"("id");



ALTER TABLE ONLY "public"."org_site_housing_area"
    ADD CONSTRAINT "org_site_housing_area_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site_housing"
    ADD CONSTRAINT "org_site_housing_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site"
    ADD CONSTRAINT "org_site_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_site"
    ADD CONSTRAINT "org_site_site_id_parent_fkey" FOREIGN KEY ("site_id_parent") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."org_sub_module"
    ADD CONSTRAINT "org_sub_module_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."org_sub_module"
    ADD CONSTRAINT "org_sub_module_sys_access_level_id_fkey" FOREIGN KEY ("sys_access_level_id") REFERENCES "public"."sys_access_level"("id");



ALTER TABLE ONLY "public"."org_sub_module"
    ADD CONSTRAINT "org_sub_module_sys_module_id_fkey" FOREIGN KEY ("sys_module_id") REFERENCES "public"."sys_module"("id");



ALTER TABLE ONLY "public"."org_sub_module"
    ADD CONSTRAINT "org_sub_module_sys_sub_module_id_fkey" FOREIGN KEY ("sys_sub_module_id") REFERENCES "public"."sys_sub_module"("id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_grow_lettuce_seed_batch_id_fkey" FOREIGN KEY ("grow_lettuce_seed_batch_id") REFERENCES "public"."grow_lettuce_seed_batch"("id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_pack_dryer_result_id_original_fkey" FOREIGN KEY ("pack_moisture_id_original") REFERENCES "public"."pack_moisture"("id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."pack_fail_category"
    ADD CONSTRAINT "pack_fail_category_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_moisture_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_fail_category"
    ADD CONSTRAINT "pack_productivity_fail_category_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_pack_productivity_fail_categor_fkey" FOREIGN KEY ("pack_fail_category_id") REFERENCES "public"."pack_fail_category"("id");



ALTER TABLE ONLY "public"."pack_session_labor_hour"
    ADD CONSTRAINT "pack_productivity_hour_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_session_labor_hour"
    ADD CONSTRAINT "pack_productivity_hour_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "pack_session_leftover_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "pack_session_leftover_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."pack_shelf_life_metric"
    ADD CONSTRAINT "pack_shelf_life_metric_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_shelf_life_metric"
    ADD CONSTRAINT "pack_shelf_life_metric_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_pack_session_id_fkey" FOREIGN KEY ("pack_session_id") REFERENCES "public"."pack_session"("id");



ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_pack_shelf_life_id_fkey" FOREIGN KEY ("pack_shelf_life_id") REFERENCES "public"."pack_shelf_life"("id");



ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_pack_shelf_life_id_fkey" FOREIGN KEY ("pack_shelf_life_id") REFERENCES "public"."pack_shelf_life"("id");



ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_pack_shelf_life_metric_id_fkey" FOREIGN KEY ("pack_shelf_life_metric_id") REFERENCES "public"."pack_shelf_life_metric"("id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");



ALTER TABLE ONLY "public"."sales_container_type"
    ADD CONSTRAINT "sales_container_type_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_crm_external_product"
    ADD CONSTRAINT "sales_crm_external_product_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_crm_store"
    ADD CONSTRAINT "sales_crm_store_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_crm_store"
    ADD CONSTRAINT "sales_crm_store_sales_customer_id_fkey" FOREIGN KEY ("sales_customer_id") REFERENCES "public"."sales_customer"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit"
    ADD CONSTRAINT "sales_crm_store_visit_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_photo"
    ADD CONSTRAINT "sales_crm_store_visit_photo_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_photo"
    ADD CONSTRAINT "sales_crm_store_visit_photo_sales_crm_store_visit_id_fkey" FOREIGN KEY ("sales_crm_store_visit_id") REFERENCES "public"."sales_crm_store_visit"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_result"
    ADD CONSTRAINT "sales_crm_store_visit_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_result"
    ADD CONSTRAINT "sales_crm_store_visit_result_sales_crm_external_product_id_fkey" FOREIGN KEY ("sales_crm_external_product_id") REFERENCES "public"."sales_crm_external_product"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_result"
    ADD CONSTRAINT "sales_crm_store_visit_result_sales_crm_store_visit_id_fkey" FOREIGN KEY ("sales_crm_store_visit_id") REFERENCES "public"."sales_crm_store_visit"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit_result"
    ADD CONSTRAINT "sales_crm_store_visit_result_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit"
    ADD CONSTRAINT "sales_crm_store_visit_sales_crm_store_id_fkey" FOREIGN KEY ("sales_crm_store_id") REFERENCES "public"."sales_crm_store"("id");



ALTER TABLE ONLY "public"."sales_crm_store_visit"
    ADD CONSTRAINT "sales_crm_store_visit_visited_by_emp_fkey" FOREIGN KEY ("org_id", "visited_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."sales_customer_group"
    ADD CONSTRAINT "sales_customer_group_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_customer"
    ADD CONSTRAINT "sales_customer_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_customer"
    ADD CONSTRAINT "sales_customer_sales_customer_group_id_fkey" FOREIGN KEY ("sales_customer_group_id") REFERENCES "public"."sales_customer_group"("id");



ALTER TABLE ONLY "public"."sales_customer"
    ADD CONSTRAINT "sales_customer_sales_fob_id_fkey" FOREIGN KEY ("sales_fob_id") REFERENCES "public"."sales_fob"("id");



ALTER TABLE ONLY "public"."sales_fob"
    ADD CONSTRAINT "sales_fob_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_invoice"
    ADD CONSTRAINT "sales_invoice_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."sales_invoice"
    ADD CONSTRAINT "sales_invoice_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_pallet_allocation"
    ADD CONSTRAINT "sales_pallet_allocation_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_pallet_allocation"
    ADD CONSTRAINT "sales_pallet_allocation_sales_pallet_id_fkey" FOREIGN KEY ("sales_pallet_id") REFERENCES "public"."sales_pallet"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_pallet_allocation"
    ADD CONSTRAINT "sales_pallet_allocation_sales_po_fulfillment_id_fkey" FOREIGN KEY ("sales_po_fulfillment_id") REFERENCES "public"."sales_po_fulfillment"("id");



ALTER TABLE ONLY "public"."sales_pallet"
    ADD CONSTRAINT "sales_pallet_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."sales_pallet"
    ADD CONSTRAINT "sales_pallet_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_pallet"
    ADD CONSTRAINT "sales_pallet_sales_sps_shipment_container_id_fkey" FOREIGN KEY ("sales_sps_shipment_container_id") REFERENCES "public"."sales_sps_shipment_container"("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_approved_by_emp_fkey" FOREIGN KEY ("org_id", "approved_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."sales_po_fulfillment"
    ADD CONSTRAINT "sales_po_fulfillment_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."sales_po_fulfillment"
    ADD CONSTRAINT "sales_po_fulfillment_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_po_fulfillment"
    ADD CONSTRAINT "sales_po_fulfillment_pack_session_id_fkey" FOREIGN KEY ("pack_session_id") REFERENCES "public"."pack_session"("id");



ALTER TABLE ONLY "public"."sales_po_fulfillment"
    ADD CONSTRAINT "sales_po_fulfillment_sales_po_id_fkey" FOREIGN KEY ("sales_po_id") REFERENCES "public"."sales_po"("id");



ALTER TABLE ONLY "public"."sales_po_fulfillment"
    ADD CONSTRAINT "sales_po_fulfillment_sales_po_line_id_fkey" FOREIGN KEY ("sales_po_line_id") REFERENCES "public"."sales_po_line"("id");



ALTER TABLE ONLY "public"."sales_po_line"
    ADD CONSTRAINT "sales_po_line_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."sales_po_line"
    ADD CONSTRAINT "sales_po_line_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_po_line"
    ADD CONSTRAINT "sales_po_line_sales_po_id_fkey" FOREIGN KEY ("sales_po_id") REFERENCES "public"."sales_po"("id");



ALTER TABLE ONLY "public"."sales_po_line"
    ADD CONSTRAINT "sales_po_line_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_qb_uploaded_by_emp_fkey" FOREIGN KEY ("org_id", "qb_uploaded_by") REFERENCES "public"."hr_employee"("org_id", "id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_sales_customer_group_id_fkey" FOREIGN KEY ("sales_customer_group_id") REFERENCES "public"."sales_customer_group"("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_sales_customer_id_fkey" FOREIGN KEY ("sales_customer_id") REFERENCES "public"."sales_customer"("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_sales_fob_id_fkey" FOREIGN KEY ("sales_fob_id") REFERENCES "public"."sales_fob"("id");



ALTER TABLE ONLY "public"."sales_po"
    ADD CONSTRAINT "sales_po_sales_sps_trading_partner_id_fkey" FOREIGN KEY ("sales_sps_trading_partner_id") REFERENCES "public"."sales_sps_trading_partner"("id");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_dimension_uom_fkey" FOREIGN KEY ("dimension_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_grow_grade_id_fkey" FOREIGN KEY ("grow_grade_id") REFERENCES "public"."grow_grade"("id");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_item_uom_fkey" FOREIGN KEY ("item_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_product"
    ADD CONSTRAINT "sales_product_pack_uom_fkey" FOREIGN KEY ("pack_uom") REFERENCES "public"."sys_uom"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_sales_customer_group_id_fkey" FOREIGN KEY ("sales_customer_group_id") REFERENCES "public"."sales_customer_group"("id");



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_sales_customer_id_fkey" FOREIGN KEY ("sales_customer_id") REFERENCES "public"."sales_customer"("id");



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_sales_fob_id_fkey" FOREIGN KEY ("sales_fob_id") REFERENCES "public"."sales_fob"("id");



ALTER TABLE ONLY "public"."sales_product_price"
    ADD CONSTRAINT "sales_product_price_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."sales_sps_edi_inbound_message"
    ADD CONSTRAINT "sales_sps_edi_inbound_message_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_edi_inbound_message"
    ADD CONSTRAINT "sales_sps_edi_inbound_message_sales_po_id_fkey" FOREIGN KEY ("sales_po_id") REFERENCES "public"."sales_po"("id");



ALTER TABLE ONLY "public"."sales_sps_edi_inbound_message"
    ADD CONSTRAINT "sales_sps_edi_inbound_message_sales_sps_trading_partner_id_fkey" FOREIGN KEY ("sales_sps_trading_partner_id") REFERENCES "public"."sales_sps_trading_partner"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_pack_session_id_fkey" FOREIGN KEY ("pack_session_id") REFERENCES "public"."pack_session"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_parent_carton_id_fkey" FOREIGN KEY ("parent_carton_id") REFERENCES "public"."sales_sps_po_asn_carton"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_sales_po_fulfillment_id_fkey" FOREIGN KEY ("sales_po_fulfillment_id") REFERENCES "public"."sales_po_fulfillment"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_sales_po_line_id_fkey" FOREIGN KEY ("sales_po_line_id") REFERENCES "public"."sales_po_line"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_sales_sps_po_asn_id_fkey" FOREIGN KEY ("sales_sps_po_asn_id") REFERENCES "public"."sales_sps_po_asn"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_sps_po_asn_carton"
    ADD CONSTRAINT "sales_sps_po_asn_carton_weight_uom_fkey" FOREIGN KEY ("weight_uom") REFERENCES "public"."sys_uom"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn"
    ADD CONSTRAINT "sales_sps_po_asn_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn"
    ADD CONSTRAINT "sales_sps_po_asn_sales_po_id_fkey" FOREIGN KEY ("sales_po_id") REFERENCES "public"."sales_po"("id");



ALTER TABLE ONLY "public"."sales_sps_po_asn"
    ADD CONSTRAINT "sales_sps_po_asn_sales_sps_shipment_container_id_fkey" FOREIGN KEY ("sales_sps_shipment_container_id") REFERENCES "public"."sales_sps_shipment_container"("id");



ALTER TABLE ONLY "public"."sales_sps_product_buyer_part"
    ADD CONSTRAINT "sales_sps_product_buyer_part_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_product_buyer_part"
    ADD CONSTRAINT "sales_sps_product_buyer_part_sales_customer_id_fkey" FOREIGN KEY ("sales_customer_id") REFERENCES "public"."sales_customer"("id");



ALTER TABLE ONLY "public"."sales_sps_product_buyer_part"
    ADD CONSTRAINT "sales_sps_product_buyer_part_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");



ALTER TABLE ONLY "public"."sales_sps_shipment_container"
    ADD CONSTRAINT "sales_sps_shipment_container_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_shipment_container"
    ADD CONSTRAINT "sales_sps_shipment_container_sales_container_type_id_fkey" FOREIGN KEY ("sales_container_type_id") REFERENCES "public"."sales_container_type"("id");



ALTER TABLE ONLY "public"."sales_sps_shipment_container"
    ADD CONSTRAINT "sales_sps_shipment_container_sales_sps_shipment_id_fkey" FOREIGN KEY ("sales_sps_shipment_id") REFERENCES "public"."sales_sps_shipment"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales_sps_shipment_container"
    ADD CONSTRAINT "sales_sps_shipment_container_temperature_uom_fkey" FOREIGN KEY ("temperature_uom") REFERENCES "public"."sys_uom"("id");



ALTER TABLE ONLY "public"."sales_sps_shipment"
    ADD CONSTRAINT "sales_sps_shipment_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_trading_partner"
    ADD CONSTRAINT "sales_sps_trading_partner_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");



ALTER TABLE ONLY "public"."sales_sps_trading_partner"
    ADD CONSTRAINT "sales_sps_trading_partner_sales_customer_id_fkey" FOREIGN KEY ("sales_customer_id") REFERENCES "public"."sales_customer"("id");



ALTER TABLE ONLY "public"."sys_sub_module"
    ADD CONSTRAINT "sys_sub_module_sys_access_level_id_fkey" FOREIGN KEY ("sys_access_level_id") REFERENCES "public"."sys_access_level"("id");



ALTER TABLE ONLY "public"."sys_sub_module"
    ADD CONSTRAINT "sys_sub_module_sys_module_id_fkey" FOREIGN KEY ("sys_module_id") REFERENCES "public"."sys_module"("id");



ALTER TABLE "public"."edi_crodeon_weather" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "edi_crodeon_weather_read" ON "public"."edi_crodeon_weather" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."edi_qb_expense" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."edi_qb_expense_line" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "edi_qb_expense_line_read" ON "public"."edi_qb_expense_line" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "edi_qb_expense_read" ON "public"."edi_qb_expense" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."edi_qb_invoice" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."edi_qb_invoice_line" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "edi_qb_invoice_line_read" ON "public"."edi_qb_invoice_line" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "edi_qb_invoice_read" ON "public"."edi_qb_invoice" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fin_expense" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fin_expense_delete" ON "public"."fin_expense" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fin_expense_insert" ON "public"."fin_expense" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fin_expense_read" ON "public"."fin_expense" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fin_expense_update" ON "public"."fin_expense" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fsafe_lab" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fsafe_lab_delete" ON "public"."fsafe_lab" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_lab_insert" ON "public"."fsafe_lab" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_lab_read" ON "public"."fsafe_lab" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fsafe_lab_test" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fsafe_lab_test_delete" ON "public"."fsafe_lab_test" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_lab_test_insert" ON "public"."fsafe_lab_test" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_lab_test_read" ON "public"."fsafe_lab_test" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_lab_test_update" ON "public"."fsafe_lab_test" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_lab_update" ON "public"."fsafe_lab" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fsafe_pest_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fsafe_pest_result_delete" ON "public"."fsafe_pest_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_pest_result_insert" ON "public"."fsafe_pest_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_pest_result_read" ON "public"."fsafe_pest_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_pest_result_update" ON "public"."fsafe_pest_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fsafe_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fsafe_result_delete" ON "public"."fsafe_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_result_insert" ON "public"."fsafe_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_result_read" ON "public"."fsafe_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_result_update" ON "public"."fsafe_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fsafe_test_hold" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fsafe_test_hold_delete" ON "public"."fsafe_test_hold" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_test_hold_insert" ON "public"."fsafe_test_hold" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."fsafe_test_hold_po" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "fsafe_test_hold_po_delete" ON "public"."fsafe_test_hold_po" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_test_hold_po_insert" ON "public"."fsafe_test_hold_po" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_test_hold_po_read" ON "public"."fsafe_test_hold_po" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_test_hold_po_update" ON "public"."fsafe_test_hold_po" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_test_hold_read" ON "public"."fsafe_test_hold" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "fsafe_test_hold_update" ON "public"."fsafe_test_hold" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_chemistry_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_chemistry_result_delete" ON "public"."grow_chemistry_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_chemistry_result_insert" ON "public"."grow_chemistry_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_chemistry_result_read" ON "public"."grow_chemistry_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_chemistry_result_update" ON "public"."grow_chemistry_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_cuke_gh_row_planting" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_cuke_gh_row_planting_delete" ON "public"."grow_cuke_gh_row_planting" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_cuke_gh_row_planting_insert" ON "public"."grow_cuke_gh_row_planting" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_cuke_gh_row_planting_read" ON "public"."grow_cuke_gh_row_planting" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_cuke_gh_row_planting_update" ON "public"."grow_cuke_gh_row_planting" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_cuke_rotation" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_cuke_rotation_read" ON "public"."grow_cuke_rotation" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_cuke_seed_batch" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_cuke_seed_batch_anon_read" ON "public"."grow_cuke_seed_batch" FOR SELECT TO "anon" USING (true);



CREATE POLICY "grow_cuke_seed_batch_delete" ON "public"."grow_cuke_seed_batch" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_cuke_seed_batch_insert" ON "public"."grow_cuke_seed_batch" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_cuke_seed_batch_read" ON "public"."grow_cuke_seed_batch" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_cuke_seed_batch_update" ON "public"."grow_cuke_seed_batch" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_cycle_pattern" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_cycle_pattern_read" ON "public"."grow_cycle_pattern" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_fertigation" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_fertigation_delete" ON "public"."grow_fertigation" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_insert" ON "public"."grow_fertigation" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_read" ON "public"."grow_fertigation" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_fertigation_recipe" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_fertigation_recipe_delete" ON "public"."grow_fertigation_recipe" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_insert" ON "public"."grow_fertigation_recipe" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_fertigation_recipe_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_fertigation_recipe_item_delete" ON "public"."grow_fertigation_recipe_item" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_item_insert" ON "public"."grow_fertigation_recipe_item" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_item_read" ON "public"."grow_fertigation_recipe_item" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_item_update" ON "public"."grow_fertigation_recipe_item" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_read" ON "public"."grow_fertigation_recipe" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_fertigation_recipe_site" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_fertigation_recipe_site_delete" ON "public"."grow_fertigation_recipe_site" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_site_insert" ON "public"."grow_fertigation_recipe_site" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_site_read" ON "public"."grow_fertigation_recipe_site" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_site_update" ON "public"."grow_fertigation_recipe_site" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_recipe_update" ON "public"."grow_fertigation_recipe" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_fertigation_update" ON "public"."grow_fertigation" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_grade" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_grade_read" ON "public"."grow_grade" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_harvest_container" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_harvest_container_delete" ON "public"."grow_harvest_container" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_harvest_container_insert" ON "public"."grow_harvest_container" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_harvest_container_read" ON "public"."grow_harvest_container" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_harvest_container_update" ON "public"."grow_harvest_container" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_harvest_weight" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_harvest_weight_anon_read" ON "public"."grow_harvest_weight" FOR SELECT TO "anon" USING (true);



CREATE POLICY "grow_harvest_weight_delete" ON "public"."grow_harvest_weight" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_harvest_weight_insert" ON "public"."grow_harvest_weight" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_harvest_weight_read" ON "public"."grow_harvest_weight" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_harvest_weight_update" ON "public"."grow_harvest_weight" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_lettuce_seed_batch" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_lettuce_seed_batch_delete" ON "public"."grow_lettuce_seed_batch" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_batch_insert" ON "public"."grow_lettuce_seed_batch" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_batch_read" ON "public"."grow_lettuce_seed_batch" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_batch_update" ON "public"."grow_lettuce_seed_batch" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_lettuce_seed_mix" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_lettuce_seed_mix_delete" ON "public"."grow_lettuce_seed_mix" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_mix_insert" ON "public"."grow_lettuce_seed_mix" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_lettuce_seed_mix_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_lettuce_seed_mix_item_delete" ON "public"."grow_lettuce_seed_mix_item" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_mix_item_insert" ON "public"."grow_lettuce_seed_mix_item" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_mix_item_read" ON "public"."grow_lettuce_seed_mix_item" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_mix_item_update" ON "public"."grow_lettuce_seed_mix_item" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_mix_read" ON "public"."grow_lettuce_seed_mix" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_lettuce_seed_mix_update" ON "public"."grow_lettuce_seed_mix" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_monitoring_metric" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_monitoring_metric_read" ON "public"."grow_monitoring_metric" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_monitoring_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_monitoring_result_delete" ON "public"."grow_monitoring_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_monitoring_result_insert" ON "public"."grow_monitoring_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_monitoring_result_read" ON "public"."grow_monitoring_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_monitoring_result_update" ON "public"."grow_monitoring_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_scout_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_scout_result_delete" ON "public"."grow_scout_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_scout_result_insert" ON "public"."grow_scout_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_scout_result_read" ON "public"."grow_scout_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_scout_result_update" ON "public"."grow_scout_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_spray_compliance" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_spray_compliance_read" ON "public"."grow_spray_compliance" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_spray_equipment" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_spray_equipment_delete" ON "public"."grow_spray_equipment" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_spray_equipment_insert" ON "public"."grow_spray_equipment" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_spray_equipment_read" ON "public"."grow_spray_equipment" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_spray_equipment_update" ON "public"."grow_spray_equipment" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_spray_input" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_spray_input_delete" ON "public"."grow_spray_input" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_spray_input_insert" ON "public"."grow_spray_input" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_spray_input_read" ON "public"."grow_spray_input" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_spray_input_update" ON "public"."grow_spray_input" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_task_photo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_task_photo_delete" ON "public"."grow_task_photo" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_task_photo_insert" ON "public"."grow_task_photo" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_task_photo_read" ON "public"."grow_task_photo" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_task_photo_update" ON "public"."grow_task_photo" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_task_seed_batch" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_task_seed_batch_delete" ON "public"."grow_task_seed_batch" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_task_seed_batch_insert" ON "public"."grow_task_seed_batch" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_task_seed_batch_read" ON "public"."grow_task_seed_batch" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_task_seed_batch_update" ON "public"."grow_task_seed_batch" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_trial_type" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_trial_type_read" ON "public"."grow_trial_type" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."grow_variety" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "grow_variety_read" ON "public"."grow_variety" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_weather_reading_delete" ON "public"."edi_crodeon_weather" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_weather_reading_insert" ON "public"."edi_crodeon_weather" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "grow_weather_reading_update" ON "public"."edi_crodeon_weather" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_department" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_department_read" ON "public"."hr_department" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_disciplinary_warning" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_disciplinary_warning_delete" ON "public"."hr_disciplinary_warning" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_disciplinary_warning_insert" ON "public"."hr_disciplinary_warning" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_disciplinary_warning_read" ON "public"."hr_disciplinary_warning" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_disciplinary_warning_update" ON "public"."hr_disciplinary_warning" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_employee" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_employee_delete" ON "public"."hr_employee" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_employee_insert" ON "public"."hr_employee" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_employee_read" ON "public"."hr_employee" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_employee_review" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_employee_review_delete" ON "public"."hr_employee_review" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_employee_review_insert" ON "public"."hr_employee_review" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_employee_review_read" ON "public"."hr_employee_review" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_employee_review_update" ON "public"."hr_employee_review" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_employee_update" ON "public"."hr_employee" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_module_access" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_module_access_read" ON "public"."hr_module_access" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_payroll" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_payroll_delete" ON "public"."hr_payroll" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_payroll_insert" ON "public"."hr_payroll" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_payroll_read" ON "public"."hr_payroll" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_payroll_update" ON "public"."hr_payroll" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_time_off_request" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_time_off_request_delete" ON "public"."hr_time_off_request" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_time_off_request_insert" ON "public"."hr_time_off_request" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_time_off_request_read" ON "public"."hr_time_off_request" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_time_off_request_update" ON "public"."hr_time_off_request" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_travel_request" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_travel_request_delete" ON "public"."hr_travel_request" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_travel_request_insert" ON "public"."hr_travel_request" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_travel_request_read" ON "public"."hr_travel_request" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "hr_travel_request_update" ON "public"."hr_travel_request" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."hr_work_authorization" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "hr_work_authorization_read" ON "public"."hr_work_authorization" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_category" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_category_read" ON "public"."invnt_category" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_item_anon_read" ON "public"."invnt_item" FOR SELECT TO "anon" USING (true);



CREATE POLICY "invnt_item_read" ON "public"."invnt_item" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_lot" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_lot_delete" ON "public"."invnt_lot" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_lot_insert" ON "public"."invnt_lot" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_lot_read" ON "public"."invnt_lot" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_lot_update" ON "public"."invnt_lot" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_onhand" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_onhand_delete" ON "public"."invnt_onhand" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_onhand_insert" ON "public"."invnt_onhand" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_onhand_read" ON "public"."invnt_onhand" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_onhand_update" ON "public"."invnt_onhand" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_po" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_po_delete" ON "public"."invnt_po" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_po_insert" ON "public"."invnt_po" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_po_read" ON "public"."invnt_po" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_po_received" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_po_received_delete" ON "public"."invnt_po_received" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_po_received_insert" ON "public"."invnt_po_received" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_po_received_read" ON "public"."invnt_po_received" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_po_received_update" ON "public"."invnt_po_received" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "invnt_po_update" ON "public"."invnt_po" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."invnt_vendor" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invnt_vendor_read" ON "public"."invnt_vendor" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."maint_request" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maint_request_delete" ON "public"."maint_request" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_insert" ON "public"."maint_request" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."maint_request_invnt_item" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maint_request_invnt_item_delete" ON "public"."maint_request_invnt_item" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_invnt_item_insert" ON "public"."maint_request_invnt_item" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_invnt_item_read" ON "public"."maint_request_invnt_item" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_invnt_item_update" ON "public"."maint_request_invnt_item" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."maint_request_photo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "maint_request_photo_delete" ON "public"."maint_request_photo" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_photo_insert" ON "public"."maint_request_photo" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_photo_read" ON "public"."maint_request_photo" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_photo_update" ON "public"."maint_request_photo" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_read" ON "public"."maint_request" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "maint_request_update" ON "public"."maint_request" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_corrective_action_choice" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_corrective_action_choice_read" ON "public"."ops_corrective_action_choice" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_corrective_action_taken" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_corrective_action_taken_delete" ON "public"."ops_corrective_action_taken" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_corrective_action_taken_insert" ON "public"."ops_corrective_action_taken" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_corrective_action_taken_read" ON "public"."ops_corrective_action_taken" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_corrective_action_taken_update" ON "public"."ops_corrective_action_taken" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_task" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_task_read" ON "public"."ops_task" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_task_schedule" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_task_schedule_delete" ON "public"."ops_task_schedule" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_task_schedule_insert" ON "public"."ops_task_schedule" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_task_schedule_read" ON "public"."ops_task_schedule" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_task_schedule_update" ON "public"."ops_task_schedule" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_task_template" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_task_template_read" ON "public"."ops_task_template" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_task_tracker" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_task_tracker_delete" ON "public"."ops_task_tracker" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_task_tracker_insert" ON "public"."ops_task_tracker" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_task_tracker_read" ON "public"."ops_task_tracker" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_task_tracker_update" ON "public"."ops_task_tracker" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_template" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ops_template_question" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_template_question_read" ON "public"."ops_template_question" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_read" ON "public"."ops_template" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_template_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_template_result_delete" ON "public"."ops_template_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_result_insert" ON "public"."ops_template_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_template_result_photo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_template_result_photo_delete" ON "public"."ops_template_result_photo" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_result_photo_insert" ON "public"."ops_template_result_photo" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_result_photo_read" ON "public"."ops_template_result_photo" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_result_photo_update" ON "public"."ops_template_result_photo" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_result_read" ON "public"."ops_template_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_template_result_update" ON "public"."ops_template_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_training" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ops_training_attendee" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_training_attendee_delete" ON "public"."ops_training_attendee" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_attendee_insert" ON "public"."ops_training_attendee" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_attendee_read" ON "public"."ops_training_attendee" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_attendee_update" ON "public"."ops_training_attendee" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_delete" ON "public"."ops_training" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_insert" ON "public"."ops_training" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_read" ON "public"."ops_training" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."ops_training_type" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ops_training_type_read" ON "public"."ops_training_type" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "ops_training_update" ON "public"."ops_training" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."org_business_rule" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_business_rule_read" ON "public"."org_business_rule" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_equipment" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_equipment_read" ON "public"."org_equipment" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_farm" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_farm_read" ON "public"."org_farm" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_module" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_module_read" ON "public"."org_module" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_quickbooks_token" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_read" ON "public"."org" FOR SELECT TO "authenticated" USING (("id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_site" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."org_site_category" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_site_category_read" ON "public"."org_site_category" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_site_cuke_gh" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."org_site_cuke_gh_block" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_site_cuke_gh_block_read" ON "public"."org_site_cuke_gh_block" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "org_site_cuke_gh_read" ON "public"."org_site_cuke_gh" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_site_cuke_gh_row" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_site_cuke_gh_row_read" ON "public"."org_site_cuke_gh_row" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_site_housing" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."org_site_housing_area" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_site_housing_area_read" ON "public"."org_site_housing_area" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "org_site_housing_read" ON "public"."org_site_housing" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "org_site_read" ON "public"."org_site" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."org_sub_module" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_sub_module_read" ON "public"."org_sub_module" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_fail_category" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_fail_category_read" ON "public"."pack_fail_category" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_moisture" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_moisture_delete" ON "public"."pack_moisture" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_moisture_insert" ON "public"."pack_moisture" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_moisture_read" ON "public"."pack_moisture" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_moisture_update" ON "public"."pack_moisture" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_session" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pack_session_cases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_cases_delete" ON "public"."pack_session_cases" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_cases_insert" ON "public"."pack_session_cases" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_cases_read" ON "public"."pack_session_cases" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_cases_update" ON "public"."pack_session_cases" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_delete" ON "public"."pack_session" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_session_fails" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_fails_delete" ON "public"."pack_session_fails" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_fails_insert" ON "public"."pack_session_fails" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_fails_read" ON "public"."pack_session_fails" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_fails_update" ON "public"."pack_session_fails" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_insert" ON "public"."pack_session" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_session_labor_hour" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_labor_hour_delete" ON "public"."pack_session_labor_hour" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_labor_hour_insert" ON "public"."pack_session_labor_hour" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_labor_hour_read" ON "public"."pack_session_labor_hour" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_labor_hour_update" ON "public"."pack_session_labor_hour" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_session_leftover" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_leftover_delete" ON "public"."pack_session_leftover" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_leftover_insert" ON "public"."pack_session_leftover" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_leftover_read" ON "public"."pack_session_leftover" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_leftover_update" ON "public"."pack_session_leftover" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_read" ON "public"."pack_session" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_session_update" ON "public"."pack_session" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_shelf_life" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_delete" ON "public"."pack_shelf_life" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_insert" ON "public"."pack_shelf_life" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_shelf_life_metric" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_metric_read" ON "public"."pack_shelf_life_metric" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_shelf_life_photo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_photo_delete" ON "public"."pack_shelf_life_photo" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_photo_insert" ON "public"."pack_shelf_life_photo" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_photo_read" ON "public"."pack_shelf_life_photo" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_photo_update" ON "public"."pack_shelf_life_photo" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_read" ON "public"."pack_shelf_life" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."pack_shelf_life_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_result_delete" ON "public"."pack_shelf_life_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_result_insert" ON "public"."pack_shelf_life_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_result_read" ON "public"."pack_shelf_life_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_result_update" ON "public"."pack_shelf_life_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "pack_shelf_life_update" ON "public"."pack_shelf_life" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_container_type" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_container_type_read" ON "public"."sales_container_type" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_crm_external_product" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_crm_external_product_delete" ON "public"."sales_crm_external_product" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_external_product_insert" ON "public"."sales_crm_external_product" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_external_product_read" ON "public"."sales_crm_external_product" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_external_product_update" ON "public"."sales_crm_external_product" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_crm_store" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_crm_store_delete" ON "public"."sales_crm_store" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_insert" ON "public"."sales_crm_store" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_read" ON "public"."sales_crm_store" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_update" ON "public"."sales_crm_store" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_crm_store_visit" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_crm_store_visit_delete" ON "public"."sales_crm_store_visit" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_insert" ON "public"."sales_crm_store_visit" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_crm_store_visit_photo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_crm_store_visit_photo_delete" ON "public"."sales_crm_store_visit_photo" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_photo_insert" ON "public"."sales_crm_store_visit_photo" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_photo_read" ON "public"."sales_crm_store_visit_photo" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_photo_update" ON "public"."sales_crm_store_visit_photo" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_read" ON "public"."sales_crm_store_visit" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_crm_store_visit_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_crm_store_visit_result_delete" ON "public"."sales_crm_store_visit_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_result_insert" ON "public"."sales_crm_store_visit_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_result_read" ON "public"."sales_crm_store_visit_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_result_update" ON "public"."sales_crm_store_visit_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_crm_store_visit_update" ON "public"."sales_crm_store_visit" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_customer" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_customer_delete" ON "public"."sales_customer" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_customer_group" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_customer_group_delete" ON "public"."sales_customer_group" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_customer_group_insert" ON "public"."sales_customer_group" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_customer_group_read" ON "public"."sales_customer_group" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_customer_group_update" ON "public"."sales_customer_group" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_customer_insert" ON "public"."sales_customer" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_customer_read" ON "public"."sales_customer" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_customer_update" ON "public"."sales_customer" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_edi_inbound_message_read" ON "public"."sales_sps_edi_inbound_message" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_fob" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_fob_read" ON "public"."sales_fob" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_invoice" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_invoice_delete" ON "public"."sales_invoice" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_invoice_insert" ON "public"."sales_invoice" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_invoice_read" ON "public"."sales_invoice" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_invoice_update" ON "public"."sales_invoice" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_pallet" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_pallet_allocation" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_pallet_allocation_delete" ON "public"."sales_pallet_allocation" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_allocation_insert" ON "public"."sales_pallet_allocation" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_allocation_read" ON "public"."sales_pallet_allocation" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_allocation_update" ON "public"."sales_pallet_allocation" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_delete" ON "public"."sales_pallet" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_insert" ON "public"."sales_pallet" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_read" ON "public"."sales_pallet" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_pallet_update" ON "public"."sales_pallet" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_po" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_po_asn_carton_delete" ON "public"."sales_sps_po_asn_carton" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_carton_insert" ON "public"."sales_sps_po_asn_carton" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_carton_read" ON "public"."sales_sps_po_asn_carton" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_carton_update" ON "public"."sales_sps_po_asn_carton" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_delete" ON "public"."sales_sps_po_asn" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_insert" ON "public"."sales_sps_po_asn" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_read" ON "public"."sales_sps_po_asn" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_asn_update" ON "public"."sales_sps_po_asn" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_delete" ON "public"."sales_po" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_po_fulfillment" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_po_fulfillment_delete" ON "public"."sales_po_fulfillment" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_fulfillment_insert" ON "public"."sales_po_fulfillment" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_fulfillment_read" ON "public"."sales_po_fulfillment" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_fulfillment_update" ON "public"."sales_po_fulfillment" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_insert" ON "public"."sales_po" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_po_line" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_po_line_delete" ON "public"."sales_po_line" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_line_insert" ON "public"."sales_po_line" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_line_read" ON "public"."sales_po_line" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_line_update" ON "public"."sales_po_line" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_read" ON "public"."sales_po" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_po_update" ON "public"."sales_po" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_product" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_product_buyer_part_delete" ON "public"."sales_sps_product_buyer_part" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_buyer_part_insert" ON "public"."sales_sps_product_buyer_part" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_buyer_part_read" ON "public"."sales_sps_product_buyer_part" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_buyer_part_update" ON "public"."sales_sps_product_buyer_part" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_delete" ON "public"."sales_product" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_insert" ON "public"."sales_product" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_product_price" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_product_price_delete" ON "public"."sales_product_price" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_price_insert" ON "public"."sales_product_price" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_price_read" ON "public"."sales_product_price" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_price_update" ON "public"."sales_product_price" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_read" ON "public"."sales_product" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_product_update" ON "public"."sales_product" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_container_delete" ON "public"."sales_sps_shipment_container" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_container_insert" ON "public"."sales_sps_shipment_container" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_container_read" ON "public"."sales_sps_shipment_container" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_container_update" ON "public"."sales_sps_shipment_container" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_delete" ON "public"."sales_sps_shipment" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_insert" ON "public"."sales_sps_shipment" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_read" ON "public"."sales_sps_shipment" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_shipment_update" ON "public"."sales_sps_shipment" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



ALTER TABLE "public"."sales_sps_edi_inbound_message" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_sps_po_asn" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_sps_po_asn_carton" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_sps_product_buyer_part" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_sps_shipment" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_sps_shipment_container" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sales_sps_trading_partner" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_trading_partner_delete" ON "public"."sales_sps_trading_partner" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_trading_partner_insert" ON "public"."sales_sps_trading_partner" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_trading_partner_read" ON "public"."sales_sps_trading_partner" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



CREATE POLICY "sales_trading_partner_update" ON "public"."sales_sps_trading_partner" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));



REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_access_level"("target_org" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_access_level"("target_org" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_access_level"("target_org" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_employee_id"("target_org" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_employee_id"("target_org" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_employee_id"("target_org" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."chat_query"("q" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."chat_query"("q" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."chat_query"("q" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."chat_schema"() TO "anon";
GRANT ALL ON FUNCTION "public"."chat_schema"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."chat_schema"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_org_ids"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_org_ids"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_org_ids"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_auth_user"() TO "service_role";



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



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_crodeon_weather" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_crodeon_weather" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_crodeon_weather" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_crodeon_weather_dli" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_crodeon_weather_dli" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_crodeon_weather_dli" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense_line" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense_line" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense_line" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense_summary" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense_summary" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_expense_summary" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice_line" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice_line" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice_line" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_customer" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_customer" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_customer" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_product" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_product" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_product" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice_summary" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice_summary" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."edi_qb_invoice_summary" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fin_expense" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fin_expense" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fin_expense" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fin_expense_v" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fin_expense_v" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fin_expense_v" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_lab" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_lab" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_lab" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_lab_test" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_lab_test" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_lab_test" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_pest_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_pest_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_pest_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_test_hold" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_test_hold" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_test_hold" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_test_hold_po" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_test_hold_po" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."fsafe_test_hold_po" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_chemistry_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_chemistry_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_chemistry_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_gh_row_planting" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_gh_row_planting" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_gh_row_planting" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_seed_batch" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_seed_batch" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_seed_batch" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_harvest_weight" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_harvest_weight" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_harvest_weight" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_item" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_item" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_item" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_harvest" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_harvest" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_harvest" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_rotation" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_rotation" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cuke_rotation" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cycle_pattern" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cycle_pattern" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_cycle_pattern" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_disease" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_disease" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_disease" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe_item" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe_item" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe_item" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe_site" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe_site" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_fertigation_recipe_site" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_grade" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_grade" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_grade" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_harvest_container" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_harvest_container" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_harvest_container" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_batch" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_batch" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_batch" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_harvest" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_harvest" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_harvest" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_mix" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_mix" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_mix" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_mix_item" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_mix_item" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_lettuce_seed_mix_item" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_monitoring_metric" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_monitoring_metric" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_monitoring_metric" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_monitoring_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_monitoring_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_monitoring_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_pest" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_pest" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_pest" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_scout_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_scout_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_scout_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_compliance" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_compliance" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_compliance" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_equipment" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_equipment" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_equipment" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_input" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_input" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_input" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_tracker" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_tracker" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_tracker" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_restriction" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_restriction" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_spray_restriction" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_task_photo" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_task_photo" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_task_photo" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_task_seed_batch" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_task_seed_batch" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_task_seed_batch" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_trial_type" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_trial_type" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_trial_type" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_variety" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_variety" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."grow_variety" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_department" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_department" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_department" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_disciplinary_warning" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_disciplinary_warning" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_disciplinary_warning" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_employee" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_employee" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_employee" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_employee_review" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_employee_review" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_employee_review" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_module_access" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_module_access" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_module_access" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_schedule" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_schedule" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_schedule" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_by_task" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_by_task" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_by_task" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_data_secure" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_data_secure" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_data_secure" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_employee_comparison" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_employee_comparison" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_employee_comparison" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_task_comparison" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_task_comparison" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_payroll_task_comparison" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_module" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_module" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_module" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_sub_module" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_sub_module" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_sub_module" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_access_level" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_access_level" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_access_level" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_module" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_module" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_module" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_sub_module" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_sub_module" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_sub_module" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_rba_navigation" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_rba_navigation" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_rba_navigation" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_staffing_pp_detail_v" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_staffing_pp_detail_v" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_staffing_pp_detail_v" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_staffing_pp_v" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_staffing_pp_v" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_staffing_pp_v" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_time_off_request" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_time_off_request" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_time_off_request" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_travel_request" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_travel_request" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_travel_request" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_work_authorization" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_work_authorization" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."hr_work_authorization" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_category" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_category" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_category" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_onhand" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_onhand" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_onhand" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_po" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_po" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_po" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_po_received" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_po_received" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_po_received" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_item_summary" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_item_summary" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_item_summary" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_lot" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_lot" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_lot" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_vendor" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_vendor" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."invnt_vendor" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request_invnt_item" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request_invnt_item" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request_invnt_item" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request_photo" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request_photo" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."maint_request_photo" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_corrective_action_choice" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_corrective_action_choice" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_corrective_action_choice" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_corrective_action_taken" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_corrective_action_taken" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_corrective_action_taken" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_template" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_template" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_template" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_weekly_schedule" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_weekly_schedule" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_task_weekly_schedule" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_question" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_question" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_question" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_result_photo" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_result_photo" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_template_result_photo" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training_attendee" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training_attendee" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training_attendee" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training_type" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training_type" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."ops_training_type" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_business_rule" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_business_rule" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_business_rule" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_equipment" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_equipment" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_equipment" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_farm" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_farm" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_farm" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_quickbooks_token" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_category" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_category" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_category" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh_block" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh_block" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh_block" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh_row" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh_row" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_cuke_gh_row" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_area" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_area" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_area" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_tenant_count" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_tenant_count" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_tenant_count" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_tenants" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_tenants" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."org_site_housing_tenants" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_fail_category" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_fail_category" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_fail_category" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_moisture" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_moisture" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_moisture" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_cases" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_cases" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_cases" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_fails" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_fails" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_fails" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_labor_hour" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_labor_hour" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_labor_hour" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_leftover" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_leftover" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_leftover" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_summary_v" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_summary_v" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_summary_v" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_metric" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_metric" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_metric" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_photo" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_photo" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_photo" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_container_type" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_container_type" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_container_type" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_external_product" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_external_product" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_external_product" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit_photo" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit_photo" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit_photo" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit_result" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit_result" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_crm_store_visit_result" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_customer_group" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_customer_group" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_customer_group" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_fob" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_fob" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_fob" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoice" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoice" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoice" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoice_v" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoice_v" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_invoice_v" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_pallet" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_pallet" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_pallet" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_pallet_allocation" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_pallet_allocation" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_pallet_allocation" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po_fulfillment" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po_fulfillment" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po_fulfillment" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po_line" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po_line" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_po_line" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_product_price" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_product_price" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_product_price" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_edi_inbound_message" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_edi_inbound_message" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_edi_inbound_message" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_po_asn" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_po_asn" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_po_asn" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_po_asn_carton" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_po_asn_carton" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_po_asn_carton" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_product_buyer_part" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_product_buyer_part" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_product_buyer_part" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_shipment" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_shipment" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_shipment" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_shipment_container" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_shipment_container" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_shipment_container" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_trading_partner" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_trading_partner" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sales_sps_trading_partner" TO "service_role";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_uom" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_uom" TO "authenticated";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."sys_uom" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,USAGE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,USAGE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,USAGE ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO "service_role";




