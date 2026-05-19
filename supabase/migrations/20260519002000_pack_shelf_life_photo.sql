-- pack_shelf_life_photo
-- =====================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

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


ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_shelf_life_photo_org_id" ON "public"."pack_shelf_life_photo" USING "btree" ("org_id");


CREATE INDEX "idx_pack_shelf_life_photo_trial" ON "public"."pack_shelf_life_photo" USING "btree" ("pack_shelf_life_id");


CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_photo_set_day" BEFORE INSERT OR UPDATE OF "observation_date", "pack_shelf_life_id" ON "public"."pack_shelf_life_photo" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_set_day"();


ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE ONLY "public"."pack_shelf_life_photo"
    ADD CONSTRAINT "pack_shelf_life_photo_pack_shelf_life_id_fkey" FOREIGN KEY ("pack_shelf_life_id") REFERENCES "public"."pack_shelf_life"("id");


ALTER TABLE "public"."pack_shelf_life_photo" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_photo_delete" ON "public"."pack_shelf_life_photo" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_photo_insert" ON "public"."pack_shelf_life_photo" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_photo_read" ON "public"."pack_shelf_life_photo" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_photo_update" ON "public"."pack_shelf_life_photo" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_photo" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_photo" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_photo" TO "service_role";

