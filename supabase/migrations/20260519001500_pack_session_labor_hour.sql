-- pack_session_labor_hour
-- =======================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

CREATE TABLE IF NOT EXISTS "public"."pack_session_labor_hour" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "pack_date" "date" NOT NULL,
    "pack_end_hour" timestamp with time zone NOT NULL,
    "catchers" integer DEFAULT 0 NOT NULL,
    "packers" integer DEFAULT 0 NOT NULL,
    "mixers" integer DEFAULT 0 NOT NULL,
    "boxers" integer DEFAULT 0 NOT NULL,
    "fsafe_metal_detected" boolean DEFAULT false NOT NULL,
    "fsafe_metal_detected_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


COMMENT ON TABLE "public"."pack_session_labor_hour" IS 'Hourly crew snapshot for a pack day. One row per (org, farm, pack_date, pack_end_hour). Crew counts (catchers/packers/mixers/boxers) and metal-detector flag are session-wide; per-product cases are in pack_session_cases.';


COMMENT ON COLUMN "public"."pack_session_labor_hour"."pack_end_hour" IS 'The hour being recorded (e.g. 2026-03-26 11:00); one row per clock hour.';


COMMENT ON COLUMN "public"."pack_session_labor_hour"."fsafe_metal_detected_at" IS 'Timestamp of food safety metal detection check during this packing hour; null means no detection was recorded';


COMMENT ON COLUMN "public"."pack_session_labor_hour"."fsafe_metal_detected" IS 'True when the required food-safety metal-detection process was performed during this packing hour; false (default) means not yet done. Captured separately from the timestamp so the UI can record a simple yes/no without needing to also stamp a time.';


COMMENT ON COLUMN "public"."pack_session_labor_hour"."pack_date" IS 'Day this hour belongs to (denormalized from pack_session — both are keyed by pack_date).';


ALTER TABLE ONLY "public"."pack_session_labor_hour"
    ADD CONSTRAINT "pack_productivity_hour_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_session_labor_hour_farm_id" ON "public"."pack_session_labor_hour" USING "btree" ("farm_id");


CREATE INDEX "idx_pack_session_labor_hour_org_id" ON "public"."pack_session_labor_hour" USING "btree" ("org_id");


CREATE INDEX "idx_pack_session_labor_hour_pack_date" ON "public"."pack_session_labor_hour" USING "btree" ("pack_date");


CREATE UNIQUE INDEX "uq_pack_session_labor_hour" ON "public"."pack_session_labor_hour" USING "btree" ("org_id", "farm_id", "pack_date", "pack_end_hour");


CREATE OR REPLACE TRIGGER "pack_session_labor_hour_before_update_guard" BEFORE UPDATE ON "public"."pack_session_labor_hour" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_labor_hour_guard_immutable"();


ALTER TABLE ONLY "public"."pack_session_labor_hour"
    ADD CONSTRAINT "pack_productivity_hour_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_session_labor_hour"
    ADD CONSTRAINT "pack_productivity_hour_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE "public"."pack_session_labor_hour" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_labor_hour_delete" ON "public"."pack_session_labor_hour" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_labor_hour_insert" ON "public"."pack_session_labor_hour" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_labor_hour_read" ON "public"."pack_session_labor_hour" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_labor_hour_update" ON "public"."pack_session_labor_hour" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_labor_hour" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_labor_hour" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_labor_hour" TO "service_role";

