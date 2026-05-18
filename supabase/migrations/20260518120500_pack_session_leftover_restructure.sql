-- Pack restructure step 6/17: pack_session_leftover restructure.
--   - Drop pack_session_id (replaced by pack_date) and pack_variety_id (dropped).
--   - leftover_pounds becomes leftover_lettuce.
--   - Add leftover_watercress, leftover_arugula (3 fixed crop columns).
--   - One row per (org, farm, pack_date).

-- Drop FK to pack_variety first (pack_variety table is being dropped).
ALTER TABLE pack_session_leftover
    DROP CONSTRAINT IF EXISTS pack_session_leftover_variety_fkey;

ALTER TABLE pack_session_leftover
    DROP COLUMN pack_session_id,
    DROP COLUMN pack_variety_id,
    ADD  COLUMN pack_date           DATE    NOT NULL,
    ADD  COLUMN leftover_watercress NUMERIC NOT NULL DEFAULT 0,
    ADD  COLUMN leftover_arugula    NUMERIC NOT NULL DEFAULT 0;

ALTER TABLE pack_session_leftover
    RENAME COLUMN leftover_pounds TO leftover_lettuce;

ALTER TABLE pack_session_leftover
    DROP CONSTRAINT IF EXISTS uq_pack_session_leftover;

ALTER TABLE pack_session_leftover
    ADD CONSTRAINT uq_pack_session_leftover UNIQUE (org_id, farm_id, pack_date);

DROP INDEX IF EXISTS idx_pack_session_leftover_session;
CREATE INDEX idx_pack_session_leftover_pack_date ON pack_session_leftover (pack_date);

COMMENT ON TABLE  pack_session_leftover                     IS 'End-of-day leftover pounds by fixed crop column (lettuce/watercress/arugula). One row per (org, farm, pack_date).';
COMMENT ON COLUMN pack_session_leftover.leftover_lettuce    IS 'Leftover pounds — lettuce.';
COMMENT ON COLUMN pack_session_leftover.leftover_watercress IS 'Leftover pounds — watercress.';
COMMENT ON COLUMN pack_session_leftover.leftover_arugula    IS 'Leftover pounds — arugula.';
