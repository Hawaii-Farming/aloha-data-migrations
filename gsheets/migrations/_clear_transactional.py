"""
Clear transactional tables before a full re-run of migrations 003-034.

Two-phase strategy:

  1. TRUNCATE ... CASCADE on the non-HR transactional tables (sales / pack /
     fsafe / grow / ops / maint / invnt / org_business_rule). Today these
     only carry hawaii_farming data, so a global TRUNCATE is the simplest
     way to clear them and lets CASCADE catch any descendant tables we
     haven't enumerated (e.g. EDI / ASN / pallet allocations recently
     added). If a future org starts writing to these, switch the relevant
     entries from the TRUNCATE list to the per-org DELETE list.

  2. DELETE WHERE org_id = HF_ORG_ID on the HR reference chain
     (hr_employee + descendants). Campo Caribe has its own rows in these
     tables and the previous all-org TRUNCATE wiped them every night.
     Deleting per-org leaves Campo intact.

Post-clear, migration 003 reinserts HF employees and re-links
auth.users -> hr_employee.user_id; the campo_caribe_hr.py one-off does
the equivalent for Campo when re-run.

Does NOT touch reference / seed tables (sys_uom, org, org_farm, org_site,
invnt_item, invnt_vendor, invnt_category, grow_variety, grow_grade,
grow_pest, grow_disease, ops_task, etc.) -- those are upserted
idempotently by migrations 001-002 and 006.

Usage:
    python migrations/_clear_transactional.py
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import psycopg2

from _config import _load_env_file  # noqa: triggers .env load

HF_ORG_ID = "hawaii_farming"

# ---------------------------------------------------------------------------
# Phase 1 -- non-HR transactional tables, TRUNCATEd CASCADE all-org.
# Reverse FK order is preserved here so the single TRUNCATE call works even
# if CASCADE has to chase any unlisted descendant.
# ---------------------------------------------------------------------------
NON_HR_TABLES = [
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
    # excluded -- both are static/forward-planned tables populated by the
    # one-time 20260417000001_cuke_plantmap.py seeder (and recoverable via
    # 20260418000001_rebuild_cuke_seed_batch_and_planting.py). No nightly
    # re-populator exists for them, so truncating them here leaves the
    # plant-map empty and breaks 025's batch lookup. Do not re-add without
    # a repopulator.
    "grow_lettuce_seed_batch",
    "grow_lettuce_seed_mix_item",
    "grow_lettuce_seed_mix",
    # grow_trial_type excluded -- reference data upserted idempotently by
    # its own migrations, and truncating it CASCADE-wipes grow_cuke_seed_batch
    # via the trial_type FK.
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
    "org_business_rule",
]

# ---------------------------------------------------------------------------
# Phase 2 -- HR chain, deleted per-org. Reverse FK order so children go
# before their parents.
# ---------------------------------------------------------------------------
HR_TABLES_REVERSE_FK = [
    "hr_disciplinary_warning",
    "hr_employee_review",
    "hr_module_access",
    "hr_time_off_request",
    "hr_travel_request",
    "hr_payroll",
    "hr_employee",
    "hr_work_authorization",
    "hr_department",
]


def main():
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise SystemExit("ERROR: SUPABASE_DB_URL not set")

    conn = psycopg2.connect(db_url)
    conn.autocommit = False
    cur = conn.cursor()

    # Phase 1: non-HR tables, all-org TRUNCATE CASCADE.
    print(f"Phase 1: TRUNCATE CASCADE {len(NON_HR_TABLES)} non-HR tables...")
    cur.execute("TRUNCATE TABLE " + ", ".join(NON_HR_TABLES) + " CASCADE;")

    # Phase 2: HR chain, scoped DELETE.
    # 2a. Break external FK to hr_employee (org_quickbooks_token.connected_by)
    #     before deleting HF employees.
    cur.execute(
        "UPDATE org_quickbooks_token SET connected_by = NULL WHERE org_id = %s",
        (HF_ORG_ID,),
    )

    # 2b. Break self-FKs on hr_employee so the per-row FK check during DELETE
    #     doesn't trip when team_lead/comp_manager point at another HF row
    #     also being deleted.
    cur.execute(
        "UPDATE hr_employee "
        "SET team_lead_id = NULL, compensation_manager_id = NULL "
        "WHERE org_id = %s",
        (HF_ORG_ID,),
    )

    # 2c. Delete the HR chain in reverse FK order, scoped to HF.
    print(f"Phase 2: DELETE org_id='{HF_ORG_ID}' from {len(HR_TABLES_REVERSE_FK)} HR tables...")
    total_deleted = 0
    for tbl in HR_TABLES_REVERSE_FK:
        cur.execute(f"DELETE FROM {tbl} WHERE org_id = %s", (HF_ORG_ID,))
        print(f"  {tbl:30s} {cur.rowcount} rows")
        total_deleted += cur.rowcount

    conn.commit()
    cur.close()
    conn.close()
    print(f"Done. {total_deleted} HR rows cleared for {HF_ORG_ID}; Campo Caribe data preserved.")


if __name__ == "__main__":
    main()
