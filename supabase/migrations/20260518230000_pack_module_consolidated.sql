-- pack module — consolidated schema (2026-05-18)
-- ==================================================================
-- This file is the canonical definition of every pack-related object
-- in the database. It REPLACES all prior pack_* migration files,
-- which have been deleted from the repo as part of this consolidation:
--
--   20260401000116_pack_lot.sql
--   20260401000118_pack_lot_item.sql
--   20260401000133_pack_shelf_life_metric.sql
--   20260401000134_pack_shelf_life.sql
--   20260401000135_pack_shelf_life_result.sql
--   20260401000136_pack_shelf_life_photo.sql
--   20260401000137_pack_dryer_result.sql
--   20260401000138_pack_productivity_fail_category.sql
--   20260401000139_pack_productivity_hour.sql
--   20260401000140_pack_productivity_hour_fail.sql
--   20260507230000_pack_dryer_result_drop_uoms.sql
--   20260511210504_pack_productivity_hour_add_fsafe_metal_detected.sql
--   20260513010000_pack_shelf_life_auto_terminate.sql
--   20260513010100_pack_shelf_life_photos_bucket.sql
--   20260513020000_pack_shelf_life_set_day_trigger.sql
--   20260513020100_pack_shelf_life_cascade_day.sql
--   20260514230000_pack_variety.sql
--   20260514230100_pack_session.sql
--   20260514230200_pack_session_product_run.sql
--   20260514230300_pack_session_leftover.sql
--   20260514230400_pack_productivity_hour_alter_for_session.sql
--   20260514230500_pack_session_product_hour.sql
--   20260514230600_pack_lot_alter_constraints.sql
--   20260514230700_pack_lot_default_lot_number_fn.sql
--   20260514230800_pack_session_product_run_lot_trigger.sql
--   20260514230900_pack_session_views.sql
--   20260514231000_pack_session_rls.sql
--   20260514234000_pack_session_write_policies.sql
--   20260515195000_pack_immutability_guards.sql
--   20260515200000_cleanup_jean_pack_test_data.sql
--   20260515210000_wipe_all_pack_test_data.sql
--   20260515220000_hard_delete_soft_deleted_pack.sql
--   20260515220500_wipe_pack_data_again.sql
--   20260515230000_wipe_pack_data_third.sql
--   20260518115800_pack_self_heal_lot_items.sql
--   20260518115900_pack_preflight_audit.sql
--   20260518120000_pack_drop_views_triggers_guards.sql
--   20260518120100_pack_truncate_test_data.sql
--   20260518120200_pack_session_restructure.sql
--   20260518120300_pack_session_labor_hour.sql
--   20260518120400_pack_session_cases.sql
--   20260518120500_pack_session_leftover_restructure.sql
--   20260518120600_pack_session_fails.sql
--   20260518120700_pack_renames.sql
--   20260518120800_pack_session_backfill_from_lot.sql
--   20260518121100_pack_shelf_life_redirect.sql
--   20260518121300_pack_lot_drop.sql
--   20260518121400_pack_session_summary_v.sql
--   20260518121500_pack_session_rls.sql
--   20260518121600_pack_immutability_guards.sql
--   20260518121700_pack_session_defaults_trigger.sql
--   20260518121800_pack_session_finalize.sql
--   20260518121900_pack_shelf_life_day_recreate.sql
--   20260518150000_pack_disable_packlot_submodule.sql
--   20260518160000_pack_data_audit_diagnostic.sql
--   20260518170000_pack_session_fix_invalid_stopped.sql
--
-- The original versions are marked `--status reverted` in
-- supabase_migrations.schema_migrations on both dev and prod so they
-- no longer participate in the migration history -- the live DB state
-- is what THIS file alone is the source of truth for.
--
-- On apply: drops everything pack-related and recreates from scratch.
-- ALL EXISTING PACK DATA IS LOST. This is intentional -- the schema
-- has churned past the point where preservation is meaningful.
--
-- The body of this file (everything below the second `-- =====` rule)
-- is the verbatim output of `supabase db dump --schema public` against
-- dev on 2026-05-18, filtered to pack_-target statements by
-- scripts/carve_pack_from_dump.py. See docs/schema/pack_extracted.sql
-- for the standalone reference.

-- ==================================================================
-- Drop section: wipe everything pack-related.
-- ==================================================================

-- Views first (no dependents).
DROP VIEW IF EXISTS public.pack_session_summary_v CASCADE;

-- Tables. CASCADE drops dependent FKs from non-pack tables
-- (those FKs are reapplied by this migration's body where they
-- originate on the pack side).
DROP TABLE IF EXISTS public.pack_session_cases CASCADE;
DROP TABLE IF EXISTS public.pack_session_fails CASCADE;
DROP TABLE IF EXISTS public.pack_session_labor_hour CASCADE;
DROP TABLE IF EXISTS public.pack_session_leftover CASCADE;
DROP TABLE IF EXISTS public.pack_session CASCADE;
DROP TABLE IF EXISTS public.pack_fail_category CASCADE;
DROP TABLE IF EXISTS public.pack_moisture CASCADE;
DROP TABLE IF EXISTS public.pack_shelf_life_photo CASCADE;
DROP TABLE IF EXISTS public.pack_shelf_life_result CASCADE;
DROP TABLE IF EXISTS public.pack_shelf_life CASCADE;
DROP TABLE IF EXISTS public.pack_shelf_life_metric CASCADE;
DROP TABLE IF EXISTS public.pack_lot_item CASCADE;
DROP TABLE IF EXISTS public.pack_lot CASCADE;
DROP TABLE IF EXISTS public.pack_productivity_hour_fail CASCADE;
DROP TABLE IF EXISTS public.pack_productivity_hour CASCADE;
DROP TABLE IF EXISTS public.pack_productivity_fail_category CASCADE;
DROP TABLE IF EXISTS public.pack_dryer_result CASCADE;
DROP TABLE IF EXISTS public.pack_variety CASCADE;
DROP TABLE IF EXISTS public.pack_session_product_run CASCADE;
DROP TABLE IF EXISTS public.pack_session_product_hour CASCADE;

-- Trigger functions. CASCADE drops any remaining trigger that
-- depends on them, in case a non-pack table referenced one.
DROP FUNCTION IF EXISTS public.pack_session_cases_guard_immutable() CASCADE;
DROP FUNCTION IF EXISTS public.pack_session_fails_guard_immutable() CASCADE;
DROP FUNCTION IF EXISTS public.pack_session_guard_immutable() CASCADE;
DROP FUNCTION IF EXISTS public.pack_session_labor_hour_guard_immutable() CASCADE;
DROP FUNCTION IF EXISTS public.pack_session_leftover_guard_immutable() CASCADE;
DROP FUNCTION IF EXISTS public.pack_session_set_defaults() CASCADE;
DROP FUNCTION IF EXISTS public.pack_shelf_life_cascade_day() CASCADE;
DROP FUNCTION IF EXISTS public.pack_shelf_life_check_termination() CASCADE;
DROP FUNCTION IF EXISTS public.pack_shelf_life_set_day() CASCADE;
DROP FUNCTION IF EXISTS public.pack_lot_default_lot_number(date, date) CASCADE;
DROP FUNCTION IF EXISTS public.pack_session_product_run_ensure_lot() CASCADE;


-- ==================================================================
-- Recreate from canonical state (sourced from dev dump 2026-05-18).
-- ==================================================================

-- check_function_bodies = false so the plpgsql validator doesn't fail
-- when the function body references a pack_* table that hasn't been
-- CREATEd yet in this same migration (pg_dump emits functions first,
-- tables second). Without this, CREATE FUNCTION trips on
-- `relation "public.pack_shelf_life_metric" does not exist`.
SET check_function_bodies = false;

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






COMMENT ON TABLE "public"."pack_shelf_life_result" IS 'Individual observation responses for a shelf life trial. One row per check per observation date per trial.';




COMMENT ON COLUMN "public"."pack_shelf_life_result"."shelf_life_day" IS 'Auto-calculated: observation_date minus pack_lot.pack_date';




COMMENT ON COLUMN "public"."pack_shelf_life_result"."response_boolean" IS 'Used when pack_shelf_life_metric.response_type is boolean';




COMMENT ON COLUMN "public"."pack_shelf_life_result"."response_numeric" IS 'Used when pack_shelf_life_metric.response_type is numeric';




COMMENT ON COLUMN "public"."pack_shelf_life_result"."response_enum" IS 'Used when pack_shelf_life_metric.response_type is enum; value from metric enum_options';




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




ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "uq_pack_session" UNIQUE ("org_id", "farm_id", "pack_date", "sales_product_id", "harvest_date");




ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "uq_pack_session_leftover" UNIQUE ("org_id", "farm_id", "pack_date");




ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "uq_pack_shelf_life_result" UNIQUE ("pack_shelf_life_id", "pack_shelf_life_metric_id", "observation_date");




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
