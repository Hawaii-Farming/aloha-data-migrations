"""
Migrate Org Business Rules
===========================
Seeds org_business_rule with business rules, workflows, calculations,
requirements, and definitions derived from the schema and process docs.

Usage:
    python scripts/migrations/20260401000024_business_rule.py

Rerunnable: clears and reinserts all data on each run.
"""

import sys
from pathlib import Path

# Add this script's directory to sys.path so we can import _config regardless
# of where the script is invoked from (repo root vs scripts/migrations).
sys.path.insert(0, str(Path(__file__).parent))

from supabase import create_client

from gsheets.migrations._config import (
    AUDIT_USER,
    ORG_ID,
    SUPABASE_URL,
    require_supabase_key,
)


def rule(id, rule_type, module, title, description, rationale, applies_to, order):
    return {
        "id": id,
        "org_id": ORG_ID,
        "rule_type": rule_type,
        "module": module,
        "title": title,
        "description": description,
        "rationale": rationale,
        "applies_to": applies_to,
        "is_active": True,
        "display_order": order,
        "created_by": AUDIT_USER,
        "updated_by": AUDIT_USER,
    }


RULES = [
    # =====================================================================
    # 1. ORGANIZATION — is_active vs is_deleted, site scoping
    # =====================================================================
    rule(
        "is_active_vs_is_deleted", "business_rule", "operations",
        "is_active hides from view; is_deleted removes permanently",
        "is_active = false hides a record from dropdowns and new data entry but keeps it visible in "
        "historical reports. It can be reactivated at any time. is_deleted = true is a permanent soft "
        "delete — the record is excluded from all queries and cannot be restored through the UI. "
        "Deactivating a parent cascades is_active to lookup/config children only (e.g. deactivating a "
        "site deactivates its child sites and equipment). Transactional records (POs, payroll, results) "
        "are never cascaded. Reactivating a parent does not auto-reactivate children.",
        None,
        '[]',
        1,
    ),
    rule(
        "site_farm_scope", "business_rule", "operations",
        "Site farm scope",
        "Sites can be org-wide (farm_name null) or farm-scoped. Child sites inherit farm_name from parent.",
        None,
        '["org_site.farm_name", "org_site.site_id_parent"]',
        2,
    ),
    rule(
        "site_zone_classification", "business_rule", "operations",
        "Site zone classification for food safety",
        "zone field (zone_1 through zone_4, water) is used for EMP testing site selection. "
        "zone_1 = food contact surfaces.",
        None,
        '["org_site.zone"]',
        3,
    ),

    # =====================================================================
    # 2. HR — employees, payroll
    # =====================================================================
    rule(
        "hr_access_level_filtering", "business_rule", "human_resources",
        "Supervisory role filtering by access level",
        "Team lead dropdown: sys_access_level_name >= team_lead. "
        "Compensation manager dropdown: sys_access_level_name >= manager.",
        None,
        '["hr_employee.team_lead_id", "hr_employee.compensation_manager_id"]',
        4,
    ),
    rule(
        "hr_payroll_import_process", "workflow", "human_resources",
        "Payroll import from external processor",
        "Excel file from payroll company with tabs: $data, Hours, NetPay, PTOBank, WC, TDI. "
        "Import matches by payroll_id and snapshots department, work auth, wc, pay structure, "
        "and OT threshold from hr_employee at import time.",
        None,
        '["hr_payroll"]',
        5,
    ),
    rule(
        "hr_payroll_cost_allocation", "calculation", "human_resources",
        "Payroll cost allocation by scheduled task",
        "Actual payroll costs distributed across tasks using planned schedule hours as the ratio. "
        "If no schedule exists, full cost bucketed to employee's department.",
        None,
        '["hr_payroll", "ops_task_schedule", "ops_task"]',
        6,
    ),

    # =====================================================================
    # 3. INVENTORY — POs, lots, receiving
    # =====================================================================
    rule(
        "invnt_lot_auto_deactivate", "workflow", "inventory",
        "Lot auto-deactivation on zero onhand",
        "When latest onhand_quantity = 0, lot is_active auto-set to false. Hidden from dropdowns "
        "but can be manually reactivated.",
        None,
        '["invnt_lot.is_active", "invnt_onhand.onhand_quantity"]',
        7,
    ),
    rule(
        "invnt_auto_reorder", "workflow", "inventory",
        "Auto-create PO on low stock",
        "When latest onhand falls below reorder_point_in_burn, a new invnt_po is auto-created.",
        None,
        '["invnt_onhand.onhand_quantity", "invnt_item.reorder_point_in_burn", "invnt_po"]',
        8,
    ),
    rule(
        "invnt_po_request_types", "business_rule", "inventory",
        "PO field behavior by request type",
        "inventory_item: invnt_item_id required, category/name/UOM/vendor auto-filled from item. "
        "non_inventory_item: invnt_item_id hidden, user enters category/name/UOM manually.",
        None,
        '["invnt_po.request_type", "invnt_po.invnt_item_id"]',
        9,
    ),
    rule(
        "invnt_po_snapshot_at_order", "business_rule", "inventory",
        "PO snapshots item_name, UOMs, and cost at order time",
        "Immutable once ordered — PO history unaffected if item record changes later.",
        None,
        '["invnt_po.item_name", "invnt_po.burn_uom", "invnt_po.order_uom", "invnt_po.total_cost"]',
        10,
    ),
    rule(
        "invnt_receiving_quality_checks", "business_rule", "inventory",
        "Food safety delivery checks live on invnt_po_received",
        "fsafe_delivery_truck_clean and fsafe_delivery_acceptable are per-delivery, not per-activity, "
        "so they live on the receiving record rather than in an ops_template checklist.",
        None,
        '["invnt_po_received.fsafe_delivery_truck_clean", "invnt_po_received.fsafe_delivery_acceptable"]',
        11,
    ),

    # =====================================================================
    # 4. OPERATIONS — task tracker, templates, checklists
    # =====================================================================
    rule(
        "ops_question_immutable_after_use", "business_rule", "operations",
        "Template questions locked once results exist",
        "question_text, response_type, and pass/fail settings are immutable after first result is recorded. "
        "To change, soft-delete the question and create a new one.",
        "Past results must match the question that was actually asked.",
        '["ops_template_question"]',
        12,
    ),
    rule(
        "ops_template_auto_load", "workflow", "operations",
        "Templates auto-load when task is selected",
        "All templates linked via ops_task_template load as checklists for the activity session.",
        None,
        '["ops_task_template.ops_task_name", "ops_task_template.ops_template_id"]',
        13,
    ),
    rule(
        "ops_corrective_action_auto_create", "workflow", "operations",
        "Auto-create corrective action on required checklist failure",
        "Required question fails (boolean != pass, numeric out of range, enum not in pass options) "
        "auto-create ops_corrective_action_taken. Non-required fails are flagged only.",
        None,
        '["ops_template_result", "ops_corrective_action_taken"]',
        14,
    ),
    rule(
        "ops_quick_fill", "workflow", "operations",
        "Quick-fill creates implicit activity",
        "Submitting a checklist without a pre-created activity silently creates one with "
        "start_time = stop_time = now, is_completed = true.",
        None,
        '["ops_task_tracker"]',
        15,
    ),
    rule(
        "ops_schedule_dual_mode", "business_rule", "operations",
        "Schedule: real-time vs planned mode",
        "Real-time: ops_task_tracker_id set, times inherited from tracker. "
        "Planned: ops_task_tracker_id null, manager assigns employees to future time slots.",
        None,
        '["ops_task_schedule.ops_task_tracker_id"]',
        16,
    ),
    rule(
        "ops_planned_schedule_workflow", "workflow", "operations",
        "Weekly schedule copy-and-edit workflow",
        "Generate next week by copying current week. Edit in place — move employees between tasks, "
        "reassign time slots, soft-delete. Printable via ops_task_weekly_schedule view.",
        None,
        '["ops_task_schedule", "ops_task_weekly_schedule"]',
        17,
    ),

    # =====================================================================
    # 5. GROW — seeding through harvest
    # =====================================================================
    rule(
        "grow_site_scope", "business_rule", "grow",
        "Growing activities limited to greenhouse, pond, nursery sites",
        "Site dropdown filtered by farm_name then by subcategory IN (greenhouse, pond, nursery). "
        "Parent sites, growing_room, growing_other excluded.",
        None,
        '["grow_lettuce_seed_batch.site_id", "grow_cuke_seed_batch.site_id"]',
        18,
    ),
    rule(
        "grow_seed_batch_lifecycle", "workflow", "grow",
        "Seed batch status lifecycle",
        "planned -> seeded -> transplanted -> harvesting -> harvested. "
        "Nursery: available for activities at 'seeded'. Greenhouse/pond: at 'transplanted' or 'harvesting'.",
        None,
        '["grow_lettuce_seed_batch.status", "grow_cuke_seed_batch.status"]',
        19,
    ),
    rule(
        "grow_seeding_label_format", "business_rule", "grow",
        "Seeding label generation",
        "Labels show site+side, S#/B#, three MMdd dates (S/P/H), variety:seed. "
        "Boards > 90 split into balanced chunks. Color: blue Fri/Sun, yellow Sat/Mon.",
        None,
        '["grow_lettuce_seed_batch", "grow_cuke_seed_batch"]',
        20,
    ),
    rule(
        "grow_spray_compliance_filter", "business_rule", "grow",
        "Spray compliance: only active chemicals, rate-limited per acre",
        "Only invnt_category = chemicals_pesticides with valid effective_date shown. "
        "Blocked if quantity x acres > maximum_quantity_per_acre.",
        None,
        '["grow_spray_compliance.effective_date", "grow_spray_compliance.maximum_quantity_per_acre"]',
        21,
    ),
    rule(
        "grow_safety_interval", "calculation", "grow",
        "PHI/REI: most restrictive interval governs the spray event",
        "Max PHI days across all inputs = earliest harvest date. Max REI hours = earliest re-entry.",
        None,
        '["grow_spray_compliance.phi_days", "grow_spray_compliance.rei_hours"]',
        22,
    ),
    rule(
        "grow_monitoring_out_of_range", "business_rule", "grow",
        "Monitoring: auto-flag out-of-range, corrective action if required",
        "Readings outside min/max or not in enum_pass_options flagged. "
        "is_required = true triggers corrective action; non-required is informational.",
        None,
        '["grow_monitoring_result", "grow_monitoring_metric.is_required"]',
        23,
    ),

    # =====================================================================
    # 6. PACK — productivity, shelf life, dryer
    # =====================================================================
    rule(
        "pack_productivity_workflow", "workflow", "pack",
        "One activity per product, hourly snapshots",
        "Supervisor creates ops_task_tracker per product (sales_product_id). Records pack_productivity_hour "
        "each clock hour with crew counts, cases packed, fails. Multiple products can overlap in the same "
        "hour under different activities. When product finishes, stop_time set, new activity for next product.",
        None,
        '["ops_task_tracker.sales_product_id", "pack_productivity_hour.ops_task_tracker_id"]',
        24,
    ),
    rule(
        "pack_productivity_derived_metrics", "calculation", "pack",
        "Productivity: trays, trays/packer/min, packed pounds derived on-the-fly",
        "trays = cases_packed x pack_per_case. pounds = cases_packed x case_net_weight.",
        None,
        '["pack_productivity_hour.cases_packed"]',
        25,
    ),
    rule(
        "pack_metal_detection", "business_rule", "pack",
        "Metal detection timestamp per packing hour",
        "fsafe_metal_detected_at records when the check happened. Non-null = performed; null = not performed. "
        "Lives on hourly snapshot (not checklist) because it's recorded every hour.",
        None,
        '["pack_productivity_hour.fsafe_metal_detected_at"]',
        26,
    ),
    rule(
        "pack_invnt_item_filters", "business_rule", "pack",
        "invnt_item_id filtered by context: Packing vs Seeds",
        "sales_product.invnt_item_id: filtered to category Packing (packaging material). "
        "pack_dryer_result.invnt_item_id: filtered to category Seeds (seed variety being dried).",
        None,
        '["sales_product.invnt_item_id", "pack_dryer_result.invnt_item_id"]',
        27,
    ),
    rule(
        "pack_dryer_recheck", "workflow", "pack",
        "Dryer re-check via self-referencing FK",
        "New row with pack_dryer_result_id_original pointing to original. tracking_code is the "
        "human-readable ID for the original check. Re-checks inherit batch and site.",
        None,
        '["pack_dryer_result.pack_dryer_result_id_original", "pack_dryer_result.tracking_code"]',
        28,
    ),
    rule(
        "pack_shelf_life_experimental", "business_rule", "pack",
        "Shelf life trials: sales_product_id nullable for experiments",
        "When null, the trial tests a new variety or packaging not yet in the catalog. "
        "trial_purpose captures the intent.",
        None,
        '["pack_shelf_life.sales_product_id", "pack_shelf_life.trial_purpose"]',
        29,
    ),
    rule(
        "pack_fail_categories", "business_rule", "pack",
        "Fail categories: only 'total' active, granular categories retired",
        "Historical data uses film/tray/printer/leaves/ridges/unexplained (is_active = false). "
        "Current data uses total only.",
        None,
        '["pack_productivity_fail_category.is_active"]',
        30,
    ),

    # =====================================================================
    # 7. SALES — POs, pricing, fulfillment, palletization
    # =====================================================================
    rule(
        "sales_po_farm_on_line", "business_rule", "sales",
        "Farm lives on PO line, not PO header",
        "One PO can contain products from multiple farms. farm_name inherited from sales_product.",
        None,
        '["sales_po_line.farm_name"]',
        31,
    ),
    rule(
        "sales_po_lifecycle", "workflow", "sales",
        "PO lifecycle: draft -> approved -> fulfilled/unfulfilled",
        "unfulfilled = product unavailable (not cancelled). past_due auto-set when order_date passes. "
        "Recurring POs (recurring_frequency set) auto-create next order on fulfillment.",
        None,
        '["sales_po.status", "sales_po.recurring_frequency"]',
        32,
    ),
    rule(
        "sales_po_snapshot_pricing", "business_rule", "sales",
        "price_per_case snapshot at order time",
        "Resolution: customer-specific price -> customer group price -> default FOB price. "
        "Immutable after order creation.",
        None,
        '["sales_po_line.price_per_case", "sales_product_price.price_per_case"]',
        33,
    ),
    rule(
        "sales_palletization", "workflow", "sales",
        "Palletization: capacity-aware pallet expansion",
        "Lines expanded into pallets using pallet_ti x pallet_hi (max = maximum_case_per_pallet). "
        "Pallet types: Full, Stackable (Costco/Sam's partials), Shareable (other partials). "
        "Off-island only (FOB != Farm/Local Delivery).",
        None,
        '["sales_po_line", "sales_product.pallet_ti", "sales_product.pallet_hi"]',
        34,
    ),
    rule(
        "sales_containerization", "workflow", "sales",
        "Container assignment with spillover",
        "Pallets assigned to container spaces by type (org-level, selected by product farm). "
        "Overflow spills into other container types. container_id, booking_id, pallet_number, "
        "container_space bulk-written to sales_po_fulfillment filtered by invoice date.",
        None,
        '["sales_po_fulfillment", "sales_container_type"]',
        35,
    ),
    rule(
        "sales_print_documents", "business_rule", "sales",
        "Pallet print documents: envelopes, pallet papers, ASN labels",
        "Sorted by container type (cuke -> box -> lettuce), then by space, spillover last.",
        None,
        '["sales_po_line"]',
        36,
    ),

    # =====================================================================
    # 7b. SALES CRM — store visits, market intelligence
    # =====================================================================
    rule(
        "sales_crm_store_customer_link", "business_rule", "sales",
        "Store links to customer but many stores can share one customer",
        "sales_crm_store.sales_customer_id is nullable. Multiple stores can reference the same "
        "customer (e.g. all Costco locations link to the Costco customer for that island). "
        "Stores without a customer link are tracked for competitive intelligence only.",
        None,
        '["sales_crm_store.sales_customer_id"]',
        37,
    ),
    rule(
        "sales_crm_visit_result_product_exclusivity", "business_rule", "sales",
        "Visit observation: own product or competitor, never both",
        "Each sales_crm_store_visit_result row references either sales_product_id (own product) "
        "or sales_crm_external_product_name (competitor), enforced by CHECK constraint. "
        "This allows comparing own vs competitor shelf presence, pricing, and stock in the same query.",
        None,
        '["sales_crm_store_visit_result.sales_product_id", '
        '"sales_crm_store_visit_result.sales_crm_external_product_name"]',
        38,
    ),

    # =====================================================================
    # 8. FOOD SAFETY — testing, results
    # =====================================================================
    rule(
        "fsafe_test_pass_fail", "business_rule", "food_safety",
        "Pass/fail criteria by test type",
        "Enum: pass when response in enum_pass_options. Numeric: pass within min/max. "
        "ATP: randomly select atp_site_count zone_1 sites.",
        None,
        '["fsafe_lab_test.enum_pass_options", "fsafe_lab_test.minimum_value", "fsafe_lab_test.maximum_value"]',
        39,
    ),
    rule(
        "fsafe_retest_auto_create", "workflow", "food_safety",
        "Auto-create retest/vector on failure",
        "Failed initial test auto-creates retest and vector results based on lab test config.",
        None,
        '["fsafe_result", "fsafe_lab_test.requires_retest", "fsafe_lab_test.requires_vector_test"]',
        40,
    ),

    # =====================================================================
    # 9. MAINTENANCE — requests
    # =====================================================================
    rule(
        "maint_preventive_recurrence", "workflow", "maintenance",
        "Auto-create next request on completion of recurring maintenance",
        "When recurring_frequency is set and status = done, a new request is auto-created.",
        None,
        '["maint_request.recurring_frequency", "maint_request.status"]',
        41,
    ),

    # =====================================================================
    # 10. AUTH — sign-in auto-link to hr_employee
    # =====================================================================
    rule(
        "auth_auto_link_employee", "workflow", "human_resources",
        "Auto-link auth.users to hr_employee on first sign-in",
        "When a user signs in for the first time (Google OAuth or email/password), Supabase creates "
        "a row in auth.users. A database trigger (on_auth_user_created) fires AFTER INSERT and matches "
        "auth.users.email against hr_employee.company_email. If a match is found and user_id is NULL, "
        "it sets hr_employee.user_id = auth.users.id for ALL matching rows (supporting multi-org "
        "employees). RLS policies then use auth.uid() = hr_employee.user_id to grant org-scoped access. "
        "If no hr_employee has a matching company_email, the user authenticates but has no org membership "
        "and sees a 'no access' page. Prerequisites: (1) hr_employee must be populated with company_email "
        "before the employee signs in, (2) enable_signup = true in supabase/config.toml, (3) Google OAuth "
        "client ID/secret configured in config.toml under [auth.external.google]. "
        "Trigger: public.handle_new_auth_user() — SECURITY DEFINER. "
        "Migration: supabase/migrations/20260401000141_auth_auto_link_employee.sql.",
        "Eliminates manual auth.users seeding. Employees are managed in hr_employee only — the auth "
        "layer links automatically on first login.",
        '["auth.users", "hr_employee.company_email", "hr_employee.user_id"]',
        42,
    ),

    # =====================================================================
    # 11. GROW — harvest tare calculation
    # =====================================================================
    rule(
        "grow_harvest_tare_calculation", "calculation", "grow",
        "Harvest tare: formula-based or fixed per container",
        "When grow_harvest_container.is_tare_calculated = true, tare is computed from tare_formula "
        "using gross_weight as the input variable (linear regression per variety+grade for cuke pallets). "
        "When false, tare = fixed tare_weight x number_of_containers. "
        "Net weight = gross_weight - tare. "
        "Cuke pallet formulas use ROUND(slope * gross_weight + intercept) * 3 + offset, "
        "where the coefficients vary by variety and grade. Grade 1 (on-grade) adds a +48 offset; "
        "grade 2 (off-grade) does not. J and E share identical coefficients; K has its own.",
        "Legacy tare calculation is weight-dependent (heavier pallets have proportionally more container "
        "material). A single fixed tare_weight per container cannot express this, so the formula column "
        "follows the same pattern as grow_monitoring_metric.formula.",
        '["grow_harvest_container.tare_formula", "grow_harvest_container.is_tare_calculated", '
        '"grow_harvest_weight.gross_weight", "grow_harvest_weight.net_weight"]',
        43,
    ),
    rule(
        "grow_scouting_site_hierarchy", "business_rule", "grow",
        "Scouting: task site vs. observation site (two-tier hierarchy)",
        "A scouting event is organized around a primary site (greenhouse or pond — e.g. 'gh', '01', 'hi', 'p4') "
        "recorded on ops_task_tracker.site_id. Within that primary site, the scout walks and inspects specific "
        "sub-locations (yellow card monitoring cards, growing rows, bag numbers, etc.). Each pest or disease "
        "finding is recorded as a grow_scout_result row whose site_id points to the specific sub-site where "
        "the observation was made (org_site with a narrower category like 'row' or a monitoring station). "
        "When the sub-site granularity is unavailable (legacy data, aggregate observations), "
        "grow_scout_result.site_id stays NULL and the broader location is inferred from the tracker.",
        "Mirrors how scouting actually works in the field: one task per greenhouse/pond, many distinct "
        "observations across different spots within it. Keeping the two levels separate lets us aggregate "
        "findings by primary site while preserving the granularity of where each observation was made.",
        '["ops_task_tracker.site_id", "grow_scout_result.site_id", "org_site"]',
        44,
    ),
]


def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())

    # Clear existing rules
    print("Clearing tables...")
    try:
        supabase.table("org_business_rule").delete().neq("id", "___never___").execute()
        print("  All cleared")
    except Exception as e:
        # If clearing fails, we still proceed with the insert below — it may
        # error on duplicate keys, which the user should see. Log the reason.
        print(f"  Could not clear org_business_rule: {type(e).__name__}: {e}")
        print("  Proceeding with insert; duplicate keys may cause errors below.")

    # Insert rules in batches.
    # NOTE: PostgREST does not support multi-statement transactions, so each
    # batch is committed independently. If a batch fails mid-way through, all
    # earlier batches remain in the database. This script is rerunnable —
    # re-running clears and reinserts all data, so partial failures recover by
    # fixing the underlying issue and running the script again.
    print(f"\n--- org_business_rule ---")
    total_batches = (len(RULES) + 99) // 100
    inserted = 0
    for i in range(0, len(RULES), 100):
        batch = RULES[i:i + 100]
        batch_num = (i // 100) + 1
        try:
            supabase.table("org_business_rule").insert(batch).execute()
            inserted += len(batch)
        except Exception as e:
            print(
                f"  ERROR on batch {batch_num}/{total_batches} "
                f"(rows {i + 1}-{i + len(batch)}): {type(e).__name__}: {e}"
            )
            print(f"  {inserted} rows committed before failure")
            print(f"  Re-run the script to retry — it is idempotent.")
            raise
    print(f"  Inserted {len(RULES)} rules")

    # Summary by module
    modules = {}
    for r in RULES:
        m = r["module"]
        modules[m] = modules.get(m, 0) + 1
    for m, c in sorted(modules.items()):
        print(f"    {m}: {c}")

    print("\nOrg business rules migrated successfully")


if __name__ == "__main__":
    main()
