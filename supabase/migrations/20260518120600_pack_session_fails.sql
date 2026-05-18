-- Pack restructure step 7/17: pack_productivity_hour_fail → pack_session_fails.
--   - Drop pack_productivity_hour_id FK; replace with inline (pack_date, pack_end_hour).
--   - Rename pack_productivity_fail_category_id → pack_fail_category_id (FK target renamed in step 8).

ALTER TABLE pack_productivity_hour_fail
    DROP COLUMN pack_productivity_hour_id,
    ADD  COLUMN pack_date     DATE        NOT NULL,
    ADD  COLUMN pack_end_hour TIMESTAMPTZ NOT NULL;

ALTER TABLE pack_productivity_hour_fail
    RENAME COLUMN pack_productivity_fail_category_id TO pack_fail_category_id;

ALTER TABLE pack_productivity_hour_fail
    DROP CONSTRAINT IF EXISTS uq_pack_prod_hour_fail;

DROP INDEX IF EXISTS idx_pack_prod_hour_fail_hour;
DROP INDEX IF EXISTS uq_pack_prod_hour_fail;

ALTER TABLE pack_productivity_hour_fail RENAME TO pack_session_fails;

CREATE INDEX        idx_pack_session_fails_pack_date     ON pack_session_fails (org_id, farm_id, pack_date);
CREATE INDEX        idx_pack_session_fails_pack_end_hour ON pack_session_fails (pack_end_hour);
CREATE INDEX        idx_pack_session_fails_category      ON pack_session_fails (pack_fail_category_id);
CREATE UNIQUE INDEX uq_pack_session_fails                ON pack_session_fails (org_id, farm_id, pack_date, pack_end_hour, pack_fail_category_id);

COMMENT ON TABLE  pack_session_fails                       IS 'Fail counts per category per hour. One row per (org, farm, pack_date, pack_end_hour, fail_category).';
COMMENT ON COLUMN pack_session_fails.pack_fail_category_id IS 'Fail category (e.g. film, tray, printer, leaves, ridges) — references pack_fail_category (renamed from pack_productivity_fail_category in step 8).';
