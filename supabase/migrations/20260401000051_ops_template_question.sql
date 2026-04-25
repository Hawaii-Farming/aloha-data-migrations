CREATE TABLE IF NOT EXISTS ops_template_question (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id              TEXT        NOT NULL REFERENCES org(id),
    farm_name             TEXT        REFERENCES org_farm(name),
    ops_template_name     TEXT        NOT NULL REFERENCES ops_template(name),

    question_text       TEXT        NOT NULL,
    response_type       TEXT        NOT NULL CHECK (response_type IN ('boolean', 'numeric', 'enum')),
    is_required         BOOLEAN     NOT NULL DEFAULT true,

    -- Boolean response settings
    boolean_pass_value          BOOLEAN,

    -- Numeric response settings
    minimum_value       NUMERIC,
    maximum_value       NUMERIC,

    -- Enum response settings
    enum_options                JSONB,
    enum_pass_options           JSONB,

    warning_message                     TEXT,
    ops_corrective_action_choice_ids    JSONB,
    include_photo                       BOOLEAN NOT NULL DEFAULT false,

    display_order       INTEGER     NOT NULL DEFAULT 0,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted           BOOLEAN     NOT NULL DEFAULT false
);

COMMENT ON TABLE ops_template_question IS 'Questions within a checklist template. Ordered by display_order within each template.';

CREATE INDEX idx_ops_template_question_org_id   ON ops_template_question (org_id);
CREATE INDEX idx_ops_template_question_template ON ops_template_question (ops_template_name, display_order);

COMMENT ON COLUMN ops_template_question.response_type IS 'boolean, numeric, enum';
COMMENT ON COLUMN ops_template_question.boolean_pass_value IS 'The boolean value that constitutes a pass';
COMMENT ON COLUMN ops_template_question.enum_options IS 'JSON array of available options when response_type is enum';
COMMENT ON COLUMN ops_template_question.enum_pass_options IS 'JSON array of enum values that constitute a pass';
COMMENT ON COLUMN ops_template_question.ops_corrective_action_choice_ids IS 'JSON array of suggested corrective action choice IDs when this question fails';
COMMENT ON COLUMN ops_template_question.farm_name IS 'Inherited from ops_template.farm_name when question is created';
