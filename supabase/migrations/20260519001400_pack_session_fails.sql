-- pack_session_fails
-- ==================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

CREATE TABLE IF NOT EXISTS "public"."pack_session_fails" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "pack_date" "date" NOT NULL,
    "pack_end_hour" timestamp with time zone NOT NULL,
    "pack_fail_category_id" "text" NOT NULL,
    "fail_count" integer DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


COMMENT ON TABLE "public"."pack_session_fails" IS 'Fail counts per category per hour. One row per (org, farm, pack_date, pack_end_hour, fail_category).';


COMMENT ON COLUMN "public"."pack_session_fails"."pack_fail_category_id" IS 'Fail category (e.g. film, tray, printer, leaves, ridges) — references pack_fail_category (renamed from pack_productivity_fail_category in step 8).';


COMMENT ON COLUMN "public"."pack_session_fails"."fail_count" IS 'Number of fails for this category in this hour';


ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_session_fails_category" ON "public"."pack_session_fails" USING "btree" ("pack_fail_category_id");


CREATE INDEX "idx_pack_session_fails_pack_date" ON "public"."pack_session_fails" USING "btree" ("org_id", "farm_id", "pack_date");


CREATE INDEX "idx_pack_session_fails_pack_end_hour" ON "public"."pack_session_fails" USING "btree" ("pack_end_hour");


CREATE UNIQUE INDEX "uq_pack_session_fails" ON "public"."pack_session_fails" USING "btree" ("org_id", "farm_id", "pack_date", "pack_end_hour", "pack_fail_category_id");


CREATE OR REPLACE TRIGGER "pack_session_fails_before_update_guard" BEFORE UPDATE ON "public"."pack_session_fails" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_fails_guard_immutable"();


ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE ONLY "public"."pack_session_fails"
    ADD CONSTRAINT "pack_productivity_hour_fail_pack_productivity_fail_categor_fkey" FOREIGN KEY ("pack_fail_category_id") REFERENCES "public"."pack_fail_category"("id");


ALTER TABLE "public"."pack_session_fails" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_fails_delete" ON "public"."pack_session_fails" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_fails_insert" ON "public"."pack_session_fails" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_fails_read" ON "public"."pack_session_fails" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_fails_update" ON "public"."pack_session_fails" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_fails" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_fails" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_fails" TO "service_role";

