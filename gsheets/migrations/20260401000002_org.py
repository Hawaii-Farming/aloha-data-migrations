"""
Migrate Organization Data
==========================
Migrates org, org_farm, org_site_category, org_module, org_sub_module,
and grow_pest/grow_disease from legacy Google Sheets to Supabase.

Sources:
  - org: hardcoded (Hawaii Farming)
  - org_farm: from sheet 'global_farm'
  - org_site_category: from provisioning defaults
  - org_module: copied from sys_module for the org
  - org_sub_module: copied from sys_sub_module for the org
  - grow_pest / grow_disease: hardcoded common types

Source spreadsheet: https://docs.google.com/spreadsheets/d/1VOVyYt_Mk7QJkjZFRyq3iLf6xkBrZUWarobv7tf8yZA

Usage:
    python scripts/migrations/20260401000002_org.py

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
ORG_ID = "hawaii_farming"

SHEET_ID_GLOBAL = "1VOVyYt_Mk7QJkjZFRyq3iLf6xkBrZUWarobv7tf8yZA"
SHEET_ID_VARIETY = "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

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


def insert_rows(supabase, table: str, rows: list, upsert=False):
    """Insert (or upsert) rows in batches of 100. Returns inserted data."""
    print(f"\n--- {table} ---")
    all_data = []
    if rows:
        for i in range(0, len(rows), 100):
            batch = rows[i:i + 100]
            if upsert:
                result = supabase.table(table).upsert(batch).execute()
            else:
                result = supabase.table(table).insert(batch).execute()
            all_data.extend(result.data)
        action = "Upserted" if upsert else "Inserted"
        print(f"  {action} {len(rows)} rows")
    return all_data


def parse_bool(val):
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def safe_int(val, default=None):
    """Parse an integer value or return default."""
    try:
        v = str(val).strip().replace(",", "")
        return int(float(v)) if v else default
    except (ValueError, TypeError):
        return default


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ---------------------------------------------------------------------------
# Migration functions
# ---------------------------------------------------------------------------

def migrate_org(supabase):
    """Create the Hawaii Farming organization."""
    row = audit({
        "id": ORG_ID,
        "name": "Hawaii Farming",
        "address": "66-1475 Pu'u Huluhulu Rd, Kamuela HI",
        "currency": "USD",
    })
    print("\n--- org ---")
    supabase.table("org").upsert(row).execute()
    print("  Upserted 1 row")


def migrate_org_farm(supabase, gc):
    """Migrate farms from legacy Google Sheet."""
    sheet = gc.open_by_key(SHEET_ID_GLOBAL)
    ws = sheet.worksheet("global_farm")
    values = ws.col_values(1)[1:]  # skip header

    farm_defaults = {
        "cuke": {"weighing_uom": "pound", "growing_uom": "bag", "volume_uom": "gallon"},
        "lettuce": {"weighing_uom": "pound", "growing_uom": "board", "volume_uom": "gallon"},
    }

    rows = []
    for i, farm_name in enumerate(values):
        farm_name = farm_name.strip()
        if not farm_name or farm_name == ORG_ID.upper() or farm_name == "HF":
            continue  # skip the org-level entry
        farm_name = to_id(farm_name)
        defaults = farm_defaults.get(farm_name, {})
        rows.append(audit({
            "org_id": ORG_ID,
            "name": proper_case(farm_name),
            **defaults,
        }))

    insert_rows(supabase, "org_farm", rows, upsert=True)


def migrate_org_site_category(supabase):
    """Provision default site categories for the org."""
    categories = [
        # (category_name, sub_category_name)
        ("growing", None),
        ("growing", "greenhouse"),
        ("growing", "nursery"),
        ("growing", "pond"),
        ("growing", "row"),
        ("growing", "room"),
        ("growing", "other"),
        ("packing", None),
        ("packing", "room"),
        ("packing", "other"),
        ("housing", None),
        ("housing", "room"),
        ("housing", "other"),
        ("food_safety", None),
        ("pest_trap", None),
        ("storage", None),
        ("storage", "warehouse"),
        ("storage", "chemical_storage"),
        ("storage", "cold_storage"),
        ("other", None),
    ]

    rows = []
    cat_order = {}
    for cat, sub in categories:
        if sub in ("room", "other") and cat != "housing":
            cat_id = f"{cat}_{sub}"
        elif sub == "other" and cat == "housing":
            cat_id = f"{cat}_{sub}"
        elif sub:
            cat_id = sub
        else:
            cat_id = cat
        cat_order[cat] = cat_order.get(cat, 0) + 1
        rows.append(audit({
            "id": to_id(cat_id),
            "org_id": ORG_ID,
            "category_name": cat,
            "sub_category_name": sub,
            "display_order": cat_order[cat],
        }))

    insert_rows(supabase, "org_site_category", rows, upsert=True)


def migrate_org_module(supabase):
    """Copy sys_module records into org_module for this org.

    Only `human_resources` is enabled for now; all other modules are
    provisioned but disabled until they are ready to roll out.
    """
    ENABLED_MODULES = {"Human Resources"}

    result = supabase.table("sys_module").select("name, display_order").order("display_order").execute()

    rows = []
    for mod in result.data:
        rows.append(audit({
            "org_id": ORG_ID,
            "sys_module_name": mod["name"],
            "name": mod["name"],
            "is_enabled": mod["name"] in ENABLED_MODULES,
            "display_order": mod["display_order"],
        }))

    insert_rows(supabase, "org_module", rows, upsert=True)


def migrate_org_sub_module(supabase):
    """Copy sys_sub_module records into org_sub_module for this org.

    Only the HR sub-modules currently in use are enabled: register, scheduler,
    time_off, payroll_comp, payroll_data, employee_review, housing. Everything
    else is provisioned but disabled until its work is ready to roll out.
    """
    ENABLED_SUB_MODULES = {
        "Register",
        "Scheduler",
        "Time Off",
        "Payroll Comp",
        "Payroll Data",
        "Employee Review",
        "Housing",
    }

    result = supabase.table("sys_sub_module").select(
        "id, sys_module_name, name, sys_access_level_name, display_order"
    ).order("display_order").execute()

    rows = []
    for sub in result.data:
        rows.append(audit({
            "org_id": ORG_ID,
            "sys_module_name": sub["sys_module_name"],
            "sys_sub_module_name": sub["name"],
            "sys_access_level_name": sub["sys_access_level_name"],
            "name": sub["name"],
            "is_enabled": sub["name"] in ENABLED_SUB_MODULES,
            "display_order": sub["display_order"],
        }))

    insert_rows(supabase, "org_sub_module", rows, upsert=True)


def migrate_org_site(supabase):
    """Migrate org sites with parent-child hierarchy from legacy Google Sheet."""

    # -- CUKE FARM: Parent sites --
    cuke_parents = [
        audit({
            "id": "jtl",
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "name": "JTL",
            "org_site_category_id": "growing",
            "display_order": 1,
        }),
        audit({
            "id": "bip",
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "name": "BIP",
            "org_site_category_id": "growing",
            "display_order": 2,
        }),
    ]

    # JTL greenhouses (numbered 01-08)
    jtl_greenhouses = {
        "01": 1, "02": 2, "03": 3, "04": 4,
        "05": 5, "06": 6, "07": 7, "08": 8,
    }

    # BIP greenhouses (lettered) + nurseries
    bip_greenhouses = {
        "KO": 1, "HK": 2, "WA": 3, "HI": 4,
    }
    bip_nurseries = {
        "NE": 5, "NW": 6,
    }

    # Legacy sqft/rows data for lookup
    legacy_data = {
        "KO": (41506, 36), "08": (43368, 42), "01": (43196, 60),
        "HK": (45531, 64), "07": (41106, 45), "WA": (40634, 48),
        "04": (41818, 42), "02": (53817, 63), "06": (53817, 63),
        "HI": (39583, 42), "05": (43196, 59), "03": (43196, 60),
    }

    # Monitoring stations per site
    gh_default_stations = ["A", "B"]
    station_overrides = {
        "HK": ["KA", "KB", "HA", "HB"],
    }
    nursery_stations = ["Water", "Low", "High"]
    pond_stations = ["East", "West"]

    cuke_children = []

    # JTL greenhouses
    for code, order in jtl_greenhouses.items():
        sqft, _rows = legacy_data.get(code, (None, None))
        stations = station_overrides.get(code, gh_default_stations)
        site = {
            "id": code.lower(),
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "name": code,
            "org_site_category_id": "growing",
            "org_site_subcategory_id": "greenhouse",
            "site_id_parent": "jtl",
            "monitoring_stations": stations,
            "display_order": order,
        }
        if sqft:
            site["acres"] = round(sqft / 43560, 2)
        cuke_children.append(audit(site))

    # BIP greenhouses
    for code, order in bip_greenhouses.items():
        sqft, _rows = legacy_data.get(code, (None, None))
        stations = station_overrides.get(code, gh_default_stations)
        site = {
            "id": code.lower(),
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "name": code,
            "org_site_category_id": "growing",
            "org_site_subcategory_id": "greenhouse",
            "site_id_parent": "bip",
            "monitoring_stations": stations,
            "display_order": order,
        }
        if sqft:
            site["acres"] = round(sqft / 43560, 2)
        cuke_children.append(audit(site))

    # BIP nurseries
    for code, order in bip_nurseries.items():
        cuke_children.append(audit({
            "id": code.lower(),
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "name": code,
            "org_site_category_id": "growing",
            "org_site_subcategory_id": "nursery",
            "site_id_parent": "bip",
            "monitoring_stations": nursery_stations,
            "display_order": order,
        }))

    # -- LETTUCE FARM: Parent site --
    lettuce_parent = [
        audit({
            "id": "gh",
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "name": "GH",
            "org_site_category_id": "growing",
            "acres": round(108900 / 43560, 2),
            "display_order": 1,
        }),
    ]

    # Lettuce ponds (P1-P7)
    lettuce_ponds_data = {
        "P1": (5260, 20, 1), "P2": (13920, 40, 2), "P3": (13920, 40, 3),
        "P4": (13920, 40, 4), "P5": (13920, 40, 5), "P6": (13920, 40, 6),
        "P7": (13920, 40, 7),
    }

    lettuce_children = []
    for code, (sqft, _rows, order) in lettuce_ponds_data.items():
        lettuce_children.append(audit({
            "id": code.lower(),
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "name": code,
            "org_site_category_id": "growing",
            "org_site_subcategory_id": "pond",
            "site_id_parent": "gh",
            "monitoring_stations": pond_stations,
            "acres": round(sqft / 43560, 2),
            "display_order": order,
        }))

    # -- HOUSING (standalone table, not org_site) --
    housing_sites = [
        "BIP (5)", "Duplex", "JTL (1)", "JTL (2)",
        "Kawano (3)", "Kawano (4)", "Minor's", "Pete's",
        "Todd's", "South Kohala",
    ]
    housing_rows = []
    for name in housing_sites:
        housing_rows.append(audit({
            "name": name,
            "org_id": ORG_ID,
        }))

    # Insert parents first, then children. Housing goes to its own table.
    insert_rows(supabase, "org_site", cuke_parents + lettuce_parent, upsert=True)
    print(f"  ({len(cuke_parents + lettuce_parent)} parent sites)")
    supabase.table("org_site").upsert(cuke_children + lettuce_children).execute()
    print(f"  Upserted {len(cuke_children + lettuce_children)} child sites")
    insert_rows(supabase, "org_site_housing", housing_rows, upsert=True)
    print(f"  ({len(housing_rows)} housing facilities)")


def migrate_grow_variety(supabase, gc):
    """Migrate grow varieties from legacy Google Sheet."""
    ws = gc.open_by_key(SHEET_ID_VARIETY).worksheet("grow_variety")
    records = ws.get_all_records()

    rows = []
    for r in records:
        code = str(r.get("Variety", "")).strip()
        name = str(r.get("VarietyName", "")).strip()
        farm = str(r.get("Farm", "")).strip()
        if not code or not name:
            continue
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_name": to_id(farm),
            "code": code,
            "name": proper_case(name),
        }))

    insert_rows(supabase, "grow_variety", rows, upsert=True)


def migrate_grow_grade(supabase):
    """Migrate grow grades -- hardcoded for Cuke farm."""
    rows = [
        audit({
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "code": "1",
            "name": "On Grade",
        }),
        audit({
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "code": "2",
            "name": "Off Grade",
        }),
    ]
    insert_rows(supabase, "grow_grade", rows, upsert=True)


def migrate_ops_task(supabase):
    """Provision default ops_task records per org provisioning doc."""
    default_tasks = [
        ("seeding", "Seeding", "Planting seeds into growing media for germination"),
        ("harvesting", "Harvesting", "Cutting and collecting mature crops from growing sites"),
        ("scouting", "Scouting", "Inspecting crops for pests, disease, and growth issues"),
        ("spraying", "Spraying", "Applying pesticides or treatments to crops"),
        ("fertigation", "Fertigation", "Delivering fertilizer through the irrigation system"),
        ("monitoring", "Monitoring", "Recording environmental readings at growing sites"),
        ("packing", "Packing", "Processing harvested crops into packaged products"),
        ("pest_trap_inspection", "Pest Trap Inspection", "Checking and recording pest trap counts at food safety sites"),
        ("food_safety_log", "Food Safety Log", "Completing food safety checklists, facility inspections, and equipment calibration"),
    ]

    rows = [
        audit({
            "org_id": ORG_ID,
            "name": name,
            "description": description,
        })
        for task_id, name, description in default_tasks
    ]

    # Upsert to handle reruns where tasks may already exist (referenced by trackers)
    print("\n--- ops_task ---")
    if rows:
        supabase.table("ops_task").upsert(rows).execute()
        print(f"  Upserted {len(rows)} rows")


def migrate_grow_pest(supabase):
    """Migrate common pest types."""
    pests = [
        "Aphid", "Whitefly", "Thrips", "Spider Mite", "Mealybug",
        "Fungus Gnat", "Shore Fly", "Caterpillar", "Leafminer",
    ]
    rows = [
        audit({"name": p})
        for p in pests
    ]
    insert_rows(supabase, "grow_pest", rows, upsert=True)


def migrate_grow_disease(supabase):
    """Migrate common disease types."""
    diseases = [
        "Powdery Mildew", "Downy Mildew", "Botrytis", "Fusarium",
        "Pythium", "Root Rot", "Bacterial Leaf Spot", "Tipburn",
    ]
    rows = [
        audit({"name": d})
        for d in diseases
    ]
    insert_rows(supabase, "grow_disease", rows, upsert=True)


def main():
    if not SUPABASE_KEY:
        print("ERROR: Set SUPABASE_SERVICE_KEY in .env or environment")
        return

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("ORG DATA MIGRATION")
    print("=" * 60)

    # Clear in reverse FK order (try/except for tables that may be referenced by downstream modules)
    print("Clearing tables in FK dependency order...")
    for t in ["grow_disease", "grow_pest", "grow_grade", "grow_variety"]:
        try:
            supabase.table(t).delete().neq("id", "___never___").execute()
        except Exception:
            pass  # May fail if referenced by invnt_item etc; will be upserted
    # Clear tables — try/except for tables that may be referenced by downstream modules
    # PK column per table — name for the reference tables we keyed by name,
    # id for everything else that still uses id as PK.
    PK_COL = {
        "org_sub_module": "name",
        "org_module": "name",
        "org_farm": "name",
        "org_site": "id",
        "org_site_category": "id",
        "org": "id",
    }
    for t in ["hr_time_off_request", "hr_module_access", "hr_employee",
              "hr_work_authorization", "hr_department",
              "org_sub_module", "org_module", "org_site", "org_site_category",
              "org_farm", "org"]:
        try:
            filter_col = PK_COL.get(t, "org_id")
            supabase.table(t).delete().neq(filter_col, "___never___").execute()
        except Exception:
            pass  # May fail if referenced by downstream modules; data will be upserted
    # Clear default ops_tasks (exclude house_inspection which is managed by maint.py)
    default_task_names = ["Seeding", "Harvesting", "Scouting", "Spraying",
                          "Fertigation", "Monitoring", "Packing", "Pest Trap Inspection"]
    try:
        supabase.table("ops_task").delete().in_("name", default_task_names).execute()
    except Exception:
        pass
    print("  All cleared")

    migrate_org(supabase)
    migrate_org_farm(supabase, gc)
    migrate_org_site_category(supabase)
    migrate_org_site(supabase)
    migrate_org_module(supabase)
    migrate_org_sub_module(supabase)
    migrate_ops_task(supabase)
    migrate_grow_variety(supabase, gc)
    migrate_grow_grade(supabase)
    migrate_grow_pest(supabase)
    migrate_grow_disease(supabase)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
