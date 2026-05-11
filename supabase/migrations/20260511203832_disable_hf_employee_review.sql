-- Disable Employee Review sub-module for hawaii_farming
-- ======================================================
-- The HR Employee Review sub-module is being turned off pending further
-- product work. We update the live org_sub_module row here so the change
-- is visible immediately, AND remove "Employee Review" from the
-- ENABLED_SUB_MODULES seed list in 20260401000002_org.py so any future
-- re-seed (`--all` nightly, fresh-org provisioning) keeps it disabled.

UPDATE public.org_sub_module
SET    is_enabled = false,
       updated_at = now(),
       updated_by = 'data@hawaiifarming.com'
WHERE  org_id            = 'hawaii_farming'
  AND  sys_sub_module_id = 'Employee Review'
  AND  is_enabled        = true;
