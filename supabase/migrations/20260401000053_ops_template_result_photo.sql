CREATE TABLE IF NOT EXISTS ops_template_result_photo (
    org_id                      TEXT NOT NULL REFERENCES org(id),
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_name                     TEXT REFERENCES org_farm(name),
    ops_template_result_id      UUID NOT NULL REFERENCES ops_template_result(id),
    photo_url                   TEXT NOT NULL,
    caption                     TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  TEXT,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by                  TEXT,
    is_deleted                  BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE ops_template_result_photo IS 'Photos attached to a checklist response. One row per photo. Only used when ops_template_question.include_photo = true.';

CREATE INDEX idx_ops_template_result_photo_result ON ops_template_result_photo (ops_template_result_id);
