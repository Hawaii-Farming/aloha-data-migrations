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

-- --------------------------------------------------------------------
-- RLS: authenticated users can read orgs they belong to.
-- Membership is resolved via get_user_org_ids() (defined in
-- 20260401000142_sys_navigation.sql). Mutations are service-role only.
-- --------------------------------------------------------------------
GRANT SELECT ON public.org TO authenticated;

ALTER TABLE public.org ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "org_read" ON public.org;

CREATE POLICY "org_read" ON public.org
  FOR SELECT TO authenticated
  USING (id IN (SELECT public.get_user_org_ids()));
