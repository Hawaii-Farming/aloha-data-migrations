-- Pack restructure step 5/17: pack_session_product_hour → pack_session_cases.
-- Drops both FKs (pack_productivity_hour_id, pack_session_product_run_id) and replaces with
-- inline (pack_date, pack_end_hour, sales_product_id, harvest_date).
--
-- Cukes don't track hourly cadence — pack_end_hour is set to 23:59 for them so uniqueness still works.

ALTER TABLE pack_session_product_hour
    DROP COLUMN pack_productivity_hour_id,
    DROP COLUMN pack_session_product_run_id,
    ADD  COLUMN pack_date        DATE        NOT NULL,
    ADD  COLUMN pack_end_hour    TIMESTAMPTZ NOT NULL,
    ADD  COLUMN sales_product_id TEXT        NOT NULL REFERENCES sales_product(id),
    ADD  COLUMN harvest_date     DATE        NOT NULL;

ALTER TABLE pack_session_product_hour
    DROP CONSTRAINT IF EXISTS uq_pack_session_product_hour;

DROP INDEX IF EXISTS idx_pack_session_product_hour_hour;
DROP INDEX IF EXISTS idx_pack_session_product_hour_run;

ALTER TABLE pack_session_product_hour RENAME TO pack_session_cases;

CREATE INDEX        idx_pack_session_cases_pack_date     ON pack_session_cases (org_id, farm_id, pack_date);
CREATE INDEX        idx_pack_session_cases_pack_end_hour ON pack_session_cases (pack_end_hour);
CREATE INDEX        idx_pack_session_cases_product       ON pack_session_cases (sales_product_id);
CREATE UNIQUE INDEX uq_pack_session_cases                ON pack_session_cases (org_id, farm_id, pack_date, pack_end_hour, sales_product_id, harvest_date);

COMMENT ON TABLE  pack_session_cases                  IS 'Per-product per-hour cases packed. cases_packed is the count for THIS hour, not cumulative. Cukes use pack_end_hour=23:59 since they are day-totals, not hourly.';
COMMENT ON COLUMN pack_session_cases.pack_end_hour   IS 'Clock hour bucket. For cuke products, set to 23:59 of pack_date (uniqueness still holds; no hourly cadence).';
COMMENT ON COLUMN pack_session_cases.harvest_date     IS 'Matches the parent pack_session row''s harvest_date.';
