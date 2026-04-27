CREATE TABLE IF NOT EXISTS org_site_housing (
    id            TEXT PRIMARY KEY,
    org_id        TEXT NOT NULL REFERENCES org(id),
    maximum_beds  INTEGER,
    address       TEXT,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    TEXT,
    is_deleted    BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE org_site_housing IS 'Housing facility registry — one row per residence owned or managed by the organization. Org-scoped (no farm linkage). Standalone: id is the display name (e.g. "BIP (5)", "South Kohala") and is not FK-linked to org_site.';

COMMENT ON COLUMN org_site_housing.maximum_beds IS 'Total bed capacity of this facility. Informational';
COMMENT ON COLUMN org_site_housing.address IS 'Street address; used for HR mailings and pay stubs';

CREATE INDEX idx_org_site_housing_org ON org_site_housing (org_id);
