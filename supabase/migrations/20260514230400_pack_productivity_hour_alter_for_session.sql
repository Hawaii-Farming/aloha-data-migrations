-- Pure cutover: re-anchor pack_productivity_hour from ops_task_tracker → pack_session.
-- Drops cases_packed (now per-product in pack_session_product_hour) and leftover_pounds (now in pack_session_leftover).
-- Existing rows are wiped — semantics changed and no value in retaining single-product session data.

TRUNCATE pack_productivity_hour CASCADE;

DROP INDEX IF EXISTS idx_pack_productivity_hour_tracker;
DROP INDEX IF EXISTS uq_pack_productivity_hour;

ALTER TABLE pack_productivity_hour
    DROP COLUMN ops_task_tracker_id,
    DROP COLUMN cases_packed,
    DROP COLUMN leftover_pounds,
    ADD  COLUMN pack_session_id UUID NOT NULL REFERENCES pack_session(id) ON DELETE CASCADE;

CREATE INDEX        idx_pack_productivity_hour_session       ON pack_productivity_hour (pack_session_id);
CREATE UNIQUE INDEX uq_pack_productivity_hour_session_hour   ON pack_productivity_hour (pack_session_id, pack_end_hour);

COMMENT ON TABLE pack_productivity_hour IS 'Hourly crew snapshot for a pack session. One row per session per clock hour. Crew counts (catchers/packers/mixers/boxers) and metal-detector flag are session-wide; per-product cases-packed are tracked in pack_session_product_hour.';
COMMENT ON COLUMN pack_productivity_hour.pack_session_id IS 'Owning session. CASCADE delete with the session.';
