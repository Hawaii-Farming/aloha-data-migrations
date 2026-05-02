"""
Campo Caribe — one-off HR provisioning + employee load
=======================================================
Provisions the Campo Caribe org from scratch and loads its 82-employee
HR register from the source spreadsheet:
    https://docs.google.com/spreadsheets/d/1sD5m654kH6AAzWIKn102QkqGhiulMvpg-PlGAVloY1U

What this script creates / populates (idempotent — re-runnable):

    org                      — 1 row  ('campo_caribe')
    org_module               — 8 rows (mirrored from sys_module)
    org_sub_module           — 52 rows (mirrored from sys_sub_module)
    org_farm                 — 1 row  ('Lettuce')
    hr_work_authorization    — 1 row  ('Local')
    hr_department            — 5 rows (unique 'Department' values from sheet)
    hr_employee              — 82 rows (parsed from sheet)
    hr_module_access         — 8 rows × {employees with company_email}
                               (only employees who will sign in get module
                               access; the other 80 are tracked records-only)

Field mapping (sheet -> hr_employee):

    FULL Name "Last, First M."             -> first_name + last_name
    Payroll ID                             -> payroll_id
    Comp Manager Name                      -> compensation_manager_id (2nd pass)
    Department                             -> hr_department_id
    Hire/Rehire Date                       -> start_date
    Access Level                           -> sys_access_level_id
    Basis of Pay                           -> pay_structure
    Gender                                 -> gender
    Birth Date                             -> date_of_birth
    Company Email                          -> company_email
    Personal Contact: Personal Mobile      -> phone

Sheet 'Division' is intentionally not mapped (per request).
hr_work_authorization defaults to 'Local' for every employee.

Usage:
    PYTHONPATH=. python gsheets/one_off/campo_caribe_hr.py

This script is NOT in the nightly DEFAULT_SET — it's a manual one-off.
"""
import os
import re
import sys
from datetime import datetime
from pathlib import Path

import gspread
from google.oauth2.service_account import Credentials

# Reuse helpers from the migrations dir
sys.path.insert(0, str(Path(__file__).parent.parent / "migrations"))
from _config import _load_env_file  # noqa: E402  triggers .env load
_load_env_file()
from _pg import get_pg_conn  # noqa: E402

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SHEET_ID = "1sD5m654kH6AAzWIKn102QkqGhiulMvpg-PlGAVloY1U"
ORG_ID = "campo_caribe"
ORG_NAME = "Campo Caribe"
ORG_CURRENCY = "USD"  # Puerto Rico
AUDIT_USER = "data@hawaiifarming.com"

# org_module / org_sub_module / org_farm / hr_department / hr_work_authorization
# all use composite (org_id, *_id) primary keys, so values like 'Lettuce' /
# 'Local' / 'Operations' are reused per-org without conflict.
FARM_ID = "Lettuce"
WORK_AUTH_ID = "Local"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def to_id(text):
    """Lowercase + slug a free-text name into a TEXT PK."""
    if not text:
        return ""
    return re.sub(r"[^a-z0-9_]+", "_", str(text).lower()).strip("_")


def parse_full_name(full):
    """Sheet uses 'Lastname, Firstname M.' — split on the first comma.
    Returns (first_name, last_name). Strips trailing middle initial 'X.'.
    """
    if not full or "," not in full:
        return (full or "").strip(), ""
    last, first = full.split(",", 1)
    last = last.strip()
    first = first.strip()
    # Drop trailing middle initial like "Alleisha N." -> "Alleisha"
    first = re.sub(r"\s+[A-Z]\.?\s*$", "", first).strip()
    return first, last


def parse_date(d):
    """Sheet date strings -> ISO YYYY-MM-DD or None."""
    if not d:
        return None
    s = str(d).strip()
    if not s:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    print(f"  WARN: could not parse date '{d}'")
    return None


def get_sheets_client():
    scopes = ["https://www.googleapis.com/auth/spreadsheets"]
    for p in ["service_account.json", "credentials.json", "gsheets/service_account.json"]:
        if os.path.exists(p):
            return gspread.authorize(Credentials.from_service_account_file(p, scopes=scopes))
    raise SystemExit("ERROR: service_account credentials file not found")


# ---------------------------------------------------------------------------
# Provisioning steps (org + module + sub_module + farm + work_auth)
# ---------------------------------------------------------------------------
def provision_org(cur):
    cur.execute("""
        INSERT INTO org (id, name, currency, created_by, updated_by)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            currency = EXCLUDED.currency,
            updated_by = EXCLUDED.updated_by,
            updated_at = now()
    """, (ORG_ID, ORG_NAME, ORG_CURRENCY, AUDIT_USER, AUDIT_USER))
    print(f"  org: '{ORG_ID}' upserted")


ENABLED_MODULES = ("Human Resources",)
# Campo Caribe is HR-only for now. Add module names to ENABLED_MODULES as
# other modules come online; rows for non-listed modules still get inserted
# (so the org can toggle them on later) but ship is_enabled=false.


def provision_modules(cur):
    cur.execute("""
        INSERT INTO org_module (org_id, sys_module_id, is_enabled, display_order, created_by, updated_by)
        SELECT %s, id, id = ANY(%s), display_order, %s, %s
        FROM sys_module
        ON CONFLICT (org_id, sys_module_id) DO UPDATE SET
            is_enabled = EXCLUDED.is_enabled,
            updated_at = now(),
            updated_by = EXCLUDED.updated_by
    """, (ORG_ID, list(ENABLED_MODULES), AUDIT_USER, AUDIT_USER))
    print(f"  org_module: {cur.rowcount} rows upserted (only {ENABLED_MODULES} enabled)")


def provision_sub_modules(cur):
    cur.execute("""
        INSERT INTO org_sub_module (org_id, sys_module_id, sys_sub_module_id,
                                    sys_access_level_id, is_enabled, display_order,
                                    created_by, updated_by)
        SELECT %s, sys_module_id, id, sys_access_level_id,
               sys_module_id = ANY(%s), display_order, %s, %s
        FROM sys_sub_module
        ON CONFLICT (org_id, sys_sub_module_id) DO UPDATE SET
            is_enabled = EXCLUDED.is_enabled,
            updated_at = now(),
            updated_by = EXCLUDED.updated_by
    """, (ORG_ID, list(ENABLED_MODULES), AUDIT_USER, AUDIT_USER))
    print(f"  org_sub_module: {cur.rowcount} rows upserted (only {ENABLED_MODULES} sub-modules enabled)")


def provision_farm(cur):
    cur.execute("""
        INSERT INTO org_farm (id, org_id, created_by, updated_by)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (org_id, id) DO NOTHING
    """, (FARM_ID, ORG_ID, AUDIT_USER, AUDIT_USER))
    print(f"  org_farm '{FARM_ID}': {cur.rowcount} row inserted")


def provision_work_auth(cur):
    cur.execute("""
        INSERT INTO hr_work_authorization (id, org_id, description, created_by, updated_by)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (org_id, id) DO NOTHING
    """, (WORK_AUTH_ID, ORG_ID, "Local hire (default)", AUDIT_USER, AUDIT_USER))
    print(f"  hr_work_authorization '{WORK_AUTH_ID}': {cur.rowcount} row inserted")


# ---------------------------------------------------------------------------
# HR data load
# ---------------------------------------------------------------------------
def load_departments(cur, records):
    """Returns {sheet_dept_name: dept_id} for use during employee insert.
    With composite PK (org_id, id), the dept name itself can be the id."""
    departments = sorted({
        str(r.get("Department", "")).strip()
        for r in records
        if str(r.get("Department", "")).strip()
    })
    for d in departments:
        cur.execute("""
            INSERT INTO hr_department (id, org_id, description, created_by, updated_by)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (org_id, id) DO NOTHING
        """, (d, ORG_ID, d, AUDIT_USER, AUDIT_USER))
    print(f"  hr_department: {len(departments)} unique values upserted")
    return {d: d for d in departments}


def build_employee_rows(records, dept_map):
    """Parse sheet rows into hr_employee dicts. Returns:
        rows         — list of insert-ready dicts
        name_to_id   — {comp_manager_name_lookup_key: emp_id}
    """
    rows = []
    name_to_id = {}  # "Last First" lowered slug -> emp_id, used for comp_mgr resolution
    seen_ids = set()

    for r in records:
        full = str(r.get("FULL Name", "")).strip()
        if not full:
            continue

        first, last = parse_full_name(full)
        if not first or not last:
            print(f"  WARN: could not parse name '{full}', skipping")
            continue

        # hr_employee uses composite (org_id, id) PK so the same id can
        # legitimately exist in both orgs (e.g. a 'jose_garcia' working
        # for both HF and Campo).
        emp_id = to_id(f"{last} {first}")
        # Disambiguate id collisions (rare with 82 rows)
        suffix = 2
        base_id = emp_id
        while emp_id in seen_ids:
            emp_id = f"{base_id}_{suffix}"
            suffix += 1
        seen_ids.add(emp_id)

        # Lookup key for comp manager resolution: match on the original "Last, First" form
        # (Comp Manager Name in the sheet uses the same format)
        # Use the unprefixed slug so it directly matches the parsed key downstream.
        name_to_id[to_id(f"{last} {first}")] = emp_id

        # Field normalization
        gender = str(r.get("Gender", "")).strip().title()
        if gender not in ("Male", "Female"):
            gender = None

        access_level = str(r.get("Access Level", "")).strip().title()
        if access_level not in ("Owner", "Admin", "Manager", "Team Lead", "Employee"):
            access_level = "Employee"

        pay_structure = str(r.get("Basis of Pay", "")).strip().title()
        if pay_structure not in ("Hourly", "Salary"):
            pay_structure = None

        company_email = str(r.get("Company Email", "")).strip().lower() or None
        phone = str(r.get("Personal Contact: Personal Mobile", "")).strip() or None
        payroll_id = str(r.get("Payroll ID", "")).strip() or None
        department_raw = str(r.get("Department", "")).strip() or None
        hr_department_id = dept_map.get(department_raw) if department_raw else None

        rows.append({
            "id": emp_id,
            "org_id": ORG_ID,
            "first_name": first,
            "last_name": last,
            "gender": gender,
            "date_of_birth": parse_date(r.get("Birth Date")),
            "company_email": company_email,
            "phone": phone,
            "hr_department_id": hr_department_id,
            "hr_work_authorization_id": WORK_AUTH_ID,
            "sys_access_level_id": access_level,
            "start_date": parse_date(r.get("Hire/Rehire Date")),
            "payroll_id": payroll_id,
            "pay_structure": pay_structure,
            "is_primary_org": True,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
            # Internal use only — stripped before insert
            "_comp_mgr_raw": str(r.get("Comp Manager Name", "")).strip(),
        })
    return rows, name_to_id


def insert_employees(cur, rows):
    """Insert hr_employee rows in a single multi-row INSERT.
    Uses ON CONFLICT (id) DO UPDATE for re-runnability."""
    columns = [
        "id", "org_id", "first_name", "last_name", "gender", "date_of_birth",
        "company_email", "phone", "hr_department_id", "hr_work_authorization_id",
        "sys_access_level_id", "start_date", "payroll_id",
        "pay_structure", "is_primary_org", "created_by", "updated_by",
    ]
    inserted = 0
    for row in rows:
        values = [row[c] for c in columns]
        placeholders = ", ".join(["%s"] * len(columns))
        col_list = ", ".join(columns)
        update_set = ", ".join(
            f"{c} = EXCLUDED.{c}" for c in columns if c not in ("id", "org_id", "created_by")
        )
        cur.execute(
            f"INSERT INTO hr_employee ({col_list}) VALUES ({placeholders}) "
            f"ON CONFLICT (org_id, id) DO UPDATE SET {update_set}, updated_at = now()",
            values,
        )
        inserted += 1
    print(f"  hr_employee: {inserted} rows upserted")


def resolve_comp_managers(cur, rows, name_to_id):
    """Second pass — set compensation_manager_id by matching the sheet's
    'Comp Manager Name' (Last, First) against employee IDs we just built."""
    matched = 0
    unmatched = set()
    for row in rows:
        raw = row.get("_comp_mgr_raw", "")
        if not raw or "," not in raw:
            continue
        last, first = raw.split(",", 1)
        last = last.strip()
        first = re.sub(r"\s+[A-Z]\.?\s*$", "", first.strip()).strip()
        key = to_id(f"{last} {first}")
        mgr_id = name_to_id.get(key)
        if mgr_id:
            cur.execute(
                "UPDATE hr_employee SET compensation_manager_id = %s, updated_at = now() WHERE id = %s",
                (mgr_id, row["id"]),
            )
            matched += 1
        else:
            unmatched.add(raw)
    print(f"  compensation_manager_id resolved for {matched} employees")
    if unmatched:
        print(f"  unresolved comp managers ({len(unmatched)}): {sorted(unmatched)}")


def grant_module_access(cur, rows):
    """Create one hr_module_access row per (employee with company_email) per
    org_module of campo_caribe. Uses default flags from the table:
        is_enabled = true, can_edit = true, can_delete = false, can_verify = false
    """
    cur.execute("SELECT sys_module_id FROM org_module WHERE org_id = %s ORDER BY display_order", (ORG_ID,))
    module_ids = [r[0] for r in cur.fetchall()]

    employees_with_email = [r for r in rows if r["company_email"]]
    inserted = 0
    for emp in employees_with_email:
        for mod_id in module_ids:
            cur.execute("""
                INSERT INTO hr_module_access (org_id, hr_employee_id, sys_module_id,
                                              created_by, updated_by)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (hr_employee_id, sys_module_id) DO NOTHING
            """, (ORG_ID, emp["id"], mod_id, AUDIT_USER, AUDIT_USER))
            inserted += cur.rowcount
    print(f"  hr_module_access: {inserted} rows ({len(employees_with_email)} employees x {len(module_ids)} modules)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 60)
    print("CAMPO CARIBE — HR PROVISIONING & EMPLOYEE LOAD")
    print("=" * 60)

    print("\nReading source sheet...")
    gc = get_sheets_client()
    wb = gc.open_by_key(SHEET_ID)
    records = wb.worksheet("HR register").get_all_records()
    print(f"  {len(records)} employee records loaded")

    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            print("\n--- Provisioning org / modules / farm ---")
            provision_org(cur)
            provision_modules(cur)
            provision_sub_modules(cur)
            provision_farm(cur)
            provision_work_auth(cur)

            print("\n--- Loading departments ---")
            dept_map = load_departments(cur, records)

            print("\n--- Building employee rows ---")
            rows, name_to_id = build_employee_rows(records, dept_map)
            print(f"  parsed {len(rows)} employees")

            print("\n--- Inserting employees ---")
            insert_employees(cur, rows)

            print("\n--- Resolving compensation managers ---")
            resolve_comp_managers(cur, rows, name_to_id)

            print("\n--- Granting module access (employees with company_email) ---")
            grant_module_access(cur, rows)

        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
