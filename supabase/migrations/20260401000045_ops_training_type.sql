CREATE TABLE IF NOT EXISTS ops_training_type (
    id          TEXT        PRIMARY KEY,
    org_id      TEXT        NOT NULL REFERENCES org(id),
    name        TEXT        NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted   BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT uq_ops_training_type UNIQUE (org_id, name)
);

COMMENT ON TABLE ops_training_type IS 'Org-specific training types used to classify training sessions. Each org defines its own set of types.';

CREATE INDEX idx_ops_training_type_org_id ON ops_training_type (org_id);
CREATE INDEX idx_ops_training_type_active ON ops_training_type (org_id, is_deleted);

