-- pack_moisture
-- =============
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

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


ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_dryer_result_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_moisture_batch" ON "public"."pack_moisture" USING "btree" ("grow_lettuce_seed_batch_id");


CREATE INDEX "idx_pack_moisture_date" ON "public"."pack_moisture" USING "btree" ("check_at");


CREATE INDEX "idx_pack_moisture_farm" ON "public"."pack_moisture" USING "btree" ("farm_id");


CREATE INDEX "idx_pack_moisture_org" ON "public"."pack_moisture" USING "btree" ("org_id");


CREATE INDEX "idx_pack_moisture_original" ON "public"."pack_moisture" USING "btree" ("pack_moisture_id_original");


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


ALTER TABLE ONLY "public"."pack_moisture"
    ADD CONSTRAINT "pack_moisture_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE "public"."pack_moisture" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_moisture_delete" ON "public"."pack_moisture" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_moisture_insert" ON "public"."pack_moisture" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_moisture_read" ON "public"."pack_moisture" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_moisture_update" ON "public"."pack_moisture" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_moisture" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_moisture" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_moisture" TO "service_role";

