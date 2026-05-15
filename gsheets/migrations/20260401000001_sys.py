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
import sys
from pathlib import Path

import gspread
import psycopg2
from google.oauth2.service_account import Credentials
from supabase import create_client

# Make sibling helper modules importable both when run via _run_nightly.py
# (which preloads sys.path) and when invoked standalone for ad-hoc runs.
sys.path.insert(0, str(Path(__file__).parent))
from _qb_token_preserve import backup as backup_qb_token  # noqa: E402


def _load_dotenv():
    """Populate os.environ from .env at the repo root if keys are missing."""
    try:
        with open(".env") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k, v)
    except FileNotFoundError:
        pass


_load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://kfwqtaazdankxmdlqdak.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
SUPABASE_DB_URL = os.environ.get("SUPABASE_DB_URL")

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


def truncate_all_public_tables():
    """Truncate every table in the public schema except the four sys_* lookup
    tables (which this script re-seeds immediately after). Uses a single
    TRUNCATE ... CASCADE so FK dependency order is handled by Postgres.

    Auth/storage/realtime schemas are left untouched.
    """
    if not SUPABASE_DB_URL:
        raise SystemExit(
            "ERROR: SUPABASE_DB_URL is required to truncate public tables. "
            "Set it in .env (Supabase Dashboard -> Settings -> Database -> Connection string)."
        )

    excluded = ("sys_access_level", "sys_module", "sys_sub_module", "sys_uom")

    print("Discovering public tables...")
    with psycopg2.connect(SUPABASE_DB_URL) as conn:
        # Preserve OAuth credentials across the TRUNCATE -- migration 003
        # restores them after hr_employee is reseeded, so the composite FK
        # (org_id, connected_by) -> hr_employee is satisfied at insert time.
        # Anything we don't back up here is wiped permanently.
        backup_qb_token(conn)

        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT tablename
                FROM pg_tables
                WHERE schemaname = 'public'
                  AND tablename NOT IN %s
                ORDER BY tablename;
                """,
                (excluded,),
            )
            tables = [r[0] for r in cur.fetchall()]

            if not tables:
                print("  No tables to truncate")
                return

            print(f"  Truncating {len(tables)} tables (CASCADE)...")
            qualified = ", ".join(f'public."{t}"' for t in tables)
            cur.execute(f"TRUNCATE {qualified} RESTART IDENTITY CASCADE;")
        conn.commit()
    print(f"  Truncated {len(tables)} public tables")


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def seed_access_levels(supabase):
    """Seed the 5 access levels."""
    rows = [
        audit({"id": "Employee",  "level": 1, "display_order": 1}),
        audit({"id": "Team Lead", "level": 2, "display_order": 2}),
        audit({"id": "Manager",   "level": 3, "display_order": 3}),
        audit({"id": "Admin",     "level": 4, "display_order": 4}),
        audit({"id": "Owner",     "level": 5, "display_order": 5}),
    ]
    insert_rows(supabase, "sys_access_level", rows)


def seed_modules(supabase):
    """Seed the application modules."""
    rows = [
        audit({"id": "Operations",      "display_order": 1}),
        audit({"id": "Grow",            "display_order": 2}),
        audit({"id": "Pack",            "display_order": 3}),
        audit({"id": "Food Safety",     "display_order": 4}),
        audit({"id": "Maintenance",     "display_order": 5}),
        audit({"id": "Inventory",       "display_order": 6}),
        audit({"id": "Sales",           "display_order": 7}),
        audit({"id": "Human Resources", "display_order": 8}),
    ]
    insert_rows(supabase, "sys_module", rows)


def seed_sub_modules(supabase, gc):
    """Seed sys_sub_module from a hardcoded list.

    The legacy global_menu_icons_sub Google Sheet was retired with
    20260512184640_purge_inactive_sub_modules.sql -- the old system
    carried ~50 sub-modules we won't be rebuilding. From here on,
    sub-modules are added to ACTIVE_SUB_MODULES below as features ship,
    keeping the codebase as the single source of truth. The `gc` arg is
    retained for signature compatibility but no longer used.
    """
    # (id, sys_module_id, sys_access_level_id, display_order)
    ACTIVE_SUB_MODULES = [
        ("Packlot",        "Pack",            "Employee",  1),
        ("Packing",        "Pack",            "Employee",  2),
        ("Products",       "Pack",            "Employee",  3),
        ("Customers",      "Sales",           "Employee",  4),
        ("FOB",            "Sales",           "Employee",  5),
        ("Product Prices", "Sales",           "Employee",  6),
        ("Register",       "Human Resources", "Manager",  22),
        ("Scheduler",      "Human Resources", "Manager",  23),
        ("Time Off",       "Human Resources", "Manager",  24),
        ("Payroll Comp",   "Human Resources", "Manager",  26),
        ("Payroll Data",   "Human Resources", "Admin",    28),
        ("Housing",        "Human Resources", "Manager",  29),
    ]

    rows = [
        audit({
            "id": sub_id,
            "sys_module_id": mod_id,
            "sys_access_level_id": lvl,
            "display_order": order,
        })
        for sub_id, mod_id, lvl, order in ACTIVE_SUB_MODULES
    ]

    insert_rows(supabase, "sys_sub_module", rows)


def migrate_uom(supabase):
    """Migrate sys_uom from legacy Google Sheet + additional schema-required UOMs."""
    rows = [
        # From legacy Google Sheet (global_measurement_unit)
        {"id": "Clip",         "category": "packaging"},
        {"id": "Bag",          "category": "packaging"},
        {"id": "Box",          "category": "packaging"},
        {"id": "Blade",        "category": "equipment"},
        {"id": "Bottle",       "category": "packaging"},
        {"id": "Count",        "category": "quantity"},
        {"id": "Dozen",        "category": "quantity"},
        {"id": "Drum",         "category": "packaging"},
        {"id": "Gallon",       "category": "volume"},
        {"id": "Board",        "category": "growing"},
        {"id": "Impression",   "category": "packaging"},
        {"id": "Pallet",       "category": "shipping"},
        {"id": "Meter",        "category": "length"},
        {"id": "Label",        "category": "packaging"},
        {"id": "Seed",         "category": "growing"},
        {"id": "Pack",         "category": "packaging"},
        {"id": "Tray",         "category": "packaging"},
        {"id": "Unit",         "category": "quantity"},
        {"id": "Roll",         "category": "packaging"},
        {"id": "Lid",          "category": "packaging"},
        {"id": "Pound",        "category": "weight"},
        {"id": "Quart",        "category": "volume"},
        {"id": "Ounce",        "category": "weight"},
        {"id": "Gram",         "category": "weight"},
        {"id": "Kit",          "category": "quantity"},
        {"id": "Feet",         "category": "length"},
        {"id": "Fluid Ounce",  "category": "volume"},
        {"id": "Milliliter",   "category": "volume"},
        {"id": "Reactions",    "category": "lab"},
        {"id": "Cubes",        "category": "quantity"},

        # Additional UOMs required by the new schema
        {"id": "Kilogram",     "category": "weight"},
        {"id": "Liter",        "category": "volume"},
        {"id": "Case",         "category": "packaging"},
        {"id": "Flat",         "category": "growing"},
        {"id": "Tote",         "category": "packaging"},
        {"id": "Basket",       "category": "packaging"},
        {"id": "Clam",         "category": "packaging"},
        {"id": "Sleeve",       "category": "packaging"},
        {"id": "Bunch",        "category": "quantity"},
        {"id": "Head",         "category": "quantity"},
        {"id": "Piece",        "category": "quantity"},
        {"id": "Acre",         "category": "area"},
        {"id": "Inch",         "category": "length"},
        {"id": "Centimeter",   "category": "length"},
        {"id": "Celsius",      "category": "temperature"},
        {"id": "Fahrenheit",   "category": "temperature"},
        {"id": "PPM",          "category": "concentration"},
        {"id": "pH",           "category": "concentration"},
        {"id": "Percent",      "category": "ratio"},
        {"id": "RLU",          "category": "lab"},
        {"id": "Each",         "category": "quantity"},
        {"id": "Hour",         "category": "time"},
        {"id": "Day",          "category": "time"},
        {"id": "Millisiemens", "category": "conductivity"},
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

    truncate_all_public_tables()

    # Clear sys tables in reverse FK order so they can be re-seeded below.
    print("Clearing sys tables...")
    supabase.table("sys_sub_module").delete().neq("id", "___never___").execute()
    supabase.table("sys_module").delete().neq("id", "___never___").execute()
    supabase.table("sys_access_level").delete().neq("id", "___never___").execute()
    supabase.table("sys_uom").delete().neq("id", "___never___").execute()
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
