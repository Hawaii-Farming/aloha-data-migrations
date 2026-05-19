-- pack_shelf_life_result
-- ======================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

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


ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_pkey" PRIMARY KEY ("id");


ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "uq_pack_shelf_life_result" UNIQUE ("pack_shelf_life_id", "pack_shelf_life_metric_id", "observation_date");


CREATE INDEX "idx_pack_shelf_life_result_check" ON "public"."pack_shelf_life_result" USING "btree" ("pack_shelf_life_metric_id");


CREATE INDEX "idx_pack_shelf_life_result_org_id" ON "public"."pack_shelf_life_result" USING "btree" ("org_id");


CREATE INDEX "idx_pack_shelf_life_result_trial" ON "public"."pack_shelf_life_result" USING "btree" ("pack_shelf_life_id");


CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_check_termination" AFTER INSERT OR UPDATE ON "public"."pack_shelf_life_result" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_check_termination"();


CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_result_set_day" BEFORE INSERT OR UPDATE OF "observation_date", "pack_shelf_life_id" ON "public"."pack_shelf_life_result" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_set_day"();


ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_pack_shelf_life_id_fkey" FOREIGN KEY ("pack_shelf_life_id") REFERENCES "public"."pack_shelf_life"("id");


ALTER TABLE ONLY "public"."pack_shelf_life_result"
    ADD CONSTRAINT "pack_shelf_life_result_pack_shelf_life_metric_id_fkey" FOREIGN KEY ("pack_shelf_life_metric_id") REFERENCES "public"."pack_shelf_life_metric"("id");


ALTER TABLE "public"."pack_shelf_life_result" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_result_delete" ON "public"."pack_shelf_life_result" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_result_insert" ON "public"."pack_shelf_life_result" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_result_read" ON "public"."pack_shelf_life_result" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_result_update" ON "public"."pack_shelf_life_result" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_result" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_result" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life_result" TO "service_role";

