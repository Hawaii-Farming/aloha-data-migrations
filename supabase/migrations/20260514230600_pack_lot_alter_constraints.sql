-- Old rule: one pack_lot per pack_date (lot_number = YYYYMMDD).
-- New rule: one pack_lot per (farm, pack_date, harvest_date); lot_number = {pack}-{harv} YYYYMMDD-YYYYMMDD.
-- Keep UNIQUE(org_id, lot_number) for traceability lookups.

-- Wipe existing rows since lot_number format changes and harvest_date becomes load-bearing.
TRUNCATE pack_lot CASCADE;

ALTER TABLE pack_lot
    ADD CONSTRAINT uq_pack_lot_dates UNIQUE (org_id, farm_id, pack_date, harvest_date);

COMMENT ON TABLE  pack_lot              IS 'Production lot header. One row per (org, farm, pack_date, harvest_date). lot_number is system-generated as {pack_date}-{harvest_date} (YYYYMMDD-YYYYMMDD), user-editable.';
COMMENT ON COLUMN pack_lot.lot_number   IS 'System-generated as {pack_date YYYYMMDD}-{harvest_date YYYYMMDD}. User-editable.';
COMMENT ON COLUMN pack_lot.harvest_date IS 'Required in practice (drives lot_number); kept nullable for backward compatibility.';
