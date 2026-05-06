-- Scheduler — nav gate
-- ====================
-- Raises the required sys_access_level for the Scheduler sub-module
-- so the Layer-2 RBAC predicate in hr_rba_navigation
-- (emp_al.level >= req_al.level) filters Employee-tier users out of
-- the sidebar. Owner / Admin / Manager / Team Lead retain access.
--
-- Mirrors the nav-gate pattern shipped 2026-05-01 for payroll
-- (20260501120200_hr_payroll_nav_gate.sql).

UPDATE public.org_sub_module
   SET sys_access_level_id = 'Team Lead'
 WHERE sys_sub_module_id = 'Scheduler';
