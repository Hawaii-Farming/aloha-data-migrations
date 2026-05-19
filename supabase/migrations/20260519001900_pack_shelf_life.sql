-- pack_shelf_life
-- ===============
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

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


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_pack_shelf_life_org_id" ON "public"."pack_shelf_life" USING "btree" ("org_id");


CREATE INDEX "idx_pack_shelf_life_pack_session" ON "public"."pack_shelf_life" USING "btree" ("pack_session_id");


CREATE INDEX "idx_pack_shelf_life_product" ON "public"."pack_shelf_life" USING "btree" ("sales_product_id");


CREATE OR REPLACE TRIGGER "trg_pack_shelf_life_cascade_day" AFTER UPDATE OF "pack_session_id" ON "public"."pack_shelf_life" FOR EACH ROW EXECUTE FUNCTION "public"."pack_shelf_life_cascade_day"();


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_invnt_item_id_fkey" FOREIGN KEY ("invnt_item_id") REFERENCES "public"."invnt_item"("id");


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_pack_session_id_fkey" FOREIGN KEY ("pack_session_id") REFERENCES "public"."pack_session"("id");


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_sales_product_id_fkey" FOREIGN KEY ("sales_product_id") REFERENCES "public"."sales_product"("id");


ALTER TABLE ONLY "public"."pack_shelf_life"
    ADD CONSTRAINT "pack_shelf_life_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."org_site"("id");


ALTER TABLE "public"."pack_shelf_life" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_shelf_life_delete" ON "public"."pack_shelf_life" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_insert" ON "public"."pack_shelf_life" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_read" ON "public"."pack_shelf_life" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_shelf_life_update" ON "public"."pack_shelf_life" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_shelf_life" TO "service_role";

