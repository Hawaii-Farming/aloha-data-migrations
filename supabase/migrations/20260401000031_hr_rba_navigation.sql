-- HR Role-Based Access Navigation View
-- ====================================
-- Workspace-shell navigation view. Sits at the end of the hr cluster
-- because it joins seven tables that must exist first (hr_employee,
-- hr_module_access, sys_access_level, sys_module, sys_sub_module,
-- org_module, org_sub_module).
--
-- Three access-control layers combine in hr_rba_navigation:
--   Layer 1 — feature toggle:  org_module.is_enabled / org_sub_module.is_enabled
--   Layer 2 — RBAC:            employee access_level.level >= sub_module access_level.level
--   Layer 3 — ABAC:            hr_module_access per-employee per-module permissions

-- ============================================================
-- hr_rba_navigation
-- ============================================================
-- One row per accessible (org, module, sub_module) for the current user.
--
-- Used by:
--   - Workspace loader: build sidebar (group rows by module_slug)
--   - requireModuleAccess: filter by org_id + module_slug
--   - requireSubModuleAccess: filter by org_id + module_slug + sub_module_slug
--
-- Tenant scoping: this view is GRANTed to the authenticated role, but the
-- WHERE clause filters every row by `e.user_id = auth.uid()` — each caller
-- only sees rows joined to THEIR own hr_employee record(s). Multi-org users
-- see one row per (org, module, sub_module) across all orgs they belong to.
-- Do not remove the auth.uid() filter — it is the entire access control.

CREATE OR REPLACE VIEW public.hr_rba_navigation AS
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

GRANT SELECT ON public.hr_rba_navigation TO authenticated;
