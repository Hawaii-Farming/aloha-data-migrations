CREATE TABLE IF NOT EXISTS org (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    address    TEXT,
    currency   TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_org_name UNIQUE (name)
);

COMMENT ON TABLE org IS 'Root entity for multi-org support. Every org-scoped table references this. Stores org-level settings such as default currency.';

-- Seed the single known org up front so later SQL migrations that carry
-- reference-data INSERTs (grow_trial_type.legacy_trial, etc.) don't fail
-- their FK to org(id). The Python migration 002_org.py upserts the same
-- row with full details (address, currency) on the next nightly run.
INSERT INTO public.org (id, name)
VALUES ('hawaii_farming', 'Hawaii Farming')
ON CONFLICT (id) DO NOTHING;

-- RLS lives in 20260401000200_sys_rls_policies.sql.
