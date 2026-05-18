-- Pack restructure follow-up: disable the legacy "Packlot" sub-module.
--
-- Context: the pack_lot table was dropped in migration 20260518121300 and
-- the front-end CRUD config was removed in the same wave. Any org row in
-- org_sub_module pointing at sys_sub_module_id = 'Packlot' would still
-- render a sidebar link that produces a 500 when clicked (the route
-- loader has no config to look up, falls through to querying a view
-- named "Packlot", which does not exist).
--
-- We DISABLE rather than DELETE for two reasons:
--   1. Historical audit trails (created_by/updated_by) on org_sub_module
--      remain consistent without orphaning rows.
--   2. The sys_sub_module row itself is referenced from gsheets seed
--      scripts (20260401000001_sys.py) and DELETE-ing the sys row would
--      break the upstream invariant that every org_sub_module row has a
--      matching sys row.
--
-- Effect: org_sub_module.is_enabled = false hides the sub-module from
-- the workspace navigation view (hr_rba_navigation filters on is_enabled).

UPDATE org_sub_module
   SET is_enabled = false,
       updated_at = now(),
       updated_by = 'system@aloha.ag'
 WHERE sys_sub_module_id = 'Packlot'
   AND is_enabled = true;

COMMENT ON TABLE org_sub_module IS 'Org-scoped copy of system sub-modules. Seeded when a new org is created. Org admins toggle is_enabled to control which sub-modules are available within each enabled module. Composite PK (org_id, sys_sub_module_id) lets every org reuse the same canonical sys_sub_module ids without ID-namespace collisions. Note: "Packlot" was retired on 2026-05-18 when pack_lot table was dropped; rows are kept with is_enabled=false to preserve audit history.';
