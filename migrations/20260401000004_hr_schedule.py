"""
Migrate HR Daily Schedule
==========================
Migrates hr_ee_sched_daily from legacy Google Sheets to ops_task_schedule
as planned schedule entries (ops_task_tracker_id = null).

Also creates additional ops_task records for legacy task types not yet
provisioned (service, tearout, maintenance, corporate, other).

Source: https://docs.google.com/spreadsheets/d/13DUQTQyZf0CW07xv4FJ4ukP2x3Yoz8PyAw3Z2SwNsts
  - hr_ee_sched_daily: 22473 rows → ops_task_schedule (planned mode)

Usage:
    python scripts/migrations/20260401000004_hr_schedule.py

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

# Legacy task → (ops_task_id, farm_id)
# Tasks like PTO, Request Off, Sick Leave are time-off — skipped
TASK_MAP = {
    "cuke harvest":         ("harvesting", "cuke"),
    "harvest supervisor":   ("harvesting", "cuke"),
    "cuke ph":              ("packing", "cuke"),
    "cuke service":         ("service", "cuke"),
    "cuke service a":       ("service", "cuke"),
    "cuke service b":       ("service", "cuke"),
    "cuke service c":       ("service", "cuke"),
    "service supervisor":   ("service", "cuke"),
    "cuke tearout":         ("tearout", "cuke"),
    "cuke tearout a":       ("tearout", "cuke"),
    "cuke tearout b":       ("tearout", "cuke"),
    "cuke tearout c":       ("tearout", "cuke"),
    "tearout supervisor":   ("tearout", "cuke"),
    "cuke supervisor":      ("supervisor", "cuke"),
    "cukes supervisor":     ("supervisor", "cuke"),
    "lettuce gh":           ("harvesting", "lettuce"),
    "lettuce ph":           ("packing", "lettuce"),
    "maintenance":          ("maintenance", None),
    "corp":                 ("corporate", None),
    "other":                ("other", None),
}

# Additional ops_task records needed for legacy data
ADDITIONAL_TASKS = [
    ("service", "Service", "Greenhouse crop service and maintenance activities"),
    ("tearout", "Tearout", "Removing spent crops and preparing beds for replanting"),
    ("supervisor", "Supervisor", "Supervisory oversight of farm operations"),
    ("maintenance", "Maintenance", "Facility and equipment maintenance"),
    ("corporate", "Corporate", "Administrative and corporate activities"),
    ("other", "Other", "Miscellaneous tasks not classified elsewhere"),
]

# Time-off tasks — skipped from schedule migration
SKIP_TASKS = {"pto", "request off", "sick leave"}


# ─────────────────────────────────────────────────────────────
# STANDARD HELPERS
# ─────────────────────────────────────────────────────────────

def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def audit(row: dict) -> dict:
    """Add audit fields to a row."""
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


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


def parse_time(time_str):
    """Parse time string like '7:00:00', '15:30:00' to HH:MM:SS."""
    if not time_str or not str(time_str).strip():
        return None
    s = str(time_str).strip()
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(s, fmt).strftime("%H:%M:%S")
        except ValueError:
            continue
    return None


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# OPS TASK PROVISIONING
# ─────────────────────────────────────────────────────────────

def ensure_additional_tasks(supabase):
    """Create ops_task records for legacy task types not in the default provisioning."""
    existing = supabase.table("ops_task").select("id").execute()
    existing_ids = {t["id"] for t in existing.data}

    rows = []
    for task_id, name, desc in ADDITIONAL_TASKS:
        if task_id not in existing_ids:
            rows.append(audit({
                "id": task_id,
                "org_id": ORG_ID,
                "name": name,
                "description": desc,
            }))

    if rows:
        insert_rows(supabase, "ops_task", rows)
    else:
        print("  All additional tasks already exist")


# ─────────────────────────────────────────────────────────────
# SCHEDULE MIGRATION
# ─────────────────────────────────────────────────────────────

def migrate_schedule(supabase, gc):
    """Migrate hr_ee_sched_daily → ops_task_schedule (planned mode)."""
    wb = gc.open_by_key(HR_SHEET_ID)
    data = wb.worksheet("hr_ee_sched_daily").get_all_records()

    print(f"\nProcessing {len(data)} schedule rows...")

    # Build employee lookup by full name (uppercase in sheet)
    emp_result = supabase.table("hr_employee").select("id, first_name, last_name").execute()
    emp_by_name = {}
    for e in emp_result.data:
        full = f"{e['last_name']} {e['first_name']}".upper()
        emp_by_name[full] = e["id"]
        # Also try last_name only for partial matches
        emp_by_name[e["last_name"].upper()] = e["id"]

    dedup_map = {}  # (ops_task_id, emp_id, start_time) → row
    skipped = 0
    unmatched_employees = set()
    unmatched_tasks = set()

    for r in data:
        task_name = str(r.get("Task", "")).strip()
        if not task_name or task_name.lower() in SKIP_TASKS:
            skipped += 1
            continue

        # Resolve task
        mapping = TASK_MAP.get(task_name.lower())
        if not mapping:
            unmatched_tasks.add(task_name)
            skipped += 1
            continue
        ops_task_id, farm_id = mapping

        # Resolve employee
        full_name = str(r.get("FullName", "")).strip().upper()
        emp_id = emp_by_name.get(full_name)
        if not emp_id:
            unmatched_employees.add(full_name)
            skipped += 1
            continue

        # Parse date and times
        date = parse_date(r.get("Date"))
        if not date:
            skipped += 1
            continue

        start_time_str = parse_time(r.get("StartTime"))
        stop_time_str = parse_time(r.get("EndTime"))

        start_time = f"{date}T{start_time_str}" if start_time_str else f"{date}T07:00:00"
        stop_time = f"{date}T{stop_time_str}" if stop_time_str else None

        reported_by = str(r.get("UpdatedBy", "")).strip().lower() or AUDIT_USER

        # Deduplicate by (ops_task_id, hr_employee_id, start_time) — last row wins
        dedup_key = (ops_task_id, emp_id, start_time)
        row = {
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "ops_task_id": ops_task_id,
            "hr_employee_id": emp_id,
            "start_time": start_time,
            "stop_time": stop_time,
            "created_by": reported_by,
            "updated_by": reported_by,
        }
        dedup_map[dedup_key] = row

    rows = list(dedup_map.values())
    insert_rows(supabase, "ops_task_schedule", rows)

    if skipped:
        print(f"  Skipped {skipped} rows (time-off, unmapped task, unknown employee, missing date)")
    if unmatched_employees:
        print(f"  Unmatched employees ({len(unmatched_employees)}): {sorted(unmatched_employees)[:10]}...")
    if unmatched_tasks:
        print(f"  Unmatched tasks: {sorted(unmatched_tasks)}")


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("HR SCHEDULE MIGRATION")
    print("=" * 60)

    # Clear planned schedule entries (keep executed ones linked to trackers)
    print("\nClearing planned schedule entries...")
    supabase.table("ops_task_schedule").delete().is_("ops_task_tracker_id", "null").execute()
    print("  Cleared")

    # Step 1: Ensure additional ops_task records exist
    print("\nChecking additional task records...")
    ensure_additional_tasks(supabase)

    # Step 2: Migrate daily schedule
    migrate_schedule(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
