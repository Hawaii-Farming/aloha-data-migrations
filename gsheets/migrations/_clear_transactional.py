"""
TRUNCATE all transactional tables in reverse FK dependency order.

Used before a full re-run of migrations 003-034 to avoid cross-migration
FK violations (e.g. clearing grow_lettuce_seed_batch while grow_harvest_weight
still references it).

HR reference tables (hr_employee + its descendants) ARE truncated here
because the HR module must be fully refreshed nightly from the source
sheet — legacy id drift between runs would otherwise accumulate and
block re-inserts via unique-name constraints. Migration 003 is
responsible for re-linking auth.users → hr_employee.user_id after the
truncate-and-reinsert, so the RLS chain stays intact.

Does NOT touch the remaining reference / seed tables (sys_uom, org,
org_farm, org_site, invnt_item, invnt_vendor, invnt_category,
grow_variety, grow_grade, grow_pest, grow_disease, ops_task, etc.) —
those are upserted idempotently by migrations 001-002 and 006, and
CASCADE-wiping them would also wipe the static cuke_plantmap-seeded
tables (grow_cuke_seed_batch, grow_cuke_gh_row_planting, org_site_cuke_gh*)
which have no nightly re-populator.

Usage:
    python migrations/_clear_transactional.py
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import psycopg2

from _config import _load_env_file  # noqa: triggers .env load

# In reverse FK dependency order — deepest dependents first so the single
# TRUNCATE ... CASCADE handles any missed chain.
TABLES = [
    "ops_corrective_action_taken",
    "ops_template_result_photo",
    "ops_template_result",
    "grow_task_photo",
    "grow_task_seed_batch",
    "grow_monitoring_result",
    "grow_scout_result",
    "grow_spray_input",
    "grow_spray_equipment",
    "grow_fertigation",
    "grow_fertigation_recipe_site",
    "grow_fertigation_recipe_item",
    "grow_fertigation_recipe",
    "grow_harvest_weight",
    "grow_harvest_container",
    "fsafe_pest_result",
    "fsafe_result",
    "fsafe_test_hold_po",
    "fsafe_test_hold",
    "pack_productivity_hour_fail",
    "pack_productivity_hour",
    "pack_dryer_result",
    "pack_shelf_life_photo",
    "pack_shelf_life_result",
    "pack_shelf_life",
    "pack_lot_item",
    "pack_lot",
    "sales_po_fulfillment",
    "sales_po_line",
    "sales_po",
    "sales_product_price",
    "sales_crm_store_visit_result",
    "sales_crm_store_visit_photo",
    "sales_crm_store_visit",
    "sales_crm_store",
    "sales_crm_external_product",
    "sales_customer",
    "sales_customer_group",
    "sales_fob",
    "grow_spray_compliance",
    # grow_cuke_gh_row_planting and grow_cuke_seed_batch are intentionally
    # excluded — both are static/forward-planned tables populated by the
    # one-time 20260417000001_cuke_plantmap.py seeder (and recoverable via
    # 20260418000001_rebuild_cuke_seed_batch_and_planting.py). No nightly
    # re-populator exists for them, so truncating them here leaves the
    # plant-map empty and breaks 025's batch lookup. Do not re-add without
    # a repopulator.
    "grow_lettuce_seed_batch",
    "grow_lettuce_seed_mix_item",
    "grow_lettuce_seed_mix",
    # grow_trial_type excluded — reference data upserted idempotently by
    # its own migrations, and truncating it CASCADE-wipes grow_cuke_seed_batch
    # via the trial_type FK. Retired 024 was the only thing reseeding
    # 'legacy_trial'; with 024 gone, truncating leaves the 13 historical
    # cuke trial batches orphaned. Treat as static reference data.
    "grow_cycle_pattern",
    "grow_monitoring_metric",
    "maint_request_photo",
    "maint_request_invnt_item",
    "maint_request",
    "ops_task_schedule",
    "ops_task_tracker",
    "ops_template_question",
    "ops_task_template",
    "ops_template",
    "ops_training_attendee",
    "ops_training",
    "invnt_onhand",
    "invnt_po_received",
    "invnt_po",
    "invnt_lot",
    "fsafe_lab_test",
    "fsafe_lab",
    # HR reference chain — truncate in reverse FK order. Migration 003 is
    # responsible for re-linking auth.users → hr_employee.user_id after
    # reinserting hr_employee rows.
    "hr_disciplinary_warning",
    "hr_employee_review",
    "hr_module_access",
    "hr_time_off_request",
    "hr_travel_request",
    "hr_payroll",
    "hr_employee",
    "hr_work_authorization",
    "hr_department",
    "org_business_rule",
]


def main():
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise SystemExit("ERROR: SUPABASE_DB_URL not set")

    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cur = conn.cursor()

    sql = "TRUNCATE TABLE " + ", ".join(TABLES) + " CASCADE;"
    print(f"Truncating {len(TABLES)} transactional tables...")
    cur.execute(sql)
    print("  Done.")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
