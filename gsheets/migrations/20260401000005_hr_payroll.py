"""
Migrate HR Payroll Data
========================
Migrates hr_ee_payroll from legacy Google Sheets to hr_payroll.
Auto-creates inactive hr_employee records for former employees
not in the current HR register.

Source: https://docs.google.com/spreadsheets/d/13DUQTQyZf0CW07xv4FJ4ukP2x3Yoz8PyAw3Z2SwNsts
  - hr_ee_payroll: 11513 rows → hr_payroll

Usage:
    python scripts/migrations/20260401000005_hr_payroll.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
from datetime import datetime

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

HR_SHEET_ID = "13DUQTQyZf0CW07xv4FJ4ukP2x3Yoz8PyAw3Z2SwNsts"

# Department mapping from payroll values to hr_department IDs.
# hr_department.id is seeded from the hr_ee_register 'Department' column
# with original casing ("GH", "PH", "Corp", "Lettuce", "Maintenance"),
# so values here must match that casing or FK inserts fail.
DEPT_MAP = {
    "gh": "GH",
    "ph": "PH",
    "lettuce": "Lettuce",
    "maintenance": "Maintenance",
    "corp": "Corp",
    "const": "Corp",  # Construction → Corp
}


# ─────────────────────────────────────────────────────────────
# STANDARD HELPERS
# ─────────────────────────────────────────────────────────────

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


def parse_date(date_str):
    """Parse date string to YYYY-MM-DD or None."""
    if not date_str or not str(date_str).strip():
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# AUTO-CREATE MISSING EMPLOYEES
# ─────────────────────────────────────────────────────────────

def ensure_missing_employees(supabase, data, emp_by_pid, emp_by_name):
    """Auto-create inactive hr_employee records for former employees in payroll data."""
    missing = {}  # name → {payroll_id, department}
    for r in data:
        eid = str(r.get("employee_id", "")).strip()
        name = str(r.get("full_name", "")).strip().upper()
        if not name or name == "ADJUSTMENT":
            continue
        if eid and emp_by_pid.get(eid):
            continue
        if emp_by_name.get(name):
            continue

        # Collect info from first occurrence
        if name not in missing:
            dept = str(r.get("department", "")).strip().lower()
            status = str(r.get("status", "")).strip()
            wc = str(r.get("workers_compensation_code", "")).strip() or None
            source = str(r.get("source", "")).strip() or None
            missing[name] = {
                "payroll_id": eid or None,
                "department": DEPT_MAP.get(dept),
                "status": status,
                "wc": wc,
                "source": source,
            }

    if not missing:
        print("  No missing employees")
        return

    # Parse names: "LASTNAME FIRSTNAME" or "LASTNAME FIRSTNAME MIDDLE"
    rows = []
    for name, info in sorted(missing.items()):
        parts = name.split()
        if len(parts) >= 2:
            last = proper_case(parts[0])
            first = proper_case(" ".join(parts[1:]))
        else:
            last = proper_case(name)
            first = "Unknown"

        emp_id = to_id(name)
        rows.append(audit({
            "name": emp_id,
            "org_id": ORG_ID,
            "first_name": first,
            "last_name": last,
            "is_primary_org": True,
            "sys_access_level_name": "Employee",
            "hr_department_name": info["department"],
            "payroll_id": info["payroll_id"],
            "wc": info["wc"],
            "payroll_processor": info["source"],
            "is_deleted": True,
        }))

    insert_rows(supabase, "hr_employee", rows, upsert=True)
    print(f"  Auto-created {len(rows)} inactive former employees")


# ─────────────────────────────────────────────────────────────
# PAYROLL MIGRATION
# ─────────────────────────────────────────────────────────────

def migrate_payroll(supabase, gc):
    """Migrate hr_ee_payroll → hr_payroll.

    Uses UNFORMATTED_VALUE so numeric cells come through at full precision.
    gspread's default get_all_records() returns display values which round
    decimals like total_hours=118.36 down to 118 when the column is formatted
    as an integer, silently corrupting downstream ratio math.
    """
    wb = gc.open_by_key(HR_SHEET_ID)
    ws = wb.worksheet("hr_ee_payroll")
    # date_time_render_option keeps date cells as their formatted string so
    # parse_date can read them as "M/D/YYYY"; UNFORMATTED_VALUE only changes
    # how numeric cells are returned.
    raw = ws.get_all_values(
        value_render_option="UNFORMATTED_VALUE",
        date_time_render_option="FORMATTED_STRING",
    )
    headers = raw[0]
    data = [dict(zip(headers, row)) for row in raw[1:]]

    print(f"\nProcessing {len(data)} payroll rows...")

    # Build employee lookups
    emps = supabase.table("hr_employee").select(
        "name, first_name, last_name, payroll_id, hr_department_name, "
        "hr_work_authorization_name, wc, pay_structure, overtime_threshold"
    ).execute()

    emp_by_pid = {}
    emp_by_name = {}
    for e in emps.data:
        if e.get("payroll_id"):
            emp_by_pid[e["payroll_id"]] = e
        full = f"{e['last_name']} {e['first_name']}".upper()
        emp_by_name[full] = e

    # Auto-create missing employees
    print("\nChecking for missing employees...")
    ensure_missing_employees(supabase, data, emp_by_pid, emp_by_name)

    # Refresh lookups after auto-create
    emps = supabase.table("hr_employee").select(
        "name, first_name, last_name, payroll_id, hr_department_name, "
        "hr_work_authorization_name, wc, pay_structure, overtime_threshold"
    ).execute()
    emp_by_pid = {}
    emp_by_name = {}
    for e in emps.data:
        if e.get("payroll_id"):
            emp_by_pid[e["payroll_id"]] = e
        full = f"{e['last_name']} {e['first_name']}".upper()
        emp_by_name[full] = e

    # Work authorization lookup — hr_work_authorization has no 'name' column;
    # its id IS the display value (e.g. "H2A", "1099", "FUERTE"), so match on id.
    wa_result = supabase.table("hr_work_authorization").select("name").execute()
    wa_by_name = {w["name"].lower(): w["name"] for w in wa_result.data}

    rows = []
    skipped_adjustment = 0
    skipped_no_name = 0
    auto_created_emps = set()

    for r in data:
        name = str(r.get("full_name", "")).strip().upper()
        if not name:
            skipped_no_name += 1
            continue
        # ADJUSTMENT rows are aggregate non-employee payroll lines (e.g.
        # quarter-end true-ups). They have no employee to attach to and
        # don't represent a specific person's pay.
        if name == "ADJUSTMENT":
            skipped_adjustment += 1
            continue

        # Resolve employee — falls back to inline auto-create if neither
        # the prior pre-pass nor the lookups find a match.
        eid = str(r.get("employee_id", "")).strip()
        emp = emp_by_pid.get(eid) if eid else None
        if not emp:
            emp = emp_by_name.get(name)
        if not emp:
            # Inline auto-create as a safety net for rows the prior pass
            # didn't catch (e.g. names with parsing edge cases).
            new_id = to_id(name)
            if new_id:
                parts = name.split()
                last = proper_case(parts[0]) if parts else proper_case(name)
                first = proper_case(" ".join(parts[1:])) if len(parts) >= 2 else "Unknown"
                stub = {
                    "name": new_id,
                    "org_id": ORG_ID,
                    "first_name": first,
                    "last_name": last,
                    "is_primary_org": True,
                    "sys_access_level_name": "Employee",
                    "payroll_id": eid or new_id,
                    "is_deleted": True,
                    "created_by": AUDIT_USER,
                    "updated_by": AUDIT_USER,
                }
                try:
                    supabase.table("hr_employee").upsert(stub).execute()
                    emp = stub
                    emp_by_name[name] = stub
                    if eid:
                        emp_by_pid[eid] = stub
                    auto_created_emps.add(new_id)
                except Exception as e:
                    print(f"  WARN failed to auto-create hr_employee {new_id!r}: {type(e).__name__}: {e}")
                    continue
            else:
                continue

        # Pay period comes as a single string "M/D/YYYY - M/D/YYYY" in the
        # legacy sheet. The y1/m1/d1/y2/m2/d2 columns are *not* start/end
        # dates — they're month-split day counts used by legacy reporting —
        # so parse the pay_period string directly.
        pay_period_str = str(r.get("pay_period", "")).strip()
        pay_period_start = None
        pay_period_end = None
        if " - " in pay_period_str:
            start_str, end_str = pay_period_str.split(" - ", 1)
            pay_period_start = parse_date(start_str.strip())
            pay_period_end = parse_date(end_str.strip())

        # check_date is NOT NULL on hr_payroll, so we need a value. Try the
        # sheet's check_date first, then fall back to pay_period_end, then
        # pay_period_start. If all are missing the row is genuinely undated
        # and we skip — that case should be vanishingly rare.
        check_date = parse_date(r.get("check_date"))
        if not check_date:
            check_date = pay_period_end or pay_period_start
        if not check_date:
            skipped_no_name += 1
            continue

        # Fallback: use check_date if pay period dates missing
        if not pay_period_start:
            pay_period_start = check_date
        if not pay_period_end:
            pay_period_end = check_date

        # Snapshot fields from employee record
        dept = str(r.get("department", "")).strip().lower()
        dept_id = DEPT_MAP.get(dept) or emp.get("hr_department_name")

        status = str(r.get("status", "")).strip()
        wa_id = wa_by_name.get(status.lower()) or emp.get("hr_work_authorization_name")

        wc = str(r.get("workers_compensation_code", "")).strip() or emp.get("wc")
        pay_structure = str(r.get("pay_structure", "")).strip().lower() or emp.get("pay_structure")
        if pay_structure and pay_structure not in ("hourly", "salary"):
            pay_structure = emp.get("pay_structure")

        source = str(r.get("source", "")).strip() or "HRB"
        hourly_rate = safe_numeric(r.get("hourly_rate"), default=None)
        ot_threshold = safe_numeric(r.get("overtime_threashold"), default=None) or emp.get("overtime_threshold")

        row = {
            "org_id": ORG_ID,
            "hr_employee_name": emp["name"],
            "payroll_id": eid or emp.get("payroll_id") or emp["name"],
            "pay_period_start": pay_period_start,
            "pay_period_end": pay_period_end,
            "check_date": check_date,
            "invoice_number": str(r.get("invoice_number", "")).strip() or None,
            "payroll_processor": source,
            "is_standard": str(r.get("is_standard", "")).strip().lower() == "true",
            "employee_name": proper_case(name),
            "hr_department_name": dept_id,
            "hr_work_authorization_name": wa_id,
            "wc": wc if wc else None,
            "pay_structure": pay_structure,
            "hourly_rate": hourly_rate,
            "overtime_threshold": ot_threshold,
            # Hours
            "regular_hours": safe_numeric(r.get("regular_hours")),
            "overtime_hours": safe_numeric(r.get("overtime_hours")),
            "discretionary_overtime_hours": safe_numeric(r.get("discretionary_overtime_hours")),
            "pto_hours": safe_numeric(r.get("pto_hours_taken")),
            "total_hours": safe_numeric(r.get("total_hours")),
            "pto_hours_accrued": safe_numeric(r.get("pto_hours_accrued")),
            # Earnings
            "regular_pay": safe_numeric(r.get("regular_pay")),
            "overtime_pay": safe_numeric(r.get("overtime_pay")),
            "discretionary_overtime_pay": safe_numeric(r.get("discretionary_overtime_pay")),
            "pto_pay": safe_numeric(r.get("pto_pay")),
            "other_pay": safe_numeric(r.get("other_pay")),
            "bonus_pay": safe_numeric(r.get("bonus_pay")),
            "auto_allowance": safe_numeric(r.get("allowance_auto")),
            "per_diem": safe_numeric(r.get("allowance_per_diem")),
            "gross_wage": safe_numeric(r.get("gross_wage")),
            # Deductions
            "fit": safe_numeric(r.get("fit")),
            "sit": safe_numeric(r.get("sit")),
            "social_security": safe_numeric(r.get("social_security")),
            "medicare": safe_numeric(r.get("medicare")),
            "comp_plus": safe_numeric(r.get("comp_plus")),
            "hds_dental": safe_numeric(r.get("hds_dental")),
            "pre_tax_401k": safe_numeric(r.get("pre_tax_401k")),
            "auto_deduction": safe_numeric(r.get("auto_deduction")),
            "child_support": safe_numeric(r.get("child_support")),
            "program_fees": safe_numeric(r.get("program_fees")),
            "net_pay": safe_numeric(r.get("net_pay")),
            # Employer costs
            "labor_tax": safe_numeric(r.get("labor_tax")),
            "other_tax": safe_numeric(r.get("other_tax")),
            "workers_compensation": safe_numeric(r.get("workers_compensation")),
            "health_benefits": safe_numeric(r.get("health_benefits")),
            "other_health_charges": safe_numeric(r.get("other_health_charges")),
            "admin_fees": safe_numeric(r.get("admin_fees")),
            "hawaii_get": safe_numeric(r.get("hawaii_get")),
            "other_charges": safe_numeric(r.get("other_charges")),
            "tdi": safe_numeric(r.get("ex_invoice_tdi")),
            "total_cost": safe_numeric(r.get("total_cost")),
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }
        rows.append(row)

    insert_rows(supabase, "hr_payroll", rows)
    if auto_created_emps:
        print(f"  Inline-created {len(auto_created_emps)} additional employee stubs")
    if skipped_adjustment:
        print(f"  Skipped {skipped_adjustment} ADJUSTMENT rows (aggregate non-employee payroll lines)")
    if skipped_no_name:
        print(f"  Skipped {skipped_no_name} rows with empty name or no parseable date")


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("HR PAYROLL MIGRATION")
    print("=" * 60)

    # Clear payroll data
    print("\nClearing hr_payroll...")
    supabase.table("hr_payroll").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    print("  Cleared")

    migrate_payroll(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
