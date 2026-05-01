-- hr_payroll_nav_gate
-- ===================
-- Layer-2 RBAC nav gate. The hr_rba_navigation view (migration
-- 20260401000031) joins org_sub_module against sys_access_level via
-- emp_al.level >= req_al.level, so raising the required
-- sys_access_level_id on the four payroll/hours sub-modules from
-- 'Employee' (lowest) to 'Team Lead' is enough to drop the entries
-- from the Employee tier's sidebar without touching the navigation
-- view definition.
--
-- Owner / Admin / Manager / Team Lead all retain access; only the
-- Employee tier loses the four entries.
--
-- The four sys_sub_module.id strings ('Hours Comp', 'Payroll Comp',
-- 'Payroll Comp Manager', 'Payroll Data') were verified against the
-- hosted DB before writing this UPDATE.

UPDATE public.org_sub_module
   SET sys_access_level_id = 'Team Lead'
 WHERE sys_sub_module_id IN (
       'Hours Comp',
       'Payroll Comp',
       'Payroll Comp Manager',
       'Payroll Data'
 );
