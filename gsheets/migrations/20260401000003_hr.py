"""
Migrate HR Lookup Data
=======================
Migrates hr_department and hr_work_authorization from
legacy Google Sheet (hr_ee_register) unique values to Supabase.

Source: https://docs.google.com/spreadsheets/d/13DUQTQyZf0CW07xv4FJ4ukP2x3Yoz8PyAw3Z2SwNsts
  - hr_department: unique values from 'Department' column
  - hr_work_authorization: unique values from 'Status' column

Usage:
    python scripts/migrations/20260401000003_hr.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
import sys
from pathlib import Path

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

sys.path.insert(0, str(Path(__file__).parent))
from gsheets.migrations._pg import get_pg_conn  # noqa: E402

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
SHEET_ID = "13DUQTQyZf0CW07xv4FJ4ukP2x3Yoz8PyAw3Z2SwNsts"


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
    from datetime import datetime
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def parse_timestamp(ts_str):
    """Parse timestamp to ISO format or None."""
    if not ts_str or not str(ts_str).strip():
        return None
    from datetime import datetime
    for fmt in ("%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%m/%d/%Y"):
        try:
            return datetime.strptime(str(ts_str).strip(), fmt).isoformat()
        except ValueError:
            continue
    return None


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


def get_sheet_records(gc):
    """Return hr_ee_register records from Google Sheets."""
    ws = gc.open_by_key(SHEET_ID).worksheet("hr_ee_register")
    return ws.get_all_records()


def get_app_users(gc):
    """Get global_app_users_list from the global spreadsheet."""
    ws = gc.open_by_key("1VOVyYt_Mk7QJkjZFRyq3iLf6xkBrZUWarobv7tf8yZA").worksheet("global_app_users_list")
    return ws.get_all_records()


def migrate_hr_department(supabase, records):
    """Migrate unique departments from hr_ee_register."""
    departments = sorted(set(
        str(r.get("Department", "")).strip()
        for r in records
        if str(r.get("Department", "")).strip()
    ))

    rows = [
        audit({
            "id": d,
            "org_id": ORG_ID,
        })
        for d in departments
    ]
    insert_rows(supabase, "hr_department", rows, upsert=True)


def migrate_hr_work_authorization(supabase, records):
    """Migrate unique work authorization types from hr_ee_register Status column."""
    statuses = sorted(set(
        str(r.get("Status", "")).strip()
        for r in records
        if str(r.get("Status", "")).strip()
    ))

    rows = [
        audit({
            "id": s,
            "org_id": ORG_ID,
        })
        for s in statuses
    ]
    insert_rows(supabase, "hr_work_authorization", rows, upsert=True)


def migrate_hr_employee(supabase, records, app_users):
    """Migrate employees from hr_ee_register + global_app_users_list."""

    # Build app_users lookup by email
    user_lookup = {}
    level_map = {1: "employee", 2: "manager", 3: "admin", "1": "employee", "2": "manager", "3": "admin"}
    for u in app_users:
        email = str(u.get("Email", "")).strip().lower()
        if email:
            user_lookup[email] = u

    # Module name mapping for InAppViews
    module_map = {
        "grow": "grow", "pack": "pack", "food safety": "food_safety",
        "maintenance": "maintenance", "inventory": "inventory",
        "human resources": "human_resources", "sales": "sales",
        "execute": "operations", "global": "operations",
    }

    # Housing site ID mapping
    # Housing site id is the display name verbatim (org_site_housing.id).
    # Sheet values already match — no transformation needed.

    # First pass: build employee rows and name-to-id map
    employees = []
    name_to_id = {}  # ShortName/FirstName -> employee_id for resolving team_lead/comp_manager

    for r in records:
        first = proper_case(r.get("FirstName", ""))
        last = proper_case(r.get("LastName", ""))
        full = str(r.get("FullName", "")).strip()
        if not first or not last:
            continue

        emp_id = to_id(full)
        email = str(r.get("Email", "")).strip().lower()
        short = proper_case(r.get("ShortName", ""))

        # Map name for team_lead/compensation_manager resolution
        if short:
            name_to_id[short] = emp_id
        name_to_id[first] = emp_id

        # Get access level from app_users
        app_user = user_lookup.get(email, {})
        level = app_user.get("Level", 1)
        access_level = level_map.get(level, "employee")

        # Gender
        gender = str(r.get("Gender", "")).strip().lower()
        if gender not in ("male", "female"):
            gender = None

        # Pay structure
        pay = str(r.get("PayStructure", "")).strip().lower()
        if pay not in ("hourly", "salary"):
            pay = None

        # Housing — sheet value is the org_site_housing.id verbatim
        site_id = str(r.get("Housing", "")).strip() or None

        # Department / work auth (FK lookup)
        dept = str(r.get("Department", "")).strip()
        status = str(r.get("Status", "")).strip()

        # Overtime threshold
        ot = r.get("OvertimeThreshold", "")
        ot_val = float(ot) if ot and str(ot).strip() else None

        # WC code — preserve leading zeros (e.g. "0008")
        wc_raw = r.get("WorkersCompensationCode", "")
        if wc_raw and str(wc_raw).strip():
            wc = str(int(wc_raw)).zfill(4) if str(wc_raw).strip().isdigit() else str(wc_raw).strip()
        else:
            wc = None

        emp = {
            "id": emp_id,
            "org_id": ORG_ID,
            "first_name": first,
            "last_name": last,
            "preferred_name": short or None,
            "gender": gender,
            "date_of_birth": parse_date(r.get("DateOfBirth", "")),
            "ethnicity": "Non-Caucasian" if parse_bool(r.get("IsMinority", False)) else "Caucasian",
            "profile_photo_url": (str(r.get("Photograph", "")).strip().replace("images/hr_photo/", "images/hr_employee/") or None),
            "phone": str(r.get("Phone", "")).strip() or None,
            "company_email": email or None,
            "is_primary_org": True,
            "hr_department_id": dept or None,
            "sys_access_level_name": access_level,
            "is_manager": parse_bool(r.get("IsManager", False)),
            "hr_work_authorization_id": status or None,
            "start_date": parse_date(r.get("StartDate", "")),
            "end_date": parse_date(r.get("EndDate", "")),
            "payroll_id": str(r.get("employee_id", "")).strip() or None,
            "pay_structure": pay,
            "overtime_threshold": ot_val,
            "wc": wc,
            "payroll_processor": str(r.get("Source", "")).strip() or None,
            "pay_delivery_method": proper_case(r.get("Check", "")) or None,
            "housing_name": site_id,
            "is_deleted": not parse_bool(r.get("IsActive", True)),
        }
        employees.append(audit(emp))

    # Insert employees (without team_lead/comp_manager — self-referencing).
    # Pure INSERT: _clear_transactional.py has already truncated hr_employee
    # and its FK chain, so there's nothing to upsert against. Using upsert
    # here would re-introduce the legacy id-drift collision on uq_hr_employee_name.
    insert_rows(supabase, "hr_employee", employees, upsert=False)

    # Second pass: update team_lead_id and compensation_manager_id
    print("  Resolving team_lead_id and compensation_manager_id...")
    updates = 0
    for r in records:
        full = str(r.get("FullName", "")).strip()
        if not full:
            continue
        emp_id = to_id(full)

        team_lead = str(r.get("TeamLead", "")).strip()
        comp_mgr = str(r.get("CompensationManager", "")).strip()

        patch = {}
        if team_lead and team_lead in name_to_id:
            patch["team_lead_id"] = name_to_id[team_lead]
        if comp_mgr and comp_mgr in name_to_id:
            patch["compensation_manager_id"] = name_to_id[comp_mgr]

        if patch:
            supabase.table("hr_employee").update(patch).eq("id", emp_id).execute()
            updates += 1

    print(f"  Updated {updates} employees with team_lead/compensation_manager")

    return employees, user_lookup, module_map


def migrate_hr_module_access(supabase, employees, app_users_lookup, module_map):
    """Create hr_module_access rows based on global_app_users_list InAppViews."""

    rows = []
    for emp in employees:
        email = (emp.get("company_email") or "").lower()
        app_user = app_users_lookup.get(email, {})
        views = str(app_user.get("InAppViews", "")).strip()
        is_verifier = parse_bool(app_user.get("IsVerifier", False))

        if not views:
            continue

        # Parse "Grow & Pack & Food Safety & ..." into module IDs
        modules_seen = set()
        for view_name in views.split("&"):
            view_name = view_name.strip().lower()
            mod_id = module_map.get(view_name)
            if mod_id and mod_id not in modules_seen:
                modules_seen.add(mod_id)
                rows.append(audit({
                    "org_id": ORG_ID,
                    "hr_employee_id": emp["id"],
                    "org_module_name": mod_id,
                    "is_enabled": True,
                    "can_edit": True,
                    "can_delete": False,
                    "can_verify": is_verifier,
                    "is_deleted": emp.get("is_deleted", False),
                }))

    insert_rows(supabase, "hr_module_access", rows)


def migrate_hr_time_off_request(supabase, gc, emp_records):
    """Migrate time off requests from hr_ee_time_off_request sheet."""
    ws = gc.open_by_key(SHEET_ID).worksheet("hr_ee_time_off_request")
    records = ws.get_all_records()

    # Build employee lookups: full_name -> id, email -> id
    name_to_id = {}
    email_to_id = {}
    for r in emp_records:
        full = str(r.get("FullName", "")).strip()
        email = str(r.get("Email", "")).strip().lower()
        if full:
            name_to_id[to_id(full)] = to_id(full)
        if email:
            email_to_id[email] = to_id(full)

    # Status mapping
    status_map = {
        "approved": "approved",
        "denied": "denied",
        "not approved": "denied",
        "pending": "pending",
    }

    rows = []
    for r in records:
        full_name = str(r.get("FullName", "")).strip()
        if not full_name:
            continue

        emp_id = to_id(full_name)
        if emp_id not in name_to_id:
            print(f"  SKIP: Unknown employee '{full_name}'")
            continue

        # Resolve requested_by and reviewed_by by email
        requested_by_email = str(r.get("RequestedBy", "")).strip().lower()
        updated_by_email = str(r.get("UpdatedBy", "")).strip().lower()
        requested_by = email_to_id.get(requested_by_email)
        reviewed_by = email_to_id.get(updated_by_email)

        # Status
        raw_status = str(r.get("RequestStatus", "")).strip().lower()
        status = status_map.get(raw_status, "pending")

        # Parse numeric fields
        pto = r.get("PTODays", "")
        pto_days = float(pto) if pto and str(pto).strip() else None

        non_pto = r.get("RequestOffDays", "")
        non_pto_days = float(non_pto) if non_pto and str(non_pto).strip() else None

        sick = r.get("SickLeaveDays", "")
        sick_days = float(sick) if sick and str(sick).strip() else None

        # reviewed_at only if not pending
        reviewed_at = parse_timestamp(r.get("UpdatedDateTime", "")) if status != "pending" else None

        # Check if employee is deleted
        emp_is_deleted = not parse_bool(
            next((e.get("IsActive", True) for e in emp_records if to_id(str(e.get("FullName", ""))) == emp_id), True)
        )

        row = {
            "org_id": ORG_ID,
            "hr_employee_id": emp_id,
            "start_date": parse_date(r.get("StartDate", "")),
            "return_date": parse_date(r.get("ReturnDate", "")),
            "non_pto_days": non_pto_days,
            "pto_days": pto_days,
            "sick_leave_days": sick_days,
            "request_reason": str(r.get("Reason", "")).strip() or None,
            "notes": str(r.get("CompensationManagerNotes", "")).strip() or None,
            "status": status,
            "requested_at": parse_timestamp(r.get("RequestDateTime", "")),
            "requested_by": requested_by or emp_id,
            "reviewed_at": reviewed_at,
            "reviewed_by": reviewed_by if status != "pending" else None,
            "is_deleted": emp_is_deleted,
        }
        rows.append(audit(row))

    insert_rows(supabase, "hr_time_off_request", rows)


def migrate_hr_travel_request(supabase, gc, emp_records):
    """Migrate travel requests from proc_requests sheet (request_type = Travel)."""
    ws = gc.open_by_key("1EFgT0XyBlUe10ENVkm4-_bb4uSPyd9hPbCIzD-RKNRA").worksheet("proc_requests")
    records = ws.get_all_records()

    # Build email -> employee ID lookup
    email_to_id = {}
    name_to_id = {}
    for r in emp_records:
        email = str(r.get("Email", "")).strip().lower()
        full = str(r.get("FullName", "")).strip()
        if email:
            email_to_id[email] = to_id(full)
        if full:
            name_to_id[to_id(full)] = to_id(full)

    rows = []
    for r in records:
        req_type = str(r.get("request_type", "")).strip()
        if req_type != "Travel":
            continue

        # Resolve traveler to employee ID
        traveler = str(r.get("traveler_name", "")).strip()
        emp_id = name_to_id.get(to_id(traveler))
        if not emp_id:
            print(f"  SKIP travel: Unknown traveler '{traveler}'")
            continue

        # Resolve created_by
        created_email = str(r.get("created_by", "")).strip().lower()
        requested_by = email_to_id.get(created_email, emp_id)

        # Resolve updated_by for review
        updated_email = str(r.get("updated_by", "")).strip().lower()
        reviewed_by = email_to_id.get(updated_email)

        status = str(r.get("request_status", "")).strip().lower()
        status_map = {"requested": "pending", "ordered": "approved"}
        mapped_status = status_map.get(status, "pending")

        row = {
            "org_id": ORG_ID,
            "hr_employee_id": emp_id,
            "request_type": proper_case(r.get("travel_type", "")) or None,
            "travel_from": proper_case(r.get("flight_from", "")) or None,
            "travel_to": proper_case(r.get("flight_to", "")) or None,
            "travel_start_date": parse_date(r.get("departure_date", "")),
            "travel_return_date": parse_date(r.get("return_date", "")),
            "notes": str(r.get("request_notes", "")).strip() or None,
            "status": mapped_status,
            "requested_at": parse_timestamp(r.get("created_on", "")),
            "requested_by": requested_by,
            "reviewed_at": parse_timestamp(r.get("updated_on", "")) if mapped_status == "approved" else None,
            "reviewed_by": reviewed_by if mapped_status == "approved" else None,
        }
        rows.append(audit(row))

    insert_rows(supabase, "hr_travel_request", rows)


def relink_auth_users(supabase):
    """Restore hr_employee.user_id from auth.users.email.

    _clear_transactional.py truncates hr_employee nightly, which wipes the
    user_id column set by the handle_new_auth_user() trigger at signup.
    Without this re-link, every logged-in user loses RLS access until they
    re-sign-in (and the trigger only fires on new auth.users rows, not
    on sign-in). Match by lowercased email — both columns are email-keyed.
    """
    print("\n--- auth re-link ---")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE hr_employee he
                SET user_id = au.id
                FROM auth.users au
                WHERE lower(he.company_email) = lower(au.email)
                  AND he.user_id IS DISTINCT FROM au.id
            """)
            linked = cur.rowcount
        conn.commit()
    print(f"  Re-linked {linked} hr_employee.user_id values from auth.users")


def main():
    if not SUPABASE_KEY:
        print("ERROR: Set SUPABASE_SERVICE_KEY in .env or environment")
        return

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("Reading hr_ee_register from Google Sheets...")
    records = get_sheet_records(gc)
    print(f"  {len(records)} records loaded")

    print("Reading global_app_users_list from Google Sheets...")
    app_users = get_app_users(gc)
    print(f"  {len(app_users)} app users loaded")

    # Pre-clear is handled by _clear_transactional.py before this migration
    # runs in the nightly workflow. If running locally without that step,
    # invoke `python migrations/_clear_transactional.py` first.

    migrate_hr_department(supabase, records)
    migrate_hr_work_authorization(supabase, records)

    employees, user_lookup, module_map = migrate_hr_employee(supabase, records, app_users)
    migrate_hr_module_access(supabase, employees, user_lookup, module_map)
    migrate_hr_time_off_request(supabase, gc, records)
    migrate_hr_travel_request(supabase, gc, records)

    relink_auth_users(supabase)

    print("\nHR data migrated successfully")


if __name__ == "__main__":
    main()
