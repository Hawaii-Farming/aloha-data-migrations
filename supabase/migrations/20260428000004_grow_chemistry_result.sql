-- grow_chemistry_result
-- =====================
-- One row per (sample_date, site, nutrient) reading from the external
-- chemistry lab. Long-format on purpose — new nutrients can appear
-- without a schema change.
--
-- Source: external lab spreadsheet, synced nightly via
-- gsheets/migrations/20260401000034_grow_chemistry.py.
-- The sheet is treated as the source of truth: nightly job
-- truncates org-scoped rows and reinserts.
--
-- site_id and nutrient are kept as plain TEXT (not FKs) because
-- the lab uses its own naming (P1..P7, Water) and we don't want a
-- new pond / nutrient code to break the nightly load. The column
-- is named site_id per scoping-column convention; if we later want
-- strict referential integrity we can add the FK.

CREATE TABLE IF NOT EXISTS grow_chemistry_result (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id       TEXT NOT NULL REFERENCES org(id),
    farm_id      TEXT REFERENCES org_farm(id),
    site_id      TEXT NOT NULL,
    sample_date  DATE NOT NULL,
    nutrient     TEXT NOT NULL,
    result       NUMERIC NOT NULL,
    notes        TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by   TEXT,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   TEXT,
    is_deleted   BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_chemistry_result IS 'External-lab chemistry readings for ponds and water sources. One row per (sample_date, site_id, nutrient). Loaded nightly from the lab spreadsheet.';

COMMENT ON COLUMN grow_chemistry_result.site_id     IS 'Sample location label as written by the lab (e.g. P1..P7 for lettuce ponds, Water for the incoming water source). Free text; not FK-bound to org_site today.';
COMMENT ON COLUMN grow_chemistry_result.nutrient    IS 'Nutrient or parameter code from the lab (e.g. Ca, Mg, NO3, EC, pH). Free text; not FK-bound.';
COMMENT ON COLUMN grow_chemistry_result.result      IS 'Numeric reading. Units depend on nutrient (ppm for most ions, dS/m for EC, unitless for pH).';
COMMENT ON COLUMN grow_chemistry_result.sample_date IS 'Date the lab drew the sample (not the date the result was returned).';

CREATE INDEX idx_grow_chemistry_result_org_date ON grow_chemistry_result (org_id, sample_date);
CREATE INDEX idx_grow_chemistry_result_site     ON grow_chemistry_result (site_id);
CREATE INDEX idx_grow_chemistry_result_nutrient ON grow_chemistry_result (nutrient);

-- ============================================================
-- RLS — org-scoped read for authenticated users.
-- Mirrors the central convention from sys_rls_policies.sql.
-- ============================================================

ALTER TABLE grow_chemistry_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_chemistry_result_read" ON grow_chemistry_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON grow_chemistry_result TO authenticated;
