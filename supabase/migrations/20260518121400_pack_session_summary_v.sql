-- Pack restructure step 15/17: recreate pack_session_summary_v against new schema.
--
-- One row per (org, farm, pack_date). Aggregates across all product rows of that pack day.
--   minutes_total = (MAX(stopped_at) - MIN(started_at)) / 60   (across the day's pack_session rows)
--   total_trays   = SUM(cases_packed × sales_product.pack_per_case)
--   total_fails   = SUM(fail_count)::INT                       (only a few per hour)
--   trays_per_min = total_trays / minutes_total

CREATE OR REPLACE VIEW pack_session_summary_v
WITH (security_invoker = true) AS
WITH
day_runs AS (
    SELECT
        s.org_id,
        s.farm_id,
        s.pack_date,
        MIN(s.started_at) AS started_at,
        MAX(s.stopped_at) AS stopped_at
      FROM pack_session s
     WHERE s.is_deleted = false
     GROUP BY s.org_id, s.farm_id, s.pack_date
),
day_cases AS (
    SELECT
        c.org_id,
        c.farm_id,
        c.pack_date,
        COALESCE(SUM(c.cases_packed * COALESCE(sp.pack_per_case, 1)), 0)::INT AS total_trays
      FROM pack_session_cases c
      JOIN sales_product      sp ON sp.id = c.sales_product_id
     WHERE c.is_deleted = false
     GROUP BY c.org_id, c.farm_id, c.pack_date
),
day_fails AS (
    SELECT
        f.org_id,
        f.farm_id,
        f.pack_date,
        COALESCE(SUM(f.fail_count), 0)::INT AS total_fails
      FROM pack_session_fails f
     WHERE f.is_deleted = false
     GROUP BY f.org_id, f.farm_id, f.pack_date
)
SELECT
    r.org_id,
    r.farm_id,
    r.pack_date,
    r.started_at,
    r.stopped_at,
    CASE
        WHEN r.started_at IS NULL
          OR r.stopped_at IS NULL
          OR r.stopped_at = r.started_at THEN NULL
        ELSE EXTRACT(EPOCH FROM (r.stopped_at - r.started_at)) / 60
    END::NUMERIC AS minutes_total,
    COALESCE(c.total_trays, 0) AS total_trays,
    COALESCE(f.total_fails, 0) AS total_fails,
    CASE
        WHEN r.started_at IS NULL
          OR r.stopped_at IS NULL
          OR r.stopped_at = r.started_at THEN NULL
        ELSE COALESCE(c.total_trays, 0)::NUMERIC
             / (EXTRACT(EPOCH FROM (r.stopped_at - r.started_at)) / 60)
    END AS trays_per_min
  FROM day_runs  r
  LEFT JOIN day_cases c USING (org_id, farm_id, pack_date)
  LEFT JOIN day_fails f USING (org_id, farm_id, pack_date);

COMMENT ON VIEW pack_session_summary_v IS 'One row per (org, farm, pack_date) with rollups: minutes_total (max-stop minus min-start across day''s product rows), total_trays (cases × pack_per_case), total_fails, trays_per_min.';

GRANT SELECT ON pack_session_summary_v TO authenticated;
