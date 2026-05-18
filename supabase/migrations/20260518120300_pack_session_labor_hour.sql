-- Pack restructure step 4/17: pack_productivity_hour → pack_session_labor_hour.
-- Drops the pack_session FK in favor of inline pack_date.

ALTER TABLE pack_productivity_hour
    DROP COLUMN pack_session_id,
    ADD  COLUMN pack_date DATE NOT NULL;

ALTER TABLE pack_productivity_hour
    DROP CONSTRAINT IF EXISTS uq_pack_productivity_hour_session_hour;

DROP INDEX IF EXISTS idx_pack_productivity_hour_session;
DROP INDEX IF EXISTS idx_pack_productivity_hour_date;
DROP INDEX IF EXISTS uq_pack_productivity_hour_session_hour;

ALTER TABLE pack_productivity_hour RENAME TO pack_session_labor_hour;

CREATE INDEX        idx_pack_session_labor_hour_org_id    ON pack_session_labor_hour (org_id);
CREATE INDEX        idx_pack_session_labor_hour_farm_id   ON pack_session_labor_hour (farm_id);
CREATE INDEX        idx_pack_session_labor_hour_pack_date ON pack_session_labor_hour (pack_date);
CREATE UNIQUE INDEX uq_pack_session_labor_hour            ON pack_session_labor_hour (org_id, farm_id, pack_date, pack_end_hour);

COMMENT ON TABLE  pack_session_labor_hour              IS 'Hourly crew snapshot for a pack day. One row per (org, farm, pack_date, pack_end_hour). Crew counts (catchers/packers/mixers/boxers) and metal-detector flag are session-wide; per-product cases are in pack_session_cases.';
COMMENT ON COLUMN pack_session_labor_hour.pack_date    IS 'Day this hour belongs to (denormalized from pack_session — both are keyed by pack_date).';
COMMENT ON COLUMN pack_session_labor_hour.pack_end_hour IS 'The hour being recorded (e.g. 2026-03-26 11:00); one row per clock hour.';
