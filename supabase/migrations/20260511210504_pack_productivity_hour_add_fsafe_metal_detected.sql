-- pack_productivity_hour: add fsafe_metal_detected boolean
-- =========================================================
-- Captures whether the required food-safety metal-detection process was
-- performed during the hour as a plain yes/no. Lives alongside the
-- existing fsafe_metal_detected_at TIMESTAMPTZ (which records *when*
-- it was done) so the UI can offer a simple checkbox without forcing
-- a time-of-day capture. The CREATE TABLE in
-- 20260401000139_pack_productivity_hour.sql has been edited in place so
-- fresh rebuilds get the column directly; this is the live-DB patch.

ALTER TABLE pack_productivity_hour
    ADD COLUMN IF NOT EXISTS fsafe_metal_detected BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN pack_productivity_hour.fsafe_metal_detected IS
    'True when the required food-safety metal-detection process was performed during this packing hour; false (default) means not yet done. Captured separately from the timestamp so the UI can record a simple yes/no without needing to also stamp a time.';
