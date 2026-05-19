-- pack_shelf_life_metric
-- ======================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

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


ALTER TABLE ONLY "public"."pack_shelf_life_metric"
    ADD CONSTRAINT "pack_shelf_life_metric_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_shelf_life_metric_org_id" ON "public"."pack_shelf_life_metric" USING "btree" ("org_id");


CREATE UNIQUE INDEX "uq_pack_shelf_life_metric_farm_level" ON "public"."pack_shelf_life_metric" USING "btree" ("org_id", "farm_id", "id") WHERE ("farm_id" IS NOT NULL);


CREATE UNIQUE INDEX "uq_pack_shelf_life_metric_org_level" ON "public"."pack_shelf_life_metric" USING "btree" ("org_id", "id") WHERE ("farm_id" IS NULL);


ALTER TABLE ONLY "public"."pack_shelf_life_metric"
    ADD CONSTRAINT "pack_shelf_life_metric_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_shelf_life_metric"
    ADD CONSTRAINT "pack_shelf_life_metric_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE "public"."pack_shelf_life_metric" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_metric_read" ON "public"."pack_shelf_life_metric" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_metric" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_metric" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_metric" TO "service_role";

