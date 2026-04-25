CREATE TABLE IF NOT EXISTS ops_corrective_action_choice (
    org_id      TEXT        NOT NULL REFERENCES org(id),
    name        TEXT PRIMARY KEY,
    description TEXT,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  TEXT,
    is_deleted   BOOLEAN     NOT NULL DEFAULT false,

    CONSTRAINT uq_ops_corrective_action_choice UNIQUE (org_id, name)
);

COMMENT ON TABLE ops_corrective_action_choice IS 'Org-defined reusable corrective action options available for selection when logging a corrective action. Users pick from this dropdown; if the action isn''t listed they provide a custom description instead.';

CREATE INDEX idx_ops_corrective_action_choice_org_id ON ops_corrective_action_choice (org_id);

