-- org_quickbooks_token
-- ====================
-- Stores the OAuth artifacts returned by Intuit when an org connects
-- QuickBooks Online via aloha-app. One row per org -- the (org_id) PK
-- enforces a single QB connection per org. Companies that ever need
-- separate QB books for cuke vs lettuce farms would refactor to
-- (org_id, scope) at that time.
--
-- Tokens are SECRETS. This table is intentionally NOT exposed to the
-- authenticated role. The aloha-app server-side OAuth handlers use the
-- service-role client to read/write rows; nothing on the browser
-- session client should ever reach this table.
--
-- Field reference:
--   realm_id           -- Intuit's identifier for the connected QB
--                          company. Used as the path segment on every
--                          QB API call: /v3/company/{realmId}/...
--   access_token       -- short-lived bearer (expires in ~1 hour)
--   refresh_token      -- long-lived (~101 days). ROTATES on every
--                          refresh; always store whatever the latest
--                          refresh response returns.
--   access_expires_at  -- timestamp when the access_token stops working
--                          (computed at write time as now() + expires_in
--                          seconds).
--   refresh_expires_at -- timestamp when re-auth is required. After
--                          this, the user must reconnect from the UI.
--   connected_by       -- hr_employee.id (composite-FK with org_id) of
--                          the operator who established the connection.
--
-- Single source of truth for QB connection state for the org:
--   * row exists + refresh_expires_at > now() => connected, can sync
--   * row exists + refresh_expires_at <= now() => need reconnect
--   * no row => never connected (or disconnected and row deleted)

CREATE TABLE IF NOT EXISTS org_quickbooks_token (
    org_id              TEXT PRIMARY KEY REFERENCES org(id),
    realm_id            TEXT NOT NULL,
    access_token        TEXT NOT NULL,
    refresh_token       TEXT NOT NULL,
    access_expires_at   TIMESTAMPTZ NOT NULL,
    refresh_expires_at  TIMESTAMPTZ NOT NULL,
    connected_by        TEXT,
    connected_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted          BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT org_quickbooks_token_connected_by_fkey
      FOREIGN KEY (org_id, connected_by) REFERENCES hr_employee(org_id, id)
);

COMMENT ON TABLE org_quickbooks_token IS 'OAuth tokens for the org''s connected QuickBooks Online company. Service-role-only -- not exposed via PostgREST to authenticated users. One row per org. realm_id, access_token, refresh_token rotate on every refresh; always overwrite with the latest values.';

COMMENT ON COLUMN org_quickbooks_token.realm_id IS 'Intuit-assigned company id used in every QB API path: /v3/company/{realmId}/...';
COMMENT ON COLUMN org_quickbooks_token.access_token IS 'OAuth bearer token. Expires after ~1 hour; refresh on demand using refresh_token.';
COMMENT ON COLUMN org_quickbooks_token.refresh_token IS 'Long-lived (~101 days). ROTATES on every refresh -- always persist the new value returned by Intuit. Reuse of an old refresh_token causes Intuit to invalidate the chain.';
COMMENT ON COLUMN org_quickbooks_token.refresh_expires_at IS 'After this time the user must reconnect from the UI; access_token cannot be refreshed.';
COMMENT ON COLUMN org_quickbooks_token.connected_by IS 'Composite-FK (org_id, connected_by) -> hr_employee. The operator who clicked "Connect to QuickBooks".';

-- ============================================================
-- RLS: lock down completely. No SELECT / INSERT / UPDATE / DELETE
-- policy is granted to authenticated, so every PostgREST call from the
-- browser session client returns 0 rows / 401. The aloha-app OAuth
-- routes use the service-role client (which bypasses RLS) for all
-- reads and writes.
-- ============================================================
ALTER TABLE public.org_quickbooks_token ENABLE ROW LEVEL SECURITY;
-- Intentionally NO policies. Service role only.

REVOKE ALL ON public.org_quickbooks_token FROM authenticated;
REVOKE ALL ON public.org_quickbooks_token FROM anon;
