"""
Migrate Food Safety Pest Trap Log
==================================
Migrates fsafe_log_pest into fsafe_pest_result with one ops_task_tracker
per (sheet row x station) — fanning out multi-station rows.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_pest: ~2248 rows -> ~10000 trackers + fsafe_pest_result rows

Architecture:
  - Uses the existing 'pest_trap_inspection' ops_task (not food_safety_log)
  - Each sheet row covers either one station or many (concatenated with '+').
    Multi-station rows are fanned out — one tracker per station.
  - tracker.site_id = the parent building (looked up from each trap's
    site_id_parent in org_site)
  - fsafe_pest_result.site_id = the specific trap
  - pest_type = 'mouse' when Activity=TRUE and Pest Type='Mouse', else null

Site name mapping (sheet -> org_site id prefix):
  Cuke + GH cluster letters (HI/HK/KO/WA) -> cuke_<lower>_trap_<n>
  Cuke + 'PH'                              -> cuke_ph_trap_<n>
  Cuke + 'Nursery'                         -> cuke_nursery_trap_<n>
  Lettuce + 'GH'                           -> lettuce_gh_trap_<n>
  Lettuce + 'PH'                           -> lettuce_ph_trap_<n>

Rerunnable: clears fsafe_pest_result and the orphaned trackers it
points at, then reinserts.

Usage:
    python migrations/20260401000018_fsafe_pest_log.py
"""

import re
import sys
import uuid
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

from _config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)
from _pg import get_pg_conn, paginate_select, pg_bulk_insert

FSAFE_SHEET_ID = SHEET_IDS["fsafe"]
TASK_ID = "pest_trap_inspection"


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def to_id(name: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, upsert=False):
    print(f"\n--- {table} ---")
    all_data = []
    if not rows:
        return all_data
    total_batches = (len(rows) + 99) // 100
    for i in range(0, len(rows), 100):
        batch = rows[i:i + 100]
        batch_num = (i // 100) + 1
        try:
            if upsert:
                result = supabase.table(table).upsert(batch).execute()
            else:
                result = supabase.table(table).insert(batch).execute()
            all_data.extend(result.data)
        except Exception as e:
            print(
                f"  ERROR on batch {batch_num}/{total_batches} "
                f"(rows {i + 1}-{i + len(batch)}): {type(e).__name__}: {e}"
            )
            print(f"  {len(all_data)} rows committed before failure")
            print(f"  Re-run the script to retry — it is idempotent.")
            raise
    action = "Upserted" if upsert else "Inserted"
    print(f"  {action} {len(rows)} rows")
    return all_data


def get_sheets():
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def parse_datetime(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    formats = (
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%m/%d/%y %H:%M:%S",
        "%m/%d/%y %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%m/%d/%Y",
        "%m/%d/%y",
        "%Y-%m-%d",
    )
    for fmt in formats:
        try:
            dt = datetime.strptime(s, fmt)
            if fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
                dt = dt.replace(hour=12)
            return dt.isoformat()
        except ValueError:
            continue
    return None


def parse_bool_cell(val):
    if val is None:
        return False
    s = str(val).strip().upper()
    return s in ("TRUE", "YES", "1")


# ---------------------------------------------------------------------------
# Stub-employee creation
# ---------------------------------------------------------------------------

def load_employee_email_map(supabase):
    employees = paginate_select(supabase, "hr_employee", "id, company_email")
    return {
        (r["company_email"] or "").lower(): r["id"]
        for r in employees
        if r.get("company_email")
    }


def create_stub_employee(supabase, email):
    local = email.split("@")[0]
    parts = re.split(r"[._-]+", local)
    first = (parts[0] if parts else local).title() or "External"
    last = (parts[1] if len(parts) > 1 else "Verifier").title() or "Verifier"
    emp_id = to_id(f"{last} {first}") or to_id(email.replace("@", "_at_"))
    row = audit({
        "id": emp_id,
        "org_id": ORG_ID,
        "first_name": first,
        "last_name": last,
        "company_email": email,
        "is_primary_org": True,
        "sys_access_level_id": "employee",
        "is_deleted": True,
    })
    try:
        supabase.table("hr_employee").upsert(row).execute()
    except Exception as e:
        print(f"  WARN stub employee upsert failed for {email}: {type(e).__name__}: {e}")
        return None
    return emp_id


def resolve_verifier(supabase, email, email_map, stub_cache):
    if not email or "@" not in email:
        return None
    email = email.lower()
    if email in email_map:
        return email_map[email]
    if email in stub_cache:
        return stub_cache[email]
    new_id = create_stub_employee(supabase, email)
    if new_id:
        stub_cache[email] = new_id
        email_map[email] = new_id
    return new_id


# ---------------------------------------------------------------------------
# Pest trap site lookup
# ---------------------------------------------------------------------------

def load_trap_index(supabase):
    """Build a lookup: trap_id -> (site_id_parent, farm_id).

    Returns dict keyed by org_site.id for all pest_trap rows.
    """
    sites = paginate_select(
        supabase, "org_site", "id,site_id_parent,farm_id",
        eq_filters={"org_site_category_id": "pest_trap"},
    )
    return {r["id"]: r for r in sites}


def build_trap_id(farm: str, site_name: str, station: str) -> str | None:
    """Map (Farm, Site Name, Station) -> existing org_site.id pattern.

    Returns None if station can't be parsed as integer.
    """
    if not farm or not site_name:
        return None
    try:
        n = int(str(station).strip())
    except (ValueError, TypeError):
        return None

    farm_lower = farm.strip().lower()  # 'cuke' or 'lettuce'
    site_lower = site_name.strip().lower()  # 'gh', 'ph', 'hi', 'hk', 'ko', 'wa', 'nursery', '1'

    return f"{farm_lower}_{site_lower}_trap_{n}"


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    """Delete fsafe_pest_result rows + the trackers they point at."""
    print("\nClearing existing fsafe_pest_result + trackers...")

    # Capture tracker IDs before deleting results. Page through since there
    # could be ~10k rows. supabase-py defaults to 1000 row limit.
    tracker_ids = set()
    offset = 0
    while True:
        result = (
            supabase.table("fsafe_pest_result")
            .select("ops_task_tracker_id")
            .range(offset, offset + 999)
            .execute()
        )
        if not result.data:
            break
        for r in result.data:
            tracker_ids.add(r["ops_task_tracker_id"])
        if len(result.data) < 1000:
            break
        offset += 1000

    # Delete fsafe_pest_result rows. PostgREST requires a filter on delete.
    supabase.table("fsafe_pest_result").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    print(f"  Cleared fsafe_pest_result")

    if tracker_ids:
        ids = list(tracker_ids)
        for i in range(0, len(ids), 100):
            chunk = ids[i:i + 100]
            supabase.table("ops_task_tracker").delete().in_("id", chunk).execute()
        print(f"  Cleared {len(ids)} orphaned pest trackers")
    else:
        print("  No orphaned trackers to delete")


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

def migrate(supabase, gc, email_map, stub_cache):
    print("\n=== fsafe_log_pest -> fsafe_pest_result ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_pest")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    trap_index = load_trap_index(supabase)
    print(f"  {len(trap_index)} pest_trap sites loaded for resolution")

    trackers = []
    pending_results = []  # dicts of fsafe_pest_result fields (tracker_id pre-assigned)
    skipped_no_date = 0
    skipped_no_site = 0
    skipped_unknown_traps = []  # list of (trap_id_attempted)
    fanned_out = 0
    pest_active_total = 0

    for r in records:
        farm_raw = str(r.get("Farm", "")).strip()
        site_raw = str(r.get("Site Name", "")).strip()
        stations_raw = str(r.get("Station(s)", "")).strip()

        if not farm_raw or not site_raw or not stations_raw:
            skipped_no_site += 1
            continue

        reported = parse_datetime(r.get("Reported Time")) or parse_datetime(r.get("Checked Date"))
        if not reported:
            skipped_no_date += 1
            continue

        verified_at = parse_datetime(r.get("Verified Time"))
        verified_by_id = resolve_verifier(supabase, str(r.get("Verified By", "")).strip(), email_map, stub_cache)
        reported_by_raw = str(r.get("Reported By", "")).strip()
        reported_by = reported_by_raw.lower() if "@" in reported_by_raw else AUDIT_USER

        activity = parse_bool_cell(r.get("Activity"))
        action_required = parse_bool_cell(r.get("Action Required"))
        pest_type_raw = str(r.get("Pest Type", "")).strip().lower()
        warning_raw = str(r.get("Warning", "")).strip()
        photo_raw = str(r.get("Photo", "")).strip()

        # Resolve to canonical pest_type enum
        if activity and pest_type_raw == "mouse":
            pest_type = "mouse"
        elif activity and pest_type_raw == "rat":
            pest_type = "rat"
        else:
            pest_type = None

        # Fan out the Station(s) cell
        station_codes = [s.strip() for s in stations_raw.split("+") if s.strip()]
        if len(station_codes) > 1:
            fanned_out += 1

        farm_id = farm_raw.lower()  # 'cuke' / 'lettuce'

        for station in station_codes:
            trap_id = build_trap_id(farm_raw, site_raw, station)
            if not trap_id or trap_id not in trap_index:
                skipped_unknown_traps.append(trap_id or f"({farm_raw}/{site_raw}/{station})")
                continue
            trap = trap_index[trap_id]
            parent_site = trap.get("site_id_parent")
            if not parent_site:
                # Trap has no parent — fall back to the farm parent (gh/bip)
                parent_site = "gh" if farm_id == "lettuce" else "bip"

            # Pre-generate tracker UUID so we can assign it to the
            # pest_result row without a DB roundtrip.
            tracker_id = str(uuid.uuid4())
            trackers.append({
                "id": tracker_id,
                "org_id": ORG_ID,
                "farm_id": farm_id,
                "site_id": parent_site,
                "ops_task_id": TASK_ID,
                "start_time": reported,
                "stop_time": reported,
                "is_completed": True,
                "verified_at": verified_at,
                "verified_by": verified_by_id,
                "notes": warning_raw or None,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

            if pest_type is not None:
                pest_active_total += 1

            pending_results.append({
                "org_id": ORG_ID,
                "farm_id": farm_id,
                "site_id": trap_id,
                "ops_task_tracker_id": tracker_id,
                "pest_type": pest_type,
                "photo_url": photo_raw or None,
                "notes": warning_raw or None,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

    print(f"  {fanned_out} multi-station rows fanned out")
    print(f"  {len(trackers)} trackers to insert")
    print(f"  {pest_active_total} results with pest activity")
    if skipped_no_date:
        print(f"  Skipped {skipped_no_date} rows: no parseable date")
    if skipped_no_site:
        print(f"  Skipped {skipped_no_site} rows: missing farm/site/station")
    if skipped_unknown_traps:
        from collections import Counter
        c = Counter(skipped_unknown_traps)
        print(f"  Skipped {len(skipped_unknown_traps)} entries: unknown trap")
        print(f"  Top unresolved: {dict(c.most_common(8))}")

    if not trackers:
        return

    # Bulk insert via psycopg2 — single transaction, orders of magnitude
    # faster than ~100 PostgREST roundtrips for 10k+ rows.
    print(f"\n--- ops_task_tracker ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "ops_task_tracker", trackers)
        print(f"  Inserted {len(trackers)} rows")
        print(f"\n--- fsafe_pest_result ---")
        pg_bulk_insert(conn, "fsafe_pest_result", pending_results)
        print(f"  Inserted {len(pending_results)} rows")
        conn.commit()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE PEST TRAP LOG MIGRATION")
    print("=" * 60)

    clear_existing_data(supabase)

    email_map = load_employee_email_map(supabase)
    stub_cache = {}

    migrate(supabase, gc, email_map, stub_cache)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
