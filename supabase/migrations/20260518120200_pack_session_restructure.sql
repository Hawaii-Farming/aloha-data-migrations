-- Pack restructure step 3/17:
--   - Drop the OLD pack_session (pack-day header). The name is being reused.
--   - Restructure pack_session_product_run to absorb pack_date/best_by_date/pack_lot inline
--     (replacing the pack_session_id and pack_lot_id FKs).
--   - Rename pack_session_product_run → pack_session.
--
-- Natural key for the new pack_session: (org_id, farm_id, pack_date, sales_product_id, harvest_date).

-- Drop the original pack-day header (now redundant — pack_date is the natural day-link key).
DROP TABLE IF EXISTS pack_session CASCADE;

-- Restructure pack_session_product_run.
ALTER TABLE pack_session_product_run
    DROP COLUMN pack_session_id,
    DROP COLUMN pack_lot_id,
    ADD  COLUMN pack_date    DATE NOT NULL,
    ADD  COLUMN best_by_date DATE,
    ADD  COLUMN pack_lot     TEXT;

-- Old uniqueness was per (pack_session_id, sales_product_id, harvest_date) — pack_session_id
-- is gone; the equivalent key is pack_date scoped to org/farm.
ALTER TABLE pack_session_product_run
    DROP CONSTRAINT IF EXISTS uq_pack_session_product_run;

ALTER TABLE pack_session_product_run
    ADD CONSTRAINT uq_pack_session
        UNIQUE (org_id, farm_id, pack_date, sales_product_id, harvest_date);

-- started_at was NOT NULL in pack_session_product_run; new pack_session should allow rows
-- with no started_at (historical backfill from pack_lot has no run-start timestamp).
ALTER TABLE pack_session_product_run
    ALTER COLUMN started_at DROP NOT NULL;

-- Rename.
ALTER TABLE pack_session_product_run RENAME TO pack_session;

-- Drop obsolete indexes; recreate against the new column set.
DROP INDEX IF EXISTS idx_pack_session_product_run_session;
DROP INDEX IF EXISTS idx_pack_session_product_run_lot;
DROP INDEX IF EXISTS idx_pack_session_product_run_product;

CREATE INDEX idx_pack_session_org_id    ON pack_session (org_id);
CREATE INDEX idx_pack_session_farm_id   ON pack_session (farm_id);
CREATE INDEX idx_pack_session_pack_date ON pack_session (pack_date);
CREATE INDEX idx_pack_session_product   ON pack_session (sales_product_id);

COMMENT ON TABLE  pack_session              IS 'Pack session: one row per (org, farm, pack_date, sales_product_id, harvest_date). Absorbs the prior pack_session_product_run + pack_lot rollup.';
COMMENT ON COLUMN pack_session.pack_date    IS 'Day this product was packed. Editable; user can backdate to log prior days.';
COMMENT ON COLUMN pack_session.pack_lot     IS 'Lot number TEXT (formerly pack_lot.lot_number). Auto-generated on insert as {pack_date}-{harvest_date} YYYYMMDD-YYYYMMDD by trigger; user-editable.';
COMMENT ON COLUMN pack_session.best_by_date IS 'Auto-set on insert as harvest_date + sales_product.shelf_life_days.';
COMMENT ON COLUMN pack_session.started_at   IS 'Set when packing starts. Nullable for historical backfill where no run was recorded.';
COMMENT ON COLUMN pack_session.stopped_at   IS 'Set-once when packing stops.';
