-- Purge inactive sub-modules
-- ============================
-- The sys_sub_module catalog was originally seeded from the legacy
-- "global_menu_icons_sub" Google Sheet, which carries the full Aloha
-- sub-module surface (≈50 items). Most of those represent the old system
-- and won't be rebuilt against the new schema; we'll add new
-- sub-modules explicitly as features ship.
--
-- Hard-delete the inactive rows now so the org tables only show what's
-- actually live, and so views like hr_rba_navigation don't have to
-- filter dead rubble.
--
-- Two-step delete:
--   1. Drop every org_sub_module row that's disabled or soft-deleted.
--      After this step, every remaining org_sub_module row is active
--      (is_enabled = true AND is_deleted = false).
--   2. Drop every sys_sub_module row that's no longer referenced by any
--      remaining (= active) org_sub_module row.
--
-- Paired with a patch to gsheets/migrations/20260401000001_sys.py that
-- adds an ACTIVE_SUB_MODULES allowlist, so a re-run of 001 (manual /
-- `--all`) won't reseed the removed rows from the sheet.
--
-- Modules (sys_module / org_module) are intentionally left alone — they
-- have downstream dependents (hr_module_access, ops_template) and will
-- be handled separately when the seed scripts for those tables are
-- cleaned up.

BEGIN;

DELETE FROM public.org_sub_module
 WHERE is_enabled = false
    OR is_deleted = true;

DELETE FROM public.sys_sub_module
 WHERE id NOT IN (
     SELECT DISTINCT sys_sub_module_id
       FROM public.org_sub_module
 );

COMMIT;
