-- pack_session_cases
-- ==================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

CREATE TABLE IF NOT EXISTS "public"."pack_session_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "pack_date" "date" NOT NULL,
    "harvest_date" "date" NOT NULL,
    "pack_end_hour" timestamp with time zone NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "cases_packed" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


COMMENT ON TABLE "public"."pack_session_cases" IS 'Per-product per-hour cases packed. cases_packed is the count for THIS hour, not cumulative. Cukes use pack_end_hour=23:59 since they are day-totals, not hourly.';


COMMENT ON COLUMN "public"."pack_session_cases"."pack_end_hour" IS 'Clock hour bucket. For cuke products, set to 23:59 of pack_date (uniqueness still holds; no hourly cadence).';


COMMENT ON COLUMN "public"."pack_session_cases"."harvest_date" IS 'Matches the parent pack_session row''s harvest_date.';


ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_session_cases_pack_date" ON "public"."pack_session_cases" USING "btree" ("org_id", "farm_id", "pack_date");


CREATE INDEX "idx_pack_session_cases_pack_end_hour" ON "public"."pack_session_cases" USING "btree" ("pack_end_hour");


CREATE INDEX "idx_pack_session_cases_product" ON "public"."pack_session_cases" USING "btree" ("sales_product_id");


CREATE UNIQUE INDEX "uq_pack_session_cases" ON "public"."pack_session_cases" USING "btree" ("org_id", "farm_id", "pack_date", "pack_end_hour", "sales_product_id", "harvest_date");


CREATE OR REPLACE TRIGGER "pack_session_cases_before_update_guard" BEFORE UPDATE ON "public"."pack_session_cases" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_cases_guard_immutable"();


ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE ONLY "public"."pack_session_cases"
    ADD CONSTRAINT "pack_session_product_hour_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");


ALTER TABLE "public"."pack_session_cases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_cases_delete" ON "public"."pack_session_cases" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_cases_insert" ON "public"."pack_session_cases" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_cases_read" ON "public"."pack_session_cases" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_cases_update" ON "public"."pack_session_cases" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_cases" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_cases" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_cases" TO "service_role";

