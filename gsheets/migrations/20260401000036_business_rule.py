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
        "is_active_vs_is_deleted", "Business Rule", "operations",
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
        "site_farm_scope", "Business Rule", "operations",
        "Site farm scope",
        "Sites can be org-wide (farm_id null) or farm-scoped. Child sites inherit farm_id from parent.",
        None,
        '["org_site.farm_id", "org_site.site_id_parent"]',
        2,
    ),
    rule(
        "site_zone_classification", "Business Rule", "operations",
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
        "hr_access_level_filtering", "Business Rule", "human_resources",
        "Supervisory role filtering by access level",
        "Team lead dropdown: sys_access_level_id >= team_lead. "
        "Compensation manager dropdown: sys_access_level_id >= manager.",
        None,
        '["hr_employee.team_lead_id", "hr_employee.compensation_manager_id"]',
        4,
    ),
    rule(
        "hr_payroll_import_process", "Workflow", "human_resources",
        "Payroll import from external processor",
        "Excel file from payroll company with tabs: $data, Hours, NetPay, PTOBank, WC, TDI. "
        "Import matches by payroll_id and snapshots department, work auth, wc, pay structure, "
        "and OT threshold from hr_employee at import time.",
        None,
        '["hr_payroll"]',
        5,
    ),
    rule(
        "hr_payroll_cost_allocation", "Calculation", "human_resources",
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
        "invnt_lot_auto_deactivate", "Workflow", "inventory",
        "Lot auto-deactivation on zero onhand",
        "When latest onhand_quantity = 0, lot is_active auto-set to false. Hidden from dropdowns "
        "but can be manually reactivated.",
        None,
        '["invnt_lot.is_active", "invnt_onhand.onhand_quantity"]',
        7,
    ),
    rule(
        "invnt_auto_reorder", "Workflow", "inventory",
        "Auto-create PO on low stock",
        "When latest onhand falls below reorder_point_in_burn, a new invnt_po is auto-created.",
        None,
        '["invnt_onhand.onhand_quantity", "invnt_item.reorder_point_in_burn", "invnt_po"]',
        8,
    ),
    rule(
        "invnt_po_request_types", "Business Rule", "inventory",
        "PO field behavior by request type",
        "inventory_item: invnt_item_id required, category/name/UOM/vendor auto-filled from item. "
        "non_inventory_item: invnt_item_id hidden, user enters category/name/UOM manually.",
        None,
        '["invnt_po.request_type", "invnt_po.invnt_item_id"]',
        9,
    ),
    rule(
        "invnt_po_snapshot_at_order", "Business Rule", "inventory",
        "PO snapshots item_name, UOMs, and cost at order time",
        "Immutable once ordered — PO history unaffected if item record changes later.",
        None,
        '["invnt_po.item_name", "invnt_po.burn_uom", "invnt_po.order_uom", "invnt_po.total_cost"]',
        10,
    ),
    rule(
        "invnt_receiving_quality_checks", "Business Rule", "inventory",
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
        "ops_question_immutable_after_use", "Business Rule", "operations",
        "Template questions locked once results exist",
        "question_text, response_type, and pass/fail settings are immutable after first result is recorded. "
        "To change, soft-delete the question and create a new one.",
        "Past results must match the question that was actually asked.",
        '["ops_template_question"]',
        12,
    ),
    rule(
        "ops_template_auto_load", "Workflow", "operations",
        "Templates auto-load when task is selected",
        "All templates linked via ops_task_template load as checklists for the activity session.",
        None,
        '["ops_task_template.ops_task_id", "ops_task_template.ops_template_id"]',
        13,
    ),
    rule(
        "ops_corrective_action_auto_create", "Workflow", "operations",
        "Auto-create corrective action on required checklist failure",
        "Required question fails (boolean != pass, numeric out of range, enum not in pass options) "
        "auto-create ops_corrective_action_taken. Non-required fails are flagged only.",
        None,
        '["ops_template_result", "ops_corrective_action_taken"]',
        14,
    ),
    rule(
        "ops_quick_fill", "Workflow", "operations",
        "Quick-fill creates implicit activity",
        "Submitting a checklist without a pre-created activity silently creates one with "
        "start_time = stop_time = now, is_completed = true.",
        None,
        '["ops_task_tracker"]',
        15,
    ),
    rule(
        "ops_schedule_dual_mode", "Business Rule", "operations",
        "Schedule: real-time vs planned mode",
        "Real-time: ops_task_tracker_id set, times inherited from tracker. "
        "Planned: ops_task_tracker_id null, manager assigns employees to future time slots.",
        None,
        '["ops_task_schedule.ops_task_tracker_id"]',
        16,
    ),
    rule(
        "ops_planned_schedule_workflow", "Workflow", "operations",
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
        "grow_site_scope", "Business Rule", "grow",
        "Growing activities limited to greenhouse, pond, nursery sites",
        "Site dropdown filtered by farm_id then by subcategory IN (greenhouse, pond, nursery). "
        "Parent sites, growing_room, growing_other excluded.",
        None,
        '["grow_lettuce_seed_batch.site_id", "grow_cuke_seed_batch.site_id"]',
        18,
    ),
    rule(
        "grow_seed_batch_lifecycle", "Workflow", "grow",
        "Seed batch status lifecycle",
        "planned -> seeded -> transplanted -> harvesting -> harvested. "
        "Nursery: available for activities at 'seeded'. Greenhouse/pond: at 'transplanted' or 'harvesting'.",
        None,
        '["grow_lettuce_seed_batch.status", "grow_cuke_seed_batch.status"]',
        19,
    ),
    rule(
        "grow_seeding_label_format", "Business Rule", "grow",
        "Seeding label generation",
        "Labels show site+side, S#/B#, three MMdd dates (S/P/H), variety:seed. "
        "Boards > 90 split into balanced chunks. Color: blue Fri/Sun, yellow Sat/Mon.",
        None,
        '["grow_lettuce_seed_batch", "grow_cuke_seed_batch"]',
        20,
    ),
    rule(
        "grow_spray_compliance_filter", "Business Rule", "grow",
        "Spray compliance: only active chemicals, rate-limited per acre",
        "Only invnt_category = chemicals_pesticides with valid effective_date shown. "
        "Blocked if quantity x acres > maximum_quantity_per_acre.",
        None,
        '["grow_spray_compliance.effective_date", "grow_spray_compliance.maximum_quantity_per_acre"]',
        21,
    ),
    rule(
        "grow_safety_interval", "Calculation", "grow",
        "PHI/REI: most restrictive interval governs the spray event",
        "Max PHI days across all inputs = earliest harvest date. Max REI hours = earliest re-entry.",
        None,
        '["grow_spray_compliance.phi_days", "grow_spray_compliance.rei_hours"]',
        22,
    ),
    rule(
        "grow_monitoring_out_of_range", "Business Rule", "grow",
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
        "pack_productivity_workflow", "Workflow", "pack",
        "One activity per product, hourly snapshots",
        "Supervisor creates ops_task_tracker per product (sales_product_id). Records pack_productivity_hour "
        "each clock hour with crew counts, cases packed, fails. Multiple products can overlap in the same "
        "hour under different activities. When product finishes, stop_time set, new activity for next product.",
        None,
        '["ops_task_tracker.sales_product_id", "pack_productivity_hour.ops_task_tracker_id"]',
        24,
    ),
    rule(
        "pack_productivity_derived_metrics", "Calculation", "pack",
        "Productivity: trays, trays/packer/min, packed pounds derived on-the-fly",
        "trays = cases_packed x pack_per_case. pounds = cases_packed x case_net_weight.",
        None,
        '["pack_productivity_hour.cases_packed"]',
        25,
    ),
    rule(
        "pack_metal_detection", "Business Rule", "pack",
        "Metal detection timestamp per packing hour",
        "fsafe_metal_detected_at records when the check happened. Non-null = performed; null = not performed. "
        "Lives on hourly snapshot (not checklist) because it's recorded every hour.",
        None,
        '["pack_productivity_hour.fsafe_metal_detected_at"]',
        26,
    ),
    rule(
        "pack_invnt_item_filters", "Business Rule", "pack",
        "invnt_item_id filtered by context: Packing vs Seeds",
        "sales_product.invnt_item_id: filtered to category Packing (packaging material). "
        "pack_dryer_result.invnt_item_id: filtered to category Seeds (seed variety being dried).",
        None,
        '["sales_product.invnt_item_id", "pack_dryer_result.invnt_item_id"]',
        27,
    ),
    rule(
        "pack_dryer_recheck", "Workflow", "pack",
        "Dryer re-check via self-referencing FK",
        "New row with pack_dryer_result_id_original pointing to original. tracking_code is the "
        "human-readable ID for the original check. Re-checks inherit batch and site.",
        None,
        '["pack_dryer_result.pack_dryer_result_id_original", "pack_dryer_result.tracking_code"]',
        28,
    ),
    rule(
        "pack_shelf_life_experimental", "Business Rule", "pack",
        "Shelf life trials: sales_product_id nullable for experiments",
        "When null, the trial tests a new variety or packaging not yet in the catalog. "
        "trial_purpose captures the intent.",
        None,
        '["pack_shelf_life.sales_product_id", "pack_shelf_life.trial_purpose"]',
        29,
    ),
    rule(
        "pack_fail_categories", "Business Rule", "pack",
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
        "sales_po_farm_on_line", "Business Rule", "sales",
        "Farm lives on PO line, not PO header",
        "One PO can contain products from multiple farms. farm_id inherited from sales_product.",
        None,
        '["sales_po_line.farm_id"]',
        31,
    ),
    rule(
        "sales_po_lifecycle", "Workflow", "sales",
        "PO lifecycle: draft -> approved -> fulfilled/unfulfilled",
        "unfulfilled = product unavailable (not cancelled). past_due auto-set when order_date passes. "
        "Recurring POs (recurring_frequency set) auto-create next order on fulfillment.",
        None,
        '["sales_po.status", "sales_po.recurring_frequency"]',
        32,
    ),
    rule(
        "sales_po_snapshot_pricing", "Business Rule", "sales",
        "price_per_case snapshot at order time",
        "Resolution: customer-specific price -> customer group price -> default FOB price. "
        "Immutable after order creation.",
        None,
        '["sales_po_line.price_per_case", "sales_product_price.price_per_case"]',
        33,
    ),
    rule(
        "sales_pallet_workflow", "Workflow", "sales",
        "Pallet workflow: Palletize -> Stack -> Containerize -> Lock",
        "Three-step user-driven shipping prep, scoped per (farm, target_invoice_date). "
        "1. Palletize: app code expands fulfillment lines into sales_pallet rows, sets pallet_type "
        "(Full / Shareable / Stackable) and capacity_utilization, assigns pallet_number "
        "(CP/LP/BP prefix per container family). 2. Stack: app code assigns container_space_number "
        "to non-Full pallets; user can drag stackable pallets between spaces in the UI. "
        "3. Containerize: app code sets sales_shipment_container_id and marks is_spillover where "
        "cucumber pallets overflow into the lettuce or box-truck container. After finalization the "
        "operator bulk-locks (is_locked=true) so subsequent regenerations preserve manual edits. "
        "Off-island only (FOB != Farm/Local Delivery). Bin-packing logic lives in app code; the DB "
        "is a passive store.",
        "Operators need to manually adjust pallet groupings between auto-generation steps "
        "(combine shareables, restack partials, override spillover targets); locking after each "
        "completed run lets new POs be palletized without disturbing settled assignments.",
        '["sales_pallet", "sales_pallet_allocation", "sales_po_fulfillment"]',
        34,
    ),
    rule(
        "sales_pallet_capacity_expansion", "Calculation", "sales",
        "Capacity-aware pallet expansion across pack dates",
        "Group fulfillments by (customer_name, po_number, product_code) and walk pack dates oldest "
        "first. Pack onto a pallet up to sales_product.maximum_case_per_pallet (max). Crossing the "
        "sales_product full_pallet labeling threshold does NOT close the pallet — it stays open and "
        "accepts top-offs from later pack dates until physically at max. At close time, label as "
        "'Full' if running >= full_pallet, else 'Stackable' (Costco/Sam's customer groups) or "
        "'Shareable_{customer_name}' (others). Capacity_utilization = take/max stored as 0..1 fraction.",
        "Earlier wipe-and-split-on-full produced fragmented pallets (e.g. 55 cases on 4/25 + "
        "5 cases on 4/26 became CP03 Full 83% and CP04 Stackable 7%); top-off across dates yields "
        "one consolidated 60-case Full pallet instead.",
        '["sales_pallet.capacity_utilization", "sales_pallet.pallet_type", '
        '"sales_product.full_pallet", "sales_product.maximum_case_per_pallet"]',
        35,
    ),
    rule(
        "sales_pallet_costco_smart_split", "Calculation", "sales",
        "Costco KW/JW smart split for 84/78/72 case quantities",
        "When a fresh pallet is being opened for Costco group with product_code in (KW, JW) and "
        "remaining qty is exactly 84, 78, or 72, take 60 cases (or 54 for qty=72) on this pallet "
        "and force-close so the next pallet starts fresh. Produces a balanced split (84 -> 60+24 "
        "rather than 66+18) that matches Costco's preferred receiving layout. The force-close "
        "prevents later top-offs from undoing the intentional split.",
        "Costco's DC pickers prefer balanced partial pallets; the 60+24 split fits their cart "
        "layout better than 66+18.",
        '["sales_pallet.pallet_type", "sales_po_line.sales_product_id"]',
        36,
    ),
    rule(
        "sales_container_spillover", "Calculation", "sales",
        "Cucumber -> lettuce -> box-truck spillover when over capacity",
        "Each sales_container_type carries maximum_spaces (cucumber=18, lettuce=18, box=10). "
        "Final container assignment runs Cucumber first, then Lettuce, then Box. If cucumber "
        "spaces in use exceed cucumber.maximum_spaces, mark the highest-numbered cucumber spaces "
        "as spillover and reassign their pallets to the lettuce container, taking lettuce's open "
        "spaces. If lettuce overflows too, spill remaining pallets into the box-truck container. "
        "Spillover pallets get is_spillover=true and a re-numbered container_space_number under "
        "the destination container. ALL pallets sharing a pallet_number with a spillover row "
        "follow it to the new container (atomic move).",
        "Loading crew expects whole pallets to stay together physically; splitting a pallet's "
        "rows across two containers would require the same product to be packed in two different "
        "trucks/containers.",
        '["sales_pallet.is_spillover", "sales_pallet.sales_shipment_container_id", '
        '"sales_container_type.maximum_spaces"]',
        37,
    ),
    rule(
        "sales_pallet_locking", "Business Rule", "sales",
        "Locked pallets are preserved across regeneration",
        "When operators bulk-lock a finalized run (is_locked=true on every sales_pallet row in "
        "scope), subsequent re-runs of Palletize/Stack/Containerize for the same "
        "(farm, target_invoice_date) skip locked pallets and their allocations. Only unlocked "
        "rows are wiped and rebuilt. New POs added after lock-in get folded into freshly created "
        "pallets without disturbing the locked assignments. Operators can unlock individual "
        "pallets if a manual edit is needed.",
        "Pallet/space assignments accrete real-world meaning (printed pallet papers, ASN labels, "
        "operator memory of which space holds what) once shared with the warehouse; regenerating "
        "from scratch each time would invalidate downstream artifacts.",
        '["sales_pallet.is_locked"]',
        38,
    ),
    rule(
        "sales_print_documents", "Business Rule", "sales",
        "Pallet print documents: envelopes, pallet papers, ASN labels",
        "Sorted by container type (cuke -> box -> lettuce), then by space, spillover last.",
        None,
        '["sales_pallet", "sales_pallet_allocation"]',
        39,
    ),

    # =====================================================================
    # 7c. SALES SPS / EDI — Costco / Safeway / etc. document exchange
    # =====================================================================
    rule(
        "sps_trading_partner_setup", "Business Rule", "sales",
        "Three records required before any inbound 850 will resolve",
        "Onboarding a new SPS buyer requires (1) a sales_customer row, (2) a sales_trading_partner "
        "row bridging sps_partner_id to that customer with the asn_required / invoice_required / "
        "acknowledgement_required flags set per the partner's contract, and (3) one "
        "sales_product_buyer_part row per (buyer, our product) pair mapping the buyer's SKU + "
        "case GTIN to our sales_product_id. Without all three in place, the inbound 850 parser "
        "fails at either the partner-routing step (unknown sps_partner_id) or the line-resolution "
        "step (unknown buyer_part_number).",
        "EDI documents arrive with the buyer's identifiers, not ours. The two lookup tables are "
        "the only way to translate them — and the data needs to exist before the first PO comes "
        "in or the parse fails and the 997 acknowledgement misses its 24h SLA.",
        '["sales_trading_partner", "sales_product_buyer_part", "sales_customer"]',
        40,
    ),
    rule(
        "sps_inbound_850_flow", "Workflow", "sales",
        "Inbound 850 PO ingestion -> parse -> ack",
        "1. Worker receives 850 via SPS SFTP / API, writes raw payload to sales_edi_inbound_message "
        "with document_type='850' and parsed_at NULL. 2. Parser looks up sales_trading_partner "
        "by sps_partner_id from the envelope, creates one sales_po row with status='Received' "
        "and snapshot of all ship_to_*/bill_to_*/buyer_*/carrier_*/requested_*_date/"
        "payment_terms_net_days fields. 3. For each line, parser resolves sales_product_id via "
        "sales_product_buyer_part(sales_customer_id, buyer_part_number) and creates sales_po_line "
        "with the buyer_* snapshot. 4. On success: sets parsed_at + sales_po_id on the inbound "
        "message. On failure: leaves parsed_at NULL and records parse_error for replay. 5. Worker "
        "sends 997 Functional Acknowledgement to SPS within 24h, recording outcome on "
        "acknowledgement_status / acknowledgement_sent_at. 6. If sales_trading_partner."
        "acknowledgement_required = true, worker also sends 855 PO Acknowledgement and "
        "transitions sales_po.status to Acknowledged.",
        "Failed parses are recoverable: fix the missing sales_trading_partner or "
        "sales_product_buyer_part row, then re-process by setting parsed_at = NULL.",
        '["sales_edi_inbound_message", "sales_po.status", "sales_po.sales_trading_partner_id", '
        '"sales_po_line.buyer_part_number"]',
        41,
    ),
    rule(
        "sps_outbound_856_flow", "Workflow", "sales",
        "Outbound 856 ASN: shipment -> container -> ASN -> carton hierarchy",
        "Generated when sales_po.status transitions to Shipped AND "
        "sales_trading_partner.asn_required = true. Worker (1) finds or creates the sales_shipment "
        "row for this booking (carrier_scac, BOL, ship_date), (2) finds or creates the "
        "sales_shipment_container row for the physical container goods are loaded in, (3) inserts a "
        "sales_po_asn row referencing the container — the (sales_shipment_container_id, sales_po_id) "
        "UNIQUE constraint prevents duplicate ASNs, (4) inserts one sales_po_asn_carton row per "
        "physical case with its GS1 SSCC-18 barcode, optionally nested under a Tare-type pallet "
        "carton via parent_carton_id, (5) builds the 856 X12/XML by joining shipment + container + "
        "asn + cartons and transmits to SPS, recording sent_at + raw_outbound on the ASN. SPS "
        "returns a 997 within hours; worker updates acknowledged_at and sales_po_asn.status on receipt.",
        "Buyers (especially Costco) require ASN within ~1h of departure. Splitting the model into "
        "shipment/container/ASN/carton matches the EDI 856 HL hierarchy exactly so the message "
        "build is a direct join, not an aggregation.",
        '["sales_shipment", "sales_shipment_container", "sales_po_asn", "sales_po_asn_carton", '
        '"sales_trading_partner.asn_required"]',
        42,
    ),
    rule(
        "sps_outbound_810_flow", "Workflow", "sales",
        "Outbound 810 Invoice flow",
        "Triggered after the 856 is acknowledged AND sales_trading_partner.invoice_required = true "
        "(some retailers self-invoice from receipt and skip 810). Worker builds the 810 on demand "
        "from sales_po (header — po_number, payment_terms_net_days, bill_to_*) + sales_po_line "
        "(lines — buyer_part_number, buyer_line_sequence, gtin_case, price_per_case) + sales_po_asn "
        "-> sales_shipment_container -> sales_shipment (BOL reference). Transmits, then sets "
        "sales_po.status = Invoiced. The 810 is not persisted to its own table — re-rendering is "
        "deterministic from the source rows.",
        "Avoiding a separate 810 table keeps the schema simpler. Every field on the 810 is captured "
        "elsewhere on sales_po + lines + ASN, so re-render is safe.",
        '["sales_po.status", "sales_trading_partner.invoice_required", "sales_po_asn"]',
        43,
    ),
    rule(
        "sps_997_acknowledgement_sla", "Requirement", "sales",
        "24h Functional Acknowledgement SLA for inbound documents",
        "SPS partner contracts require a 997 Functional Acknowledgement transmitted within 24 hours "
        "of receiving any inbound document (850, 860, 870, etc.). The worker writes "
        "acknowledgement_status (Accepted / AcceptedWithErrors / Rejected) and "
        "acknowledgement_sent_at on the sales_edi_inbound_message row when the 997 leaves. Missing the "
        "SLA triggers SPS-side alerts and may put the partner relationship into compliance review.",
        "Hard contractual SLA, not negotiable — the 997 also signals to the buyer that we "
        "received their document so they can move on operationally.",
        '["sales_edi_inbound_message.acknowledgement_status", "sales_edi_inbound_message.acknowledgement_sent_at"]',
        44,
    ),
    rule(
        "sps_sscc_uniqueness", "Business Rule", "sales",
        "GS1 SSCC-18 carton labels are globally unique, never reused",
        "Every sales_po_asn_carton.sscc is a GS1 Serial Shipping Container Code (SSCC-18) printed "
        "as the UCC-128 barcode on the case. Per GS1 spec, an SSCC value must NEVER be reused — "
        "not even after a shipment is cancelled, returned, or voided. The uq_sales_po_asn_carton_sscc "
        "UNIQUE constraint enforces this. If the buyer scans an SSCC at receiving, it must match "
        "exactly one carton record in the 856 transmitted; mismatch = carton refused at the dock.",
        "GS1 spec: reusing an SSCC corrupts the global supply-chain identifier space. Buyer "
        "receiving systems treat duplicates as fraud / error and quarantine the load.",
        '["sales_po_asn_carton.sscc", "sales_po_asn_carton.pack_lot_id"]',
        45,
    ),
    rule(
        "sps_buyer_part_resolution", "Business Rule", "sales",
        "Buyer SKUs resolve to sales_product at PO receipt; lookup is editable, history is not",
        "Inbound 850 LineItems carry the buyer's part number, not ours. At PO receipt, the parser "
        "looks up sales_product_buyer_part on (sales_customer_id, buyer_part_number) and writes "
        "sales_po_line.sales_product_id from the resolved row, while ALSO snapshotting the buyer's "
        "values (buyer_part_number, buyer_description, buyer_uom, buyer_line_sequence, gtin_case) "
        "directly onto sales_po_line. Subsequent edits to sales_product_buyer_part change future "
        "PO resolution but never rewrite the snapshotted values on past lines, so outbound 856/810 "
        "echo what the buyer originally sent.",
        "Buyers occasionally re-key SKUs or change case GTINs. Snapshotting the buyer values at "
        "receipt time means the EDI roundtrip stays consistent for the original PO even after "
        "the lookup is updated for new POs.",
        '["sales_product_buyer_part", "sales_po_line.buyer_part_number", '
        '"sales_po_line.gtin_case", "sales_po_line.sales_product_id"]',
        46,
    ),

    # =====================================================================
    # 7d. SALES CRM — store visits, market intelligence
    # =====================================================================
    rule(
        "sales_crm_store_customer_link", "Business Rule", "sales",
        "Store links to customer but many stores can share one customer",
        "sales_crm_store.sales_customer_id is nullable. Multiple stores can reference the same "
        "customer (e.g. all Costco locations link to the Costco customer for that island). "
        "Stores without a customer link are tracked for competitive intelligence only.",
        None,
        '["sales_crm_store.sales_customer_id"]',
        47,
    ),
    rule(
        "sales_crm_visit_result_product_exclusivity", "Business Rule", "sales",
        "Visit observation: own product or competitor, never both",
        "Each sales_crm_store_visit_result row references either sales_product_id (own product) "
        "or sales_crm_external_product_id (competitor), enforced by CHECK constraint. "
        "This allows comparing own vs competitor shelf presence, pricing, and stock in the same query.",
        None,
        '["sales_crm_store_visit_result.sales_product_id", '
        '"sales_crm_store_visit_result.sales_crm_external_product_id"]',
        48,
    ),

    # =====================================================================
    # 8. FOOD SAFETY — testing, results
    # =====================================================================
    rule(
        "fsafe_test_pass_fail", "Business Rule", "food_safety",
        "Pass/fail criteria by test type",
        "Enum: pass when response in enum_pass_options. Numeric: pass within min/max. "
        "ATP: randomly select atp_site_count zone_1 sites.",
        None,
        '["fsafe_lab_test.enum_pass_options", "fsafe_lab_test.minimum_value", "fsafe_lab_test.maximum_value"]',
        49,
    ),
    rule(
        "fsafe_retest_auto_create", "Workflow", "food_safety",
        "Auto-create retest/vector on failure",
        "Failed initial test auto-creates retest and vector results based on lab test config.",
        None,
        '["fsafe_result", "fsafe_lab_test.requires_retest", "fsafe_lab_test.requires_vector_test"]',
        50,
    ),

    # =====================================================================
    # 9. MAINTENANCE — requests
    # =====================================================================
    rule(
        "maint_preventive_recurrence", "Workflow", "maintenance",
        "Auto-create next request on completion of recurring maintenance",
        "When recurring_frequency is set and status = done, a new request is auto-created.",
        None,
        '["maint_request.recurring_frequency", "maint_request.status"]',
        51,
    ),

    # =====================================================================
    # 10. AUTH — sign-in auto-link to hr_employee
    # =====================================================================
    rule(
        "auth_auto_link_employee", "Workflow", "human_resources",
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
        52,
    ),

    # =====================================================================
    # 11. GROW — harvest tare calculation
    # =====================================================================
    rule(
        "grow_harvest_tare_calculation", "Calculation", "grow",
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
        53,
    ),
    rule(
        "grow_scouting_site_hierarchy", "Business Rule", "grow",
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
        54,
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
