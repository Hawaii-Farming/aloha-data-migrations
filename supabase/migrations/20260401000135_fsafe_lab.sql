CREATE TABLE IF NOT EXISTS fsafe_lab (
    id              TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),

    name            TEXT NOT NULL,
    description     TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted       BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT uq_fsafe_lab UNIQUE (org_id, name)
);

COMMENT ON TABLE fsafe_lab IS 'Catalog of laboratories used for food safety test submissions (e.g. test-and-hold pathogen testing).';

CREATE INDEX idx_fsafe_lab_org ON fsafe_lab (org_id);

