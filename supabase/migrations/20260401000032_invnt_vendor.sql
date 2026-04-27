CREATE TABLE IF NOT EXISTS invnt_vendor (
    id           TEXT PRIMARY KEY,
    org_id         TEXT NOT NULL REFERENCES org(id),
    contact_person TEXT,
    email          TEXT,
    phone          TEXT,
    address        TEXT,
    payment_terms  TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by     TEXT,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by     TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_invnt_vendor UNIQUE (org_id, id)
);

COMMENT ON TABLE invnt_vendor IS 'Organization-level suppliers used for procurement across all farms. Stores contact details, address, and payment terms.';

