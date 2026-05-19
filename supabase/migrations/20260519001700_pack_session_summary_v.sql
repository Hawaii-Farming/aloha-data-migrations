-- pack_session_summary_v
-- ======================
-- Sourced from the live dev schema on 2026-05-19. Split out of
-- the prior 20260518230000_pack_module_consolidated.sql so each
-- pack object lives in its own migration file again.

CREATE OR REPLACE VIEW "public"."pack_session_summary_v" WITH ("security_invoker"='true') AS
 WITH "day_runs" AS (
         SELECT "s"."org_id",
            "s"."farm_id",
            "s"."pack_date",
            "min"("s"."started_at") AS "started_at",
            "max"("s"."stopped_at") AS "stopped_at"
           FROM "public"."pack_session" "s"
          WHERE ("s"."is_deleted" = false)
          GROUP BY "s"."org_id", "s"."farm_id", "s"."pack_date"
        ), "day_cases" AS (
         SELECT "c_1"."org_id",
            "c_1"."farm_id",
            "c_1"."pack_date",
            (COALESCE("sum"((("c_1"."cases_packed")::numeric * COALESCE("sp"."pack_per_case", (1)::numeric))), (0)::numeric))::integer AS "total_trays"
           FROM ("public"."pack_session_cases" "c_1"
             JOIN "public"."sales_product" "sp" ON (("sp"."id" = "c_1"."sales_product_id")))
          WHERE ("c_1"."is_deleted" = false)
          GROUP BY "c_1"."org_id", "c_1"."farm_id", "c_1"."pack_date"
        ), "day_fails" AS (
         SELECT "f_1"."org_id",
            "f_1"."farm_id",
            "f_1"."pack_date",
            (COALESCE("sum"("f_1"."fail_count"), (0)::bigint))::integer AS "total_fails"
           FROM "public"."pack_session_fails" "f_1"
          WHERE ("f_1"."is_deleted" = false)
          GROUP BY "f_1"."org_id", "f_1"."farm_id", "f_1"."pack_date"
        )
 SELECT "r"."org_id",
    "r"."farm_id",
    "r"."pack_date",
    "r"."started_at",
    "r"."stopped_at",
        CASE
            WHEN (("r"."started_at" IS NULL) OR ("r"."stopped_at" IS NULL) OR ("r"."stopped_at" = "r"."started_at")) THEN NULL::numeric
            ELSE (EXTRACT(epoch FROM ("r"."stopped_at" - "r"."started_at")) / (60)::numeric)
        END AS "minutes_total",
    COALESCE("c"."total_trays", 0) AS "total_trays",
    COALESCE("f"."total_fails", 0) AS "total_fails",
        CASE
            WHEN (("r"."started_at" IS NULL) OR ("r"."stopped_at" IS NULL) OR ("r"."stopped_at" = "r"."started_at")) THEN NULL::numeric
            ELSE ((COALESCE("c"."total_trays", 0))::numeric / (EXTRACT(epoch FROM ("r"."stopped_at" - "r"."started_at")) / (60)::numeric))
        END AS "trays_per_min"
   FROM (("day_runs" "r"
     LEFT JOIN "day_cases" "c" USING ("org_id", "farm_id", "pack_date"))
     LEFT JOIN "day_fails" "f" USING ("org_id", "farm_id", "pack_date"));


COMMENT ON VIEW "public"."pack_session_summary_v" IS 'One row per (org, farm, pack_date) with rollups: minutes_total (max-stop minus min-start across day''s product rows), total_trays (cases × pack_per_case), total_fails, trays_per_min.';


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_summary_v" TO "anon";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_summary_v" TO "authenticated";


GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "public"."pack_session_summary_v" TO "service_role";

