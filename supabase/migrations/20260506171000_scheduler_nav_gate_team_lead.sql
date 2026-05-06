-- Scheduler nav gate: Manager -> Team Lead
-- =========================================
-- Lowers the org_sub_module access requirement for Scheduler so that
-- Team Lead tier users can see the sidebar entry. No row-scope RBAC
-- (intentionally — see 260506-epq revert); everyone with menu access
-- still sees all org rows in the grid.
--
-- Scope: both currently-provisioned orgs. The system default in
-- sys_sub_module remains 'Manager' (unchanged) so freshly-provisioned
-- orgs keep the stricter default and can opt in.

UPDATE public.org_sub_module
   SET sys_access_level_id = 'Team Lead'
 WHERE sys_sub_module_id = 'Scheduler';
