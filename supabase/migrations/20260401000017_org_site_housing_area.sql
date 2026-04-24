CREATE TABLE IF NOT EXISTS org_site_housing_area (
    org_id        TEXT NOT NULL REFERENCES org(id),
    housing_name    TEXT NOT NULL REFERENCES org_site_housing(name),
    name          TEXT PRIMARY KEY,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    TEXT,
    is_deleted    BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE org_site_housing_area IS 'Sub-areas within a housing facility (rooms, wings, floors). One row per nameable partition of a housing facility.';

COMMENT ON COLUMN org_site_housing_area.housing_name IS 'The housing facility this area belongs to';
COMMENT ON COLUMN org_site_housing_area.name IS 'Display label for the area (e.g. "Room 2A", "East Wing", "Upstairs"). Unique within a housing facility';

CREATE INDEX idx_org_site_housing_area_housing ON org_site_housing_area (housing_name);
CREATE INDEX idx_org_site_housing_area_org ON org_site_housing_area (org_id);
