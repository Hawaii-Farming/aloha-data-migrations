-- Revert: Scheduler nav-gate RBAC bump
-- =====================================
-- Restores org_sub_module.sys_access_level_id for Scheduler back to
-- 'Manager' (the system default from sys_sub_module.id='Scheduler').
-- The 110200 migration had set it to 'Team Lead' to hide Scheduler from
-- the Employee tier; product decision now drops that gate.

UPDATE public.org_sub_module
   SET sys_access_level_id = 'Manager'
 WHERE sys_sub_module_id = 'Scheduler';
