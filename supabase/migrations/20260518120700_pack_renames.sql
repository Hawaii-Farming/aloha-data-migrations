-- Pack restructure step 8/17: straight table renames.
--   pack_dryer_result              → pack_moisture
--   pack_productivity_fail_category → pack_fail_category

-- pack_dryer_result → pack_moisture
ALTER TABLE pack_dryer_result RENAME TO pack_moisture;

ALTER INDEX idx_pack_dryer_result_org      RENAME TO idx_pack_moisture_org;
ALTER INDEX idx_pack_dryer_result_farm     RENAME TO idx_pack_moisture_farm;
ALTER INDEX idx_pack_dryer_result_batch    RENAME TO idx_pack_moisture_batch;
ALTER INDEX idx_pack_dryer_result_date     RENAME TO idx_pack_moisture_date;
ALTER INDEX idx_pack_dryer_result_original RENAME TO idx_pack_moisture_original;

-- Self-referencing FK column kept its old name; rename it too for consistency.
ALTER TABLE pack_moisture
    RENAME COLUMN pack_dryer_result_id_original TO pack_moisture_id_original;

ALTER TABLE pack_moisture
    RENAME CONSTRAINT pack_dryer_result_farm_fkey TO pack_moisture_farm_fkey;

COMMENT ON TABLE  pack_moisture                            IS 'Environmental and moisture readings taken during the packing process. One row per check at a specific time, tracking temperature and moisture conditions before and after the dryer.';
COMMENT ON COLUMN pack_moisture.pack_moisture_id_original  IS 'Self-referencing FK to the original check when this row is a re-check.';

-- pack_productivity_fail_category → pack_fail_category
ALTER TABLE pack_productivity_fail_category RENAME TO pack_fail_category;

ALTER INDEX uq_pack_productivity_fail_category_org  RENAME TO uq_pack_fail_category_org;
ALTER INDEX uq_pack_productivity_fail_category_farm RENAME TO uq_pack_fail_category_farm;

ALTER TABLE pack_fail_category
    RENAME CONSTRAINT pack_productivity_fail_category_farm_fkey TO pack_fail_category_farm_fkey;

COMMENT ON TABLE pack_fail_category IS 'Lookup for pack line fail categories (e.g. film, tray, printer, leaves, ridges). Referenced by pack_session_fails.pack_fail_category_id.';

-- Rename policies that carried over with the table rename (preserved by OID).
DO $$
DECLARE
    p RECORD;
    new_name TEXT;
BEGIN
    FOR p IN
        SELECT policyname FROM pg_policies
         WHERE schemaname = 'public'
           AND tablename  = 'pack_moisture'
           AND policyname LIKE 'pack_dryer_result_%'
    LOOP
        new_name := 'pack_moisture_' || substring(p.policyname FROM length('pack_dryer_result_') + 1);
        EXECUTE format('ALTER POLICY %I ON public.pack_moisture RENAME TO %I', p.policyname, new_name);
    END LOOP;

    FOR p IN
        SELECT policyname FROM pg_policies
         WHERE schemaname = 'public'
           AND tablename  = 'pack_fail_category'
           AND policyname LIKE 'pack_productivity_fail_category_%'
    LOOP
        new_name := 'pack_fail_category_' || substring(p.policyname FROM length('pack_productivity_fail_category_') + 1);
        EXECUTE format('ALTER POLICY %I ON public.pack_fail_category RENAME TO %I', p.policyname, new_name);
    END LOOP;
END $$;
