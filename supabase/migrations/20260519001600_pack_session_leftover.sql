-- pack_session_leftover
-- =====================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

CREATE TABLE IF NOT EXISTS "public"."pack_session_leftover" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "text" NOT NULL,
    "farm_id" "text" NOT NULL,
    "pack_date" "date" NOT NULL,
    "leftover_lettuce" numeric DEFAULT 0 NOT NULL,
    "leftover_watercress" numeric DEFAULT 0 NOT NULL,
    "leftover_arugula" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "text",
    "is_deleted" boolean DEFAULT false NOT NULL
);


COMMENT ON TABLE "public"."pack_session_leftover" IS 'End-of-day leftover pounds by fixed crop column (lettuce/watercress/arugula). One row per (org, farm, pack_date).';


COMMENT ON COLUMN "public"."pack_session_leftover"."leftover_lettuce" IS 'Leftover pounds — lettuce.';


COMMENT ON COLUMN "public"."pack_session_leftover"."leftover_watercress" IS 'Leftover pounds — watercress.';


COMMENT ON COLUMN "public"."pack_session_leftover"."leftover_arugula" IS 'Leftover pounds — arugula.';


ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "pack_session_leftover_pkey" PRIMARY KEY ("id");


ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "uq_pack_session_leftover" UNIQUE ("org_id", "farm_id", "pack_date");


CREATE INDEX "idx_pack_session_leftover_pack_date" ON "public"."pack_session_leftover" USING "btree" ("pack_date");


CREATE OR REPLACE TRIGGER "pack_session_leftover_before_update_guard" BEFORE UPDATE ON "public"."pack_session_leftover" FOR EACH ROW EXECUTE FUNCTION "public"."pack_session_leftover_guard_immutable"();


ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "pack_session_leftover_farm_fkey" FOREIGN KEY ("org_id", "farm_id") REFERENCES "public"."org_farm"("org_id", "id");


ALTER TABLE ONLY "public"."pack_session_leftover"
    ADD CONSTRAINT "pack_session_leftover_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."org"("id");


ALTER TABLE "public"."pack_session_leftover" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pack_session_leftover_delete" ON "public"."pack_session_leftover" FOR DELETE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_leftover_insert" ON "public"."pack_session_leftover" FOR INSERT TO "authenticated" WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_leftover_read" ON "public"."pack_session_leftover" FOR SELECT TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


CREATE POLICY "pack_session_leftover_update" ON "public"."pack_session_leftover" FOR UPDATE TO "authenticated" USING (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids"))) WITH CHECK (("org_id" IN ( SELECT "public"."get_user_org_ids"() AS "get_user_org_ids")));


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_leftover" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_leftover" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_leftover" TO "service_role";

