"""
Migrate System Data
====================
Migrates sys_access_level, sys_module, sys_sub_module, and sys_uom from legacy
Google Sheets to Supabase.

Source: https://docs.google.com/spreadsheets/d/1VOVyYt_Mk7QJkjZFRyq3iLf6xkBrZUWarobv7tf8yZA
  - sys_access_level: hardcoded 5 levels (employee, team_lead, manager, admin, owner)
  - sys_module: hardcoded 8 application modules
  - sys_sub_module: from sheet 'global_menu_icons_sub'

Legacy access level mapping:
  Sheet Level 1 -> employee (level 1)
  Sheet Level 2 -> manager (level 3)
  Sheet Level 3 -> admin (level 4)

Usage:
    python scripts/migrations/20260401000001_sys.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://kfwqtaazdankxmdlqdak.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

if not SUPABASE_KEY:
    try:
        with open(".env") as f:
            for line in f:
                if line.startswith("SUPABASE_SERVICE_KEY="):
                    SUPABASE_KEY = line.strip().split("=", 1)[1]
    except FileNotFoundError:
        pass

AUDIT_USER = "data@hawaiifarming.com"

SHEET_ID = "1VOVyYt_Mk7QJkjZFRyq3iLf6xkBrZUWarobv7tf8yZA"


def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()


def audit(row: dict) -> dict:
    """Add audit fields to a row."""
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def parse_bool(val):
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def insert_rows(supabase, table: str, rows: list):
    """Insert rows in batches of 100. Returns inserted data."""
    print(f"\n--- {table} ---")
    all_data = []
    if rows:
        for i in range(0, len(rows), 100):
            batch = rows[i:i + 100]
            result = supabase.table(table).insert(batch).execute()
            all_data.extend(result.data)
        print(f"  Inserted {len(rows)} rows")
    return all_data


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def seed_access_levels(supabase):
    """Seed the 5 access levels."""
    rows = [
        audit({"id": "employee",  "name": "Employee",  "level": 1, "display_order": 1}),
        audit({"id": "team_lead", "name": "Team Lead", "level": 2, "display_order": 2}),
        audit({"id": "manager",   "name": "Manager",   "level": 3, "display_order": 3}),
        audit({"id": "admin",     "name": "Admin",     "level": 4, "display_order": 4}),
        audit({"id": "owner",     "name": "Owner",     "level": 5, "display_order": 5}),
    ]
    insert_rows(supabase, "sys_access_level", rows)


def seed_modules(supabase):
    """Seed the application modules."""
    rows = [
        audit({"id": "operations",      "name": "Operations",      "display_order": 1}),
        audit({"id": "grow",            "name": "Grow",            "display_order": 2}),
        audit({"id": "pack",            "name": "Pack",            "display_order": 3}),
        audit({"id": "food_safety",     "name": "Food Safety",     "display_order": 4}),
        audit({"id": "maintenance",     "name": "Maintenance",     "display_order": 5}),
        audit({"id": "inventory",       "name": "Inventory",       "display_order": 6}),
        audit({"id": "sales",           "name": "Sales",           "display_order": 7}),
        audit({"id": "human_resources", "name": "Human Resources", "display_order": 8}),
    ]
    insert_rows(supabase, "sys_module", rows)


def seed_sub_modules(supabase, gc):
    """
    Seed sub-modules from the legacy Google Sheet global_menu_icons_sub.

    Legacy level mapping:
      Level 1 -> employee (sys_access_level_id = 'employee')
      Level 2 -> manager  (sys_access_level_id = 'manager')
      Level 3 -> admin    (sys_access_level_id = 'admin')
    """
    sheet = gc.open_by_key(SHEET_ID)
    ws = sheet.worksheet("global_menu_icons_sub")
    records = ws.get_all_records()

    # Map legacy levels to sys_access_level_id
    level_map = {
        "1": "employee",
        "2": "manager",
        "3": "admin",
        1: "employee",
        2: "manager",
        3: "admin",
    }

    # Map legacy main menu names to sys_module_id
    module_map = {
        "grow": "grow",
        "pack": "pack",
        "food safety": "food_safety",
        "maintenance": "maintenance",
        "inventory": "inventory",
        "human resources": "human_resources",
        "sales": "sales",
        "execute": "operations",
        "global": "operations",
    }

    rows = []
    seen = set()

    for i, record in enumerate(records):
        sub_name = proper_case(record.get("SubMenuName", ""))
        main_name = record.get("MainMenuName", "").strip()
        level = record.get("Level", "1")

        if not sub_name or not main_name:
            continue

        sys_module_id = module_map.get(main_name.lower())
        if not sys_module_id:
            print(f"  SKIP: Unknown module '{main_name}' for sub '{sub_name}'")
            continue

        sys_access_level_id = level_map.get(level, "employee")
        sub_id = to_id(sub_name)

        # Deduplicate
        if sub_id in seen:
            continue
        seen.add(sub_id)

        rows.append(audit({
            "id": sub_id,
            "sys_module_id": sys_module_id,
            "name": sub_name,
            "sys_access_level_id": sys_access_level_id,
            "display_order": len(rows) + 1,
        }))

    insert_rows(supabase, "sys_sub_module", rows)


def migrate_uom(supabase):
    """Migrate sys_uom from legacy Google Sheet + additional schema-required UOMs."""
    rows = [
        # From legacy Google Sheet (global_measurement_unit)
        {"code": "clip",         "name": "clip",         "category": "packaging"},
        {"code": "bag",          "name": "bag",          "category": "packaging"},
        {"code": "box",          "name": "box",          "category": "packaging"},
        {"code": "blade",        "name": "blade",        "category": "equipment"},
        {"code": "bottle",       "name": "bottle",       "category": "packaging"},
        {"code": "count",        "name": "count",        "category": "quantity"},
        {"code": "dozen",        "name": "dozen",        "category": "quantity"},
        {"code": "drum",         "name": "drum",         "category": "packaging"},
        {"code": "gallon",       "name": "gallon",       "category": "volume"},
        {"code": "board",        "name": "board",        "category": "growing"},
        {"code": "impression",   "name": "impression",   "category": "packaging"},
        {"code": "pallet",       "name": "pallet",       "category": "shipping"},
        {"code": "meter",        "name": "meter",        "category": "length"},
        {"code": "label",        "name": "label",        "category": "packaging"},
        {"code": "seed",         "name": "seed",         "category": "growing"},
        {"code": "pack",         "name": "pack",         "category": "packaging"},
        {"code": "tray",         "name": "tray",         "category": "packaging"},
        {"code": "unit",         "name": "unit",         "category": "quantity"},
        {"code": "roll",         "name": "roll",         "category": "packaging"},
        {"code": "lid",          "name": "lid",          "category": "packaging"},
        {"code": "pound",        "name": "lb",           "category": "weight"},
        {"code": "quart",        "name": "quart",        "category": "volume"},
        {"code": "ounce",        "name": "oz",           "category": "weight"},
        {"code": "gram",         "name": "g",            "category": "weight"},
        {"code": "kit",          "name": "kit",          "category": "quantity"},
        {"code": "feet",         "name": "ft",           "category": "length"},
        {"code": "fluid_ounce",  "name": "fl oz",        "category": "volume"},
        {"code": "milliliter",   "name": "mL",           "category": "volume"},
        {"code": "reactions",    "name": "reactions",     "category": "lab"},
        {"code": "cubes",       "name": "cubes",         "category": "quantity"},

        # Additional UOMs required by the new schema
        {"code": "kilogram",     "name": "kg",           "category": "weight"},
        {"code": "liter",        "name": "L",            "category": "volume"},
        {"code": "case",         "name": "case",         "category": "packaging"},
        {"code": "flat",         "name": "flat",         "category": "growing"},
        {"code": "tote",         "name": "tote",         "category": "packaging"},
        {"code": "basket",       "name": "basket",       "category": "packaging"},
        {"code": "clam",         "name": "clam",         "category": "packaging"},
        {"code": "sleeve",       "name": "sleeve",       "category": "packaging"},
        {"code": "bunch",        "name": "bunch",        "category": "quantity"},
        {"code": "head",         "name": "head",         "category": "quantity"},
        {"code": "piece",        "name": "piece",        "category": "quantity"},
        {"code": "acre",         "name": "acre",         "category": "area"},
        {"code": "inch",         "name": "in",           "category": "length"},
        {"code": "centimeter",   "name": "cm",           "category": "length"},
        {"code": "celsius",      "name": "C",            "category": "temperature"},
        {"code": "fahrenheit",   "name": "F",            "category": "temperature"},
        {"code": "ppm",          "name": "ppm",          "category": "concentration"},
        {"code": "ph",           "name": "pH",           "category": "concentration"},
        {"code": "percent",      "name": "%",            "category": "ratio"},
        {"code": "rlu",          "name": "RLU",          "category": "lab"},
        {"code": "each",         "name": "each",          "category": "quantity"},
        {"code": "hour",         "name": "hr",           "category": "time"},
        {"code": "day",          "name": "day",          "category": "time"},
    ]

    for row in rows:
        audit(row)

    insert_rows(supabase, "sys_uom", rows)


def main():
    if not SUPABASE_KEY:
        print("ERROR: Set SUPABASE_SERVICE_KEY in .env or environment")
        print("  Get it from: Supabase Dashboard -> Settings -> API -> service_role key")
        return

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("SYSTEM DATA MIGRATION")
    print("=" * 60)

    # Clear ALL dependent tables in reverse migration order (leaf tables first)
    print("Clearing all dependent tables...")
    for t in [
              # fsafe
              "ops_corrective_action_taken",
              "fsafe_pest_result", "fsafe_result", "fsafe_test_hold_po",
              "fsafe_test_hold", "fsafe_lab_test", "fsafe_lab",
              # maint
              "maint_request_photo", "maint_request_invnt_item", "maint_request",
              # pack
              "pack_productivity_hour_fail", "pack_productivity_hour",
              "pack_productivity_fail_category",
              "pack_shelf_life_photo", "pack_shelf_life_result",
              "pack_shelf_life", "pack_shelf_life_metric",
              # sales
              "sales_po_fulfillment", "pack_lot_item", "pack_lot",
              "sales_po_line", "sales_po",
              "sales_product_price", "sales_customer",
              "sales_customer_group", "sales_fob",
              # grow (higher)
              "grow_task_photo", "grow_task_seed_batch",
              "grow_monitoring_result", "grow_monitoring_metric",
              "grow_fertigation", "grow_fertigation_recipe_site",
              "grow_fertigation_recipe_item", "grow_fertigation_recipe",
              # grow (spray/scout/harvest/seed)
              "grow_spray_equipment", "grow_spray_input",
              "grow_spray_compliance", "grow_scout_result",
              "grow_harvest_weight", "grow_harvest_container",
              "grow_seed_batch", "grow_seed_mix_item", "grow_seed_mix",
              "grow_trial_type", "grow_cycle_pattern",
              # ops
              "ops_template_result_photo", "ops_template_result",
              "ops_template_question", "ops_corrective_action_choice",
              "ops_task_template", "ops_template",
              "ops_training_attendee", "ops_training", "ops_training_type",
              "ops_task_schedule", "ops_task_tracker",
              "sales_product", "ops_task",
              # invnt
              "invnt_onhand", "invnt_po_received", "invnt_lot",
              "invnt_po", "invnt_item", "invnt_category", "invnt_vendor",
              # hr
              "hr_payroll", "hr_disciplinary_warning",
              "hr_travel_request", "hr_time_off_request",
              "hr_module_access", "hr_employee",
              "hr_title", "hr_work_authorization", "hr_department",
              # grow (base)
              "grow_disease", "grow_pest", "grow_grade", "grow_variety",
              # org
              "org_business_rule", "org_equipment", "org_site",
              "org_site_category", "org_sub_module", "org_module",
              "org_farm", "org",
              ]:
        try:
            supabase.table(t).delete().neq("org_id", "___never___").execute()
        except Exception:
            try:
                supabase.table(t).delete().neq("id", "___never___").execute()
            except Exception:
                pass
    print("  All dependencies cleared")

    # Clear sys tables in reverse FK order
    print("Clearing sys tables...")
    supabase.table("sys_sub_module").delete().neq("id", "___never___").execute()
    supabase.table("sys_module").delete().neq("id", "___never___").execute()
    supabase.table("sys_access_level").delete().neq("id", "___never___").execute()
    supabase.table("sys_uom").delete().neq("code", "___never___").execute()
    print("  All cleared")

    migrate_uom(supabase)
    seed_access_levels(supabase)
    seed_modules(supabase)
    seed_sub_modules(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
