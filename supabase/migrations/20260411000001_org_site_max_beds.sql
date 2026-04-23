ALTER TABLE org_site ADD COLUMN IF NOT EXISTS max_beds INTEGER;
COMMENT ON COLUMN org_site.max_beds IS 'Maximum bed capacity for housing sites; NULL for non-housing sites';
