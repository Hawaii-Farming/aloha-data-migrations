-- Reporting views over pack_session.
--   pack_session_summary_v          one row per session: hour count, run count, total cases, total fails
--   pack_session_product_run_summary_v   one row per product run: lot_number, best_by, total cases

CREATE OR REPLACE VIEW pack_session_summary_v AS
SELECT
    s.id                                AS pack_session_id,
    s.org_id,
    s.farm_id,
    s.site_id,
    s.pack_date,
    s.started_at,
    s.stopped_at,
    s.is_completed,
    COUNT(DISTINCT h.id)                AS hour_count,
    COUNT(DISTINCT r.id)                AS product_run_count,
    COALESCE(SUM(ph.cases_packed), 0)   AS total_cases_packed,
    COALESCE(SUM(f.fail_count), 0)      AS total_fails
  FROM pack_session s
  LEFT JOIN pack_productivity_hour      h  ON h.pack_session_id            = s.id AND h.is_deleted  = false
  LEFT JOIN pack_session_product_run    r  ON r.pack_session_id            = s.id AND r.is_deleted  = false
  LEFT JOIN pack_session_product_hour   ph ON ph.pack_productivity_hour_id = h.id AND ph.is_deleted = false
  LEFT JOIN pack_productivity_hour_fail f  ON f.pack_productivity_hour_id  = h.id AND f.is_deleted  = false
 WHERE s.is_deleted = false
 GROUP BY s.id, s.org_id, s.farm_id, s.site_id, s.pack_date, s.started_at, s.stopped_at, s.is_completed;

COMMENT ON VIEW pack_session_summary_v IS 'One row per pack session with rollups: hour count, product run count, total cases packed, total fails.';


CREATE OR REPLACE VIEW pack_session_product_run_summary_v AS
SELECT
    r.id                                                AS pack_session_product_run_id,
    r.org_id,
    r.farm_id,
    r.pack_session_id,
    r.sales_product_id,
    r.pack_lot_id,
    r.harvest_date,
    r.started_at,
    r.stopped_at,
    pl.lot_number,
    (r.harvest_date + COALESCE(sp.shelf_life_days, 0)) AS best_by_date,
    COALESCE(SUM(ph.cases_packed), 0)                  AS total_cases_packed
  FROM pack_session_product_run r
  LEFT JOIN pack_lot                  pl ON pl.id = r.pack_lot_id
  LEFT JOIN sales_product             sp ON sp.id = r.sales_product_id
  LEFT JOIN pack_session_product_hour ph ON ph.pack_session_product_run_id = r.id AND ph.is_deleted = false
 WHERE r.is_deleted = false
 GROUP BY r.id, r.org_id, r.farm_id, r.pack_session_id, r.sales_product_id, r.pack_lot_id,
          r.harvest_date, r.started_at, r.stopped_at, pl.lot_number, sp.shelf_life_days;

COMMENT ON VIEW pack_session_product_run_summary_v IS 'One row per product run with lot_number, best_by_date, and total cases packed.';
