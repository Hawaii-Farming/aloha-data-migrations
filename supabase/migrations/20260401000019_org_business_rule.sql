CREATE TABLE IF NOT EXISTS org_business_rule (
    org_id              TEXT NOT NULL REFERENCES org(id),
    id                  TEXT PRIMARY KEY,
    rule_type           TEXT NOT NULL CHECK (rule_type IN ('business_rule', 'workflow', 'calculation', 'requirement', 'definition')),
    module              TEXT,
    title               TEXT NOT NULL,
    description         TEXT NOT NULL,
    rationale           TEXT,
    applies_to          JSONB NOT NULL DEFAULT '[]',
    is_active           BOOLEAN NOT NULL DEFAULT true,
    display_order       INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          TEXT,
    is_deleted          BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE org_business_rule IS 'Org-scoped registry for business rules, workflows, calculations, requirements, and definitions. Queryable by employees (tooltips), developers (context), and AI (alignment).';

COMMENT ON COLUMN org_business_rule.rule_type IS 'business_rule, workflow, calculation, requirement, definition';
COMMENT ON COLUMN org_business_rule.applies_to IS 'JSON array of table.column references this rule applies to (e.g. ["invnt_onhand.invnt_lot_id"])';

CREATE INDEX idx_org_business_rule_type ON org_business_rule (rule_type);
CREATE INDEX idx_org_business_rule_module ON org_business_rule (module);
