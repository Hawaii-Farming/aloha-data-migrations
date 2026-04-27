"""
Migrate HR Daily Schedule
==========================
Seeds ops_task rows from the hr_ee_tasks tab (granular legacy task names
with QuickBooks accounts) and migrates hr_ee_sched_daily rows to
ops_task_schedule planned entries (ops_task_tracker_id = null).

Source: https://docs.google.com/spreadsheets/d/13DUQTQyZf0CW07xv4FJ4ukP2x3Yoz8PyAw3Z2SwNsts
  - hr_ee_tasks:       23 rows → ops_task (seed, upsert)
  - hr_ee_sched_daily: 22473 rows → ops_task_schedule (planned mode)

Usage:
    python scripts/migrations/20260401000004_hr_schedule.py

Rerunnable: clears planned schedule entries and reseeds tasks on each run.
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

# Time-off tasks — still seeded as ops_task rows, but never inserted into
# ops_task_schedule (they're not labor to schedule).
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


def safe_float(val):
    """Parse a numeric cell to float or None when blank/invalid."""
    s = str(val).strip()
    if not s:
        return None
    try:
        return float(s.replace(",", ""))
    except ValueError:
        return None


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# OPS TASK PROVISIONING
# ─────────────────────────────────────────────────────────────

def derive_farm_id(task_name: str) -> str | None:
    """Infer farm_id from a task name prefix.

    "Cuke *" → "Cuke", "Lettuce *" → "Lettuce", else None.
    """
    key = task_name.strip().lower()
    if key.startswith("cuke"):
        return "Cuke"
    if key.startswith("lettuce"):
        return "Lettuce"
    return None


def seed_tasks_from_sheet(supabase, gc) -> dict:
    """Seed ops_task rows from the hr_ee_tasks tab.

    Tab columns: Task, QuickBooksAccount. Each row becomes one ops_task row:
      id         = slugified Task (e.g. "Cuke Service A" → "cuke_service_a")
      name       = Task as-is (display)
      qb_account = QuickBooksAccount (empty string → None)
      farm_id    = derived from name prefix (Cuke/Lettuce), else None

    Uses upsert so the seed can overlay rows already created by org.py defaults
    (e.g. "maintenance") without conflict. Returns a lookup map used by the
    schedule migration to resolve task names.

    Returns: {task_name.lower(): (ops_task_id, farm_id)}
    """
    ws = gc.open_by_key(HR_SHEET_ID).worksheet("hr_ee_tasks")
    raw = ws.get_all_records()

    rows = []
    task_map = {}
    for r in raw:
        task_name = str(r.get("Task", "")).strip()
        if not task_name:
            continue
        qb_account = str(r.get("QuickBooksAccount", "")).strip() or None
        farm_id = derive_farm_id(task_name)

        rows.append({
            "org_id": ORG_ID,
            "id": task_name,
            "qb_account": qb_account,
            "farm_id": farm_id,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })
        task_map[task_name.lower()] = (task_name, farm_id)

    print("\n--- ops_task (seed from hr_ee_tasks tab) ---")
    for row in rows:
        supabase.table("ops_task").upsert(row).execute()
    print(f"  Upserted {len(rows)} rows")

    return task_map


# ─────────────────────────────────────────────────────────────
# SCHEDULE MIGRATION
# ─────────────────────────────────────────────────────────────

def _resolve_or_create_task(
    supabase, task_name: str, task_map: dict, task_cache: dict
) -> tuple[str, str | None]:
    """Resolve a sheet task name to (ops_task_id, farm_id).

    task_map is the tab-sourced seed (authoritative). task_cache tracks
    auto-created tasks discovered in this run to avoid duplicate upserts.
    Falls back to creating a new ops_task row when the name isn't in either.
    """
    key = task_name.lower()
    if key in task_map:
        return task_map[key]
    if key in task_cache:
        return task_cache[key]

    farm_id = derive_farm_id(task_name)
    try:
        supabase.table("ops_task").upsert({
            "org_id": ORG_ID,
            "id": task_name,
            "farm_id": farm_id,
            "description": f"Auto-created from legacy schedule (task name: {task_name!r})",
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }).execute()
    except Exception as e:
        print(f"  WARN failed to auto-create ops_task {task_name!r}: {type(e).__name__}: {e}")
        task_cache[key] = ("Other", None)
        return task_cache[key]

    print(f"  Auto-created ops_task: {task_name!r}")
    task_cache[key] = (task_name, farm_id)
    return task_cache[key]


def _resolve_or_create_employee(supabase, full_name: str, emp_by_name: dict) -> str | None:
    """Resolve a sheet 'LASTNAME FIRSTNAME' string to hr_employee.id.

    Falls back to creating an inactive (is_deleted=true) stub employee when
    the name isn't in the existing lookup. Mutates emp_by_name with the new id.

    Returns None when the name can't be parsed at all (empty/whitespace).
    """
    if full_name in emp_by_name:
        return emp_by_name[full_name]
    if not full_name.strip():
        return None

    parts = full_name.split()
    if len(parts) >= 2:
        last = proper_case(parts[0])
        first = proper_case(" ".join(parts[1:]))
    else:
        last = proper_case(full_name)
        first = "Unknown"

    emp_id = to_id(full_name)
    if not emp_id:
        return None

    try:
        supabase.table("hr_employee").upsert({
            "id": emp_id,
            "org_id": ORG_ID,
            "first_name": first,
            "last_name": last,
            "is_primary_org": True,
            "sys_access_level_id": "Employee",
            "is_deleted": True,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }).execute()
    except Exception as e:
        print(f"  WARN failed to auto-create hr_employee {emp_id!r}: {type(e).__name__}: {e}")
        return None

    print(f"  Auto-created inactive hr_employee: {emp_id!r} (from legacy name {full_name!r})")
    emp_by_name[full_name] = emp_id
    # Also register the last-name-only key
    emp_by_name[last.upper()] = emp_id
    return emp_id


def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()


def migrate_schedule(supabase, gc, task_map: dict):
    """Migrate hr_ee_sched_daily → ops_task_schedule (planned mode).

    task_map is the tab-sourced {task_name_lower: (ops_task_id, farm_id)}
    from seed_tasks_from_sheet. Auto-creates missing ops_task records and
    inactive hr_employee stubs inline rather than dropping rows. Time-off
    rows (PTO/Request Off/Sick Leave) and rows with unparseable dates are
    still skipped.
    """
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

    task_cache = {}  # task_name.lower() -> (ops_task_id, farm_id)  [auto-created only]
    dedup_map = {}   # (ops_task_id, emp_id, start_time) → row
    skipped_timeoff = 0
    skipped_no_date = 0
    skipped_no_emp = 0
    skipped_no_task = 0
    auto_created_tasks = set()
    auto_created_emps = set()

    for r in data:
        task_name = str(r.get("Task", "")).strip()
        if not task_name:
            skipped_no_task += 1
            continue
        if task_name.lower() in SKIP_TASKS:
            skipped_timeoff += 1
            continue

        # Resolve task (auto-create if unmapped)
        key = task_name.lower()
        was_known = key in task_map or key in task_cache
        ops_task_id, farm_id = _resolve_or_create_task(supabase, task_name, task_map, task_cache)
        if not was_known:
            auto_created_tasks.add(ops_task_id)

        # Resolve employee (auto-create stub if unknown)
        full_name = str(r.get("FullName", "")).strip().upper()
        was_known_emp = full_name in emp_by_name
        emp_id = _resolve_or_create_employee(supabase, full_name, emp_by_name)
        if not emp_id:
            skipped_no_emp += 1
            continue
        if not was_known_emp:
            auto_created_emps.add(emp_id)

        # Parse date and times
        date = parse_date(r.get("Date"))
        if not date:
            skipped_no_date += 1
            continue

        start_time_str = parse_time(r.get("StartTime"))
        stop_time_str = parse_time(r.get("EndTime"))

        start_time = f"{date}T{start_time_str}" if start_time_str else f"{date}T07:00:00"
        stop_time = f"{date}T{stop_time_str}" if stop_time_str else None

        # Sheet's Hours column already has the 30-min lunch deduction applied.
        # Capturing it directly — stop_time - start_time over-counts otherwise.
        total_hours = safe_float(r.get("Hours"))

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
            "total_hours": total_hours,
            "created_by": reported_by,
            "updated_by": reported_by,
        }
        dedup_map[dedup_key] = row

    rows = list(dedup_map.values())
    insert_rows(supabase, "ops_task_schedule", rows)

    print(f"  Auto-created {len(auto_created_tasks)} ops_tasks, {len(auto_created_emps)} inactive employees")
    if skipped_timeoff:
        print(f"  Skipped {skipped_timeoff} time-off rows (PTO / Request Off / Sick Leave)")
    if skipped_no_date:
        print(f"  Skipped {skipped_no_date} rows with no parseable date")
    if skipped_no_emp:
        print(f"  Skipped {skipped_no_emp} rows where employee name couldn't be parsed at all")
    if skipped_no_task:
        print(f"  Skipped {skipped_no_task} rows with empty Task")


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

    # Step 1: Seed ops_task from hr_ee_tasks tab (authoritative source)
    print("\nSeeding ops_task from hr_ee_tasks tab...")
    task_map = seed_tasks_from_sheet(supabase, gc)

    # Step 2: Migrate daily schedule
    migrate_schedule(supabase, gc, task_map)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
