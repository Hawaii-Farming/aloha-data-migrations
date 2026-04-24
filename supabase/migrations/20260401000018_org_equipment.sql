CREATE TABLE IF NOT EXISTS org_equipment (
    id                      TEXT PRIMARY KEY,
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_name                 TEXT REFERENCES org_farm(name),
    site_id                 TEXT REFERENCES org_site(id),
    type                    TEXT CHECK (type IN ('vehicle', 'tool', 'machine', 'ppe', 'bag_pack_sprayer', 'fogger', 'tank')),
    name                    TEXT NOT NULL,
    code                    TEXT,
    description             TEXT,
    manufacturer            TEXT,
    model                   TEXT,
    serial_number           TEXT,
    purchase_date           DATE,
    manual_url              TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE org_equipment IS 'Equipment register for all physical assets across the organization. Farm-level or shared (farm_name null). Site-level or mobile (site_id null).';

COMMENT ON COLUMN org_equipment.farm_name IS 'Inherited from parent org_farm when equipment is farm-scoped; null for org-wide equipment';
COMMENT ON COLUMN org_equipment.site_id IS 'The site where this equipment is located; null for mobile or org-wide equipment';
COMMENT ON COLUMN org_equipment.type IS 'vehicle, tool, machine, ppe, bag_pack_sprayer, fogger, tank';
