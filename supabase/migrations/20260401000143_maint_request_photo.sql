CREATE TABLE IF NOT EXISTS maint_request_photo (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                  TEXT NOT NULL REFERENCES org(id),
    farm_id                 TEXT,
    maint_request_id        UUID NOT NULL REFERENCES maint_request(id),
    photo_type              TEXT NOT NULL CHECK (photo_type IN ('Before', 'After')),
    photo_url               TEXT NOT NULL,
    caption                 TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by              TEXT,
    is_deleted              BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT maint_request_photo_farm_fkey FOREIGN KEY (org_id, farm_id) REFERENCES org_farm(org_id, id)
);

COMMENT ON TABLE maint_request_photo IS 'Photos attached to a maintenance request. One row per photo with before/after classification.';

COMMENT ON COLUMN maint_request_photo.photo_type IS 'before, after';

CREATE INDEX idx_maint_request_photo_request ON maint_request_photo (maint_request_id);
