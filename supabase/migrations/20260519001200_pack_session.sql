-- pack_session
-- ============
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

CREATE TABLE IF NOT EXISTS "public"."pack_session" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "sales_product_id" "text" NOT NULL,
    "pack_date" "date" NOT NULL,
    "harvest_date" "date" NOT NULL,
    "best_by_date" "date",
    "pack_lot" "text" NOT NULL,
    "started_at" timestamp with time zone,
    "stopped_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


COMMENT ON TABLE "public"."pack_session" IS 'Pack session: one row per (org, farm, pack_date, sales_product_id, harvest_date). Absorbs the prior pack_session_product_run + pack_lot rollup.';


COMMENT ON COLUMN "public"."pack_session"."started_at" IS 'Set when packing starts. Nullable for historical backfill where no run was recorded.';


COMMENT ON COLUMN "public"."pack_session"."stopped_at" IS 'Set-once when packing stops.';


COMMENT ON COLUMN "public"."pack_session"."pack_date" IS 'Day this product was packed. Editable; user can backdate to log prior days.';


COMMENT ON COLUMN "public"."pack_session"."best_by_date" IS 'Auto-set on insert as harvest_date + sales_product.shelf_life_days.';


COMMENT ON COLUMN "public"."pack_session"."pack_lot" IS 'Lot number TEXT (formerly pack_lot.lot_number). Auto-generated on INSERT as {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD; user-editable. NOT NULL — every session row has a lot identifier for FSMA traceability.';


ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_pkey" PRIMARY KEY ("id");


ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "uq_pack_session" UNIQUE ("org_id", "farm_id", "pack_date", "sales_product_id", "harvest_date");


CREATE INDEX "idx_pack_session_farm_id" ON "public"."pack_session" USING "btree" ("farm_id");


CREATE INDEX "idx_pack_session_org_id" ON "public"."pack_session" USING "btree" ("org_id");


CREATE INDEX "idx_pack_session_pack_date" ON "public"."pack_session" USING "btree" ("pack_date");


CREATE INDEX "idx_pack_session_product" ON "public"."pack_session" USING "btree" ("sales_product_id");


CREATE OR REPLACE TRIGGER "pack_session_before_insert_defaults" BEFORE INSERT ON "public"."pack_session" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_set_defaults"();


CREATE OR REPLACE TRIGGER "pack_session_before_update_guard" BEFORE UPDATE ON "public"."pack_session" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_guard_immutable"();


ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE ONLY "public"."pack_session"
    ADD CONSTRAINT "pack_session_product_run_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");


ALTER TABLE "public"."pack_session" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_delete" ON "public"."pack_session" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_insert" ON "public"."pack_session" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_read" ON "public"."pack_session" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_update" ON "public"."pack_session" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session" TO "service_role";

