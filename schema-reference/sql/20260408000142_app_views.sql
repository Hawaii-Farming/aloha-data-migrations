-- App Views & RLS: Navigation & Access Control
-- ==============================================
-- RLS policies on hr_employee and org, plus one navigation view
-- that powers the frontend workspace shell.
--
-- View:
--   app_navigation — one row per accessible sub-module, with parent module
--                    info and ABAC permissions included on each row
--
-- Layers:
--   Layer 1 — Feature toggle: org_module.is_enabled / org_sub_module.is_enabled
--   Layer 2 — RBAC: employee access_level >= sub_module minimum_access_level
--   Layer 3 — ABAC: hr_module_access per-employee per-module permissions

-- ============================================================
-- Grants: authenticated role needs SELECT on underlying tables
-- ============================================================

GRANT SELECT ON public.org TO authenticated;
GRANT SELECT ON public.hr_employee TO authenticated;
GRANT SELECT ON public.sys_access_level TO authenticated;
GRANT SELECT ON public.sys_module TO authenticated;
GRANT SELECT ON public.sys_sub_module TO authenticated;
GRANT SELECT ON public.org_module TO authenticated;
GRANT SELECT ON public.org_sub_module TO authenticated;
GRANT SELECT ON public.hr_module_access TO authenticated;

-- ============================================================
-- Helper: get org_ids for the current user (SECURITY DEFINER
-- to avoid infinite recursion when called from hr_employee RLS)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_user_org_ids()
RETURNS SETOF TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT org_id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND is_deleted = false;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_org_ids() TO authenticated;

-- ============================================================
-- RLS: hr_employee (org-scoped)
-- ============================================================
-- Any authenticated employee in the same org can read all employees.
-- This allows managers/admins to see the full roster.
-- Uses get_user_org_ids() to avoid self-referential recursion.
--
-- IMPORTANT — Mutation policy:
-- There are intentionally NO INSERT/UPDATE/DELETE policies on hr_employee
-- (or any other org-scoped table). All mutations from the app go through
-- a server-side route action that uses the service_role key, which bypasses
-- RLS by design. Authorization is enforced in the app layer:
--   1. requireUserLoader() validates the JWT
--   2. loadOrgWorkspace() resolves the employee + org membership
--   3. requireModuleAccess() / requireSubModuleAccess() check hr_module_access
--      for can_edit / can_delete / can_verify on the relevant module
-- Direct PostgREST writes from the browser session client are blocked because
-- no policy permits them. If a future feature needs client-side writes,
-- add explicit INSERT/UPDATE policies — do not enable broad write access.

ALTER TABLE public.hr_employee ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hr_employee_read" ON public.hr_employee;

CREATE POLICY "hr_employee_read" ON public.hr_employee
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

-- ============================================================
-- Mutation Strategy: hr_employee and org
-- ============================================================
-- INSERT/UPDATE/DELETE on hr_employee and org are performed
-- exclusively through the service_role key in server-side
-- route actions (app/lib/supabase/clients/server-client.server.ts).
--
-- The service_role key bypasses RLS entirely. Fine-grained
-- write permissions are enforced in the application layer by
-- checking hr_module_access (can_edit, can_delete, can_verify)
-- before issuing mutations.
--
-- No INSERT/UPDATE/DELETE RLS policies are defined here because:
--   1. The authenticated role has only SELECT grants on these tables.
--   2. All mutations flow through service_role, which bypasses RLS.
--   3. Application-layer enforcement via hr_module_access provides
--      per-employee per-module CRUD control that is more granular
--      than row-level policies alone.
--
-- If authenticated-role mutations are needed in the future,
-- add org-scoped INSERT/UPDATE policies following the pattern
-- in supabase/CLAUDE.md.

-- ============================================================
-- RLS: org (read by any authenticated user with membership)
-- ============================================================

ALTER TABLE public.org ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "org_read" ON public.org;

CREATE POLICY "org_read" ON public.org
  FOR SELECT TO authenticated
  USING (id IN (SELECT public.get_user_org_ids()));

-- ============================================================
-- Performance: composite index for app_navigation join
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_hr_module_access_employee_module
  ON public.hr_module_access(hr_employee_id, org_module_id);

-- ============================================================
-- app_navigation
-- ============================================================
-- Cross-tenant note: This view is NOT cross-tenant despite being
-- granted to all authenticated users. The WHERE clause filters on
-- `e.user_id = auth.uid()`, which restricts results to orgs where
-- the current user has an hr_employee membership. A user in Org A
-- cannot see Org B's navigation — they would need an hr_employee
-- row in Org B. The authenticated GRANT is safe because the view
-- itself enforces tenant isolation via the auth.uid() join.
-- Returns one row per accessible sub-module with parent module info.
-- Applies all three access control layers:
--   Layer 1 — org_module.is_enabled + org_sub_module.is_enabled
--   Layer 2 — employee access_level.level >= sub_module access_level.level
--   Layer 3 — hr_module_access.is_enabled + permission flags
--
-- Used by:
--   - Workspace loader: build sidebar (group rows by module_slug)
--   - requireModuleAccess: filter by org_id + module_slug (any row gives permissions)
--   - requireSubModuleAccess: filter by org_id + module_slug + sub_module_slug
--
-- module_slug     = sys_module.id      (e.g. 'human_resources')
-- sub_module_slug = sys_sub_module.id  (e.g. 'employees')
--
-- TENANT SCOPING — important:
-- This view is GRANTed to the `authenticated` role, but the WHERE clause
-- below filters every row by `e.user_id = auth.uid()`. That means each
-- caller only sees rows joined to THEIR own hr_employee record(s) — even
-- though there is no separate RLS policy on the view itself. Multi-org
-- users see one row per (org, module, sub_module) across all orgs they
-- belong to, which is the intended behavior for the workspace switcher.
-- Do not remove the auth.uid() filter; it is the entire access control.

CREATE OR REPLACE VIEW public.app_navigation AS
SELECT
    om.org_id,
    -- Module columns
    om.id               AS module_id,
    sm.id               AS module_slug,
    om.display_name     AS module_display_name,
    om.display_order    AS module_display_order,
    -- Sub-module columns
    osm.id              AS sub_module_id,
    ssm.id              AS sub_module_slug,
    osm.display_name    AS sub_module_display_name,
    osm.display_order   AS sub_module_display_order,
    -- ABAC permissions (module-level)
    ma.can_edit,
    ma.can_delete,
    ma.can_verify
FROM public.hr_employee e
JOIN public.sys_access_level emp_al  ON emp_al.id = e.sys_access_level_id
JOIN public.org_sub_module osm       ON osm.org_id = e.org_id
JOIN public.org_module om            ON om.org_id = osm.org_id
                                    AND om.sys_module_id = osm.sys_module_id
JOIN public.sys_module sm            ON sm.id = osm.sys_module_id
JOIN public.sys_sub_module ssm       ON ssm.id = osm.sys_sub_module_id
JOIN public.sys_access_level req_al  ON req_al.id = osm.sys_access_level_id
JOIN public.hr_module_access ma      ON ma.hr_employee_id = e.id
                                    AND ma.org_module_id = om.id
WHERE e.user_id = auth.uid()
  AND e.is_deleted = false
  AND om.is_enabled = true          -- Layer 1: parent module enabled
  AND om.is_deleted = false
  AND osm.is_enabled = true         -- Layer 1: sub-module enabled
  AND osm.is_deleted = false
  AND ma.is_enabled = true          -- Layer 3: employee module access
  AND ma.is_deleted = false
  AND emp_al.level >= req_al.level; -- Layer 2: RBAC tier check

GRANT SELECT ON public.app_navigation TO authenticated;
