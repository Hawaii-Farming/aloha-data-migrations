-- pack_fail_category
-- ==================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

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


ALTER TABLE ONLY "public"."pack_fail_category"
    ADD CONSTRAINT "pack_productivity_fail_category_pkey" PRIMARY KEY ("id");


CREATE UNIQUE INDEX "uq_pack_fail_category_farm" ON "public"."pack_fail_category" USING "btree" ("org_id", "farm_id", "id") WHERE ("farm_id" IS NOT NULL);


CREATE UNIQUE INDEX "uq_pack_fail_category_org" ON "public"."pack_fail_category" USING "btree" ("org_id", "id") WHERE ("farm_id" IS NULL);


ALTER TABLE ONLY "public"."pack_fail_category"
    ADD CONSTRAINT "pack_fail_category_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_fail_category"
    ADD CONSTRAINT "pack_productivity_fail_category_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE "public"."pack_fail_category" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_fail_category_read" ON "public"."pack_fail_category" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_fail_category" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_fail_category" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_fail_category" TO "service_role";

