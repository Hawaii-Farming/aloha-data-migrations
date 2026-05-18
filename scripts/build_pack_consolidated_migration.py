"""
Build the consolidated pack-module migration from the extracted dump.

Output: supabase/migrations/20260518230000_pack_module_consolidated.sql

Structure:
  1. Migration header explaining what it replaces.
  2. DROP block that wipes every pack-related object (current live +
     legacy from older migrations -- everything goes).
  3. Body: contents of docs/schema/pack_extracted.sql (canonical state
     captured from dev via supabase db dump on 2026-05-18).

The DROP block uses IF EXISTS + CASCADE so it's safe whether the DB
has the new (pack_session) shape, the old (pack_lot / pack_productivity)
shape, or a mix. The legacy table names that may still exist on prod
are included explicitly.

Run from repo root:
    python scripts/build_pack_consolidated_migration.py
"""
from pathlib import Path

SRC = Path("docs/schema/pack_extracted.sql")
DST = Path("supabase/migrations/20260518230000_pack_module_consolidated.sql")

# Tables to drop. Includes everything pack-related that has ever existed in
# this codebase (current + legacy). CASCADE handles FK ordering.
PACK_TABLES = [
    # Current (live on dev as of 2026-05-18)
    "pack_session_cases",
    "pack_session_fails",
    "pack_session_labor_hour",
    "pack_session_leftover",
    "pack_session",
    "pack_fail_category",
    "pack_moisture",
    "pack_shelf_life_photo",
    "pack_shelf_life_result",
    "pack_shelf_life",
    "pack_shelf_life_metric",
    # Legacy (still on prod, gone on dev)
    "pack_lot_item",
    "pack_lot",
    "pack_productivity_hour_fail",
    "pack_productivity_hour",
    "pack_productivity_fail_category",
    "pack_dryer_result",
    "pack_variety",
    "pack_session_product_run",
    "pack_session_product_hour",
]

# Pack-prefixed functions to drop. Triggers using these are dropped via
# CASCADE; we also drop the functions themselves so no dead callable
# remains in pg_proc.
PACK_FUNCTIONS = [
    "pack_session_cases_guard_immutable()",
    "pack_session_fails_guard_immutable()",
    "pack_session_guard_immutable()",
    "pack_session_labor_hour_guard_immutable()",
    "pack_session_leftover_guard_immutable()",
    "pack_session_set_defaults()",
    "pack_shelf_life_cascade_day()",
    "pack_shelf_life_check_termination()",
    "pack_shelf_life_set_day()",
    # Legacy
    "pack_lot_default_lot_number(date, date)",
    "pack_session_product_run_ensure_lot()",
]

PACK_VIEWS = [
    "pack_session_summary_v",
]


def build():
    header = """\
-- pack module — consolidated schema (2026-05-18)
-- ==================================================================
-- This file is the canonical definition of every pack-related object
-- in the database. It REPLACES all prior pack_* migration files,
-- which have been deleted from the repo as part of this consolidation:
--
--   20260401000116_pack_lot.sql
--   20260401000118_pack_lot_item.sql
--   20260401000133_pack_shelf_life_metric.sql
--   20260401000134_pack_shelf_life.sql
--   20260401000135_pack_shelf_life_result.sql
--   20260401000136_pack_shelf_life_photo.sql
--   20260401000137_pack_dryer_result.sql
--   20260401000138_pack_productivity_fail_category.sql
--   20260401000139_pack_productivity_hour.sql
--   20260401000140_pack_productivity_hour_fail.sql
--   20260507230000_pack_dryer_result_drop_uoms.sql
--   20260511210504_pack_productivity_hour_add_fsafe_metal_detected.sql
--   20260513010000_pack_shelf_life_auto_terminate.sql
--   20260513010100_pack_shelf_life_photos_bucket.sql
--   20260513020000_pack_shelf_life_set_day_trigger.sql
--   20260513020100_pack_shelf_life_cascade_day.sql
--   20260514230000_pack_variety.sql
--   20260514230100_pack_session.sql
--   20260514230200_pack_session_product_run.sql
--   20260514230300_pack_session_leftover.sql
--   20260514230400_pack_productivity_hour_alter_for_session.sql
--   20260514230500_pack_session_product_hour.sql
--   20260514230600_pack_lot_alter_constraints.sql
--   20260514230700_pack_lot_default_lot_number_fn.sql
--   20260514230800_pack_session_product_run_lot_trigger.sql
--   20260514230900_pack_session_views.sql
--   20260514231000_pack_session_rls.sql
--   20260514234000_pack_session_write_policies.sql
--   20260515195000_pack_immutability_guards.sql
--   20260515200000_cleanup_jean_pack_test_data.sql
--   20260515210000_wipe_all_pack_test_data.sql
--   20260515220000_hard_delete_soft_deleted_pack.sql
--   20260515220500_wipe_pack_data_again.sql
--   20260515230000_wipe_pack_data_third.sql
--   20260518115800_pack_self_heal_lot_items.sql
--   20260518115900_pack_preflight_audit.sql
--   20260518120000_pack_drop_views_triggers_guards.sql
--   20260518120100_pack_truncate_test_data.sql
--   20260518120200_pack_session_restructure.sql
--   20260518120300_pack_session_labor_hour.sql
--   20260518120400_pack_session_cases.sql
--   20260518120500_pack_session_leftover_restructure.sql
--   20260518120600_pack_session_fails.sql
--   20260518120700_pack_renames.sql
--   20260518120800_pack_session_backfill_from_lot.sql
--   20260518121100_pack_shelf_life_redirect.sql
--   20260518121300_pack_lot_drop.sql
--   20260518121400_pack_session_summary_v.sql
--   20260518121500_pack_session_rls.sql
--   20260518121600_pack_immutability_guards.sql
--   20260518121700_pack_session_defaults_trigger.sql
--   20260518121800_pack_session_finalize.sql
--   20260518121900_pack_shelf_life_day_recreate.sql
--   20260518150000_pack_disable_packlot_submodule.sql
--   20260518160000_pack_data_audit_diagnostic.sql
--   20260518170000_pack_session_fix_invalid_stopped.sql
--
-- The original versions are marked `--status reverted` in
-- supabase_migrations.schema_migrations on both dev and prod so they
-- no longer participate in the migration history -- the live DB state
-- is what THIS file alone is the source of truth for.
--
-- On apply: drops everything pack-related and recreates from scratch.
-- ALL EXISTING PACK DATA IS LOST. This is intentional -- the schema
-- has churned past the point where preservation is meaningful.
--
-- The body of this file (everything below the second `-- =====` rule)
-- is the verbatim output of `supabase db dump --schema public` against
-- dev on 2026-05-18, filtered to pack_-target statements by
-- scripts/carve_pack_from_dump.py. See docs/schema/pack_extracted.sql
-- for the standalone reference.

-- ==================================================================
-- Drop section: wipe everything pack-related.
-- ==================================================================

"""

    drops = []
    drops.append("-- Views first (no dependents).\n")
    for v in PACK_VIEWS:
        drops.append(f"DROP VIEW IF EXISTS public.{v} CASCADE;\n")
    drops.append("\n")
    drops.append("-- Tables. CASCADE drops dependent FKs from non-pack tables\n")
    drops.append("-- (those FKs are reapplied by this migration's body where they\n")
    drops.append("-- originate on the pack side).\n")
    for t in PACK_TABLES:
        drops.append(f"DROP TABLE IF EXISTS public.{t} CASCADE;\n")
    drops.append("\n")
    drops.append("-- Trigger functions. CASCADE drops any remaining trigger that\n")
    drops.append("-- depends on them, in case a non-pack table referenced one.\n")
    for f in PACK_FUNCTIONS:
        drops.append(f"DROP FUNCTION IF EXISTS public.{f} CASCADE;\n")

    body_header = """

-- ==================================================================
-- Recreate from canonical state (sourced from dev dump 2026-05-18).
-- ==================================================================

"""

    src_text = SRC.read_text()
    # Skip the carve script's leading comment header (first non-blank block).
    lines = src_text.splitlines(keepends=True)
    start = 0
    for i, ln in enumerate(lines):
        if ln.strip().startswith("--") or ln.strip() == "":
            continue
        start = i
        break
    body = "".join(lines[start:])

    DST.parent.mkdir(parents=True, exist_ok=True)
    DST.write_text(header + "".join(drops) + body_header + body)
    print(f"Wrote {DST}")
    print(f"  {DST.stat().st_size} bytes, ~{sum(1 for _ in DST.read_text().splitlines())} lines")


if __name__ == "__main__":
    build()
