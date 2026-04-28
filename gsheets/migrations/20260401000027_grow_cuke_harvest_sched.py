"""
Migrate Cuke Harvest Schedule Data
===================================
Migrates grow_C_harvest_sched into ops_task_tracker. Each sheet row is
one harvest crew session at one greenhouse on one date. After inserting
all trackers, links them to already-migrated grow_harvest_weight rows
by matching (harvest_date, site_id).

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_C_harvest_sched: ~8,644 rows (Nov 30 2023 through Apr 13 2026)

Data mapping:
  - HarvestDate + ClockInTime   -> start_time
  - HarvestDate + ClockOutTime  -> stop_time
  - Greenhouse                  -> site_id (normalized)
  - NumberOfPeople              -> number_of_people (nullable)
  - ReportedBy                  -> created_by / updated_by
  - ops_task_id                 -> "harvesting" (hardcoded)
  - notes                       -> "Legacy harvest schedule migration"
                                   (marker for rerun identification)

Columns NOT stored (derivable via view):
  Year, Month, ISOYear, ISOWeek (from start_time)
  Hours (from stop_time - start_time)
  GreenhouseNetWeight, GradeOneNetWeight (from grow_harvest_weight SUM)
  GreenhousePoundsPerHour, GradeOnePoundsPerHour (derived ratio)
  EntryID (UUID is the PK)

Linking strategy (earliest wins):
  Sort trackers by start_time ASC. For each, UPDATE grow_harvest_weight
  SET ops_task_tracker_id = :id WHERE farm_id = 'Cuke' AND
  harvest_date = :date AND site_id = :site AND ops_task_tracker_id IS NULL.
  The IS NULL guard means only the first tracker per (date, site) wins.

Usage:
    python migrations/20260401000027_grow_cuke_harvest_sched.py

Rerunnable: unlinks weigh-ins from our trackers, deletes our trackers
(identified by notes marker), then re-inserts.
"""

import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
import psycopg2
from google.oauth2.service_account import Credentials
from supabase import create_client

from gsheets.migrations._config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)


def get_pg_conn():
    """Direct psycopg2 connection for bulk operations that are too slow via PostgREST."""
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise SystemExit("ERROR: SUPABASE_DB_URL must be set in .env for bulk operations")
    return psycopg2.connect(db_url)

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
FARM_ID = "Cuke"
OPS_TASK_ID = "Harvesting"
TRACKER_NOTE_MARKER = "Legacy harvest schedule migration"

# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, upsert=False, on_conflict=""):
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
                result = supabase.table(table).upsert(batch, on_conflict=on_conflict).execute()
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


def parse_date(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parse_time(val):
    """Parse a time string like '7:00:00 AM' or '15:23:34'. Returns a time object or None."""
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in ("%I:%M:%S %p", "%I:%M %p", "%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(s, fmt).time()
        except ValueError:
            continue
    return None


def combine_datetime(d, t):
    """Combine a date and time into a timezone-naive datetime (stored as UTC)."""
    if d is None or t is None:
        return None
    return datetime.combine(d, t)


def parse_int(val, default=None):
    if val is None:
        return default
    s = str(val).strip().replace(",", "")
    if not s:
        return default
    try:
        return int(float(s))
    except ValueError:
        return default


def normalize_gh(raw):
    """'1' -> '01', 'HI' -> 'hi'."""
    s = str(raw).strip().lower()
    if not s:
        return None
    if s.isdigit() and len(s) == 1:
        s = s.zfill(2)
    return s

# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    """Unlink weigh-ins from our trackers and delete our trackers.

    Uses direct SQL via psycopg2 — bulk unlink + delete in one transaction
    is orders of magnitude faster than PostgREST batching.
    """
    print("\nClearing existing harvest schedule trackers...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE grow_harvest_weight
                SET ops_task_tracker_id = NULL
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE farm_id = %s AND ops_task_id = %s AND notes = %s
                )
                """,
                (FARM_ID, OPS_TASK_ID, TRACKER_NOTE_MARKER),
            )
            unlinked = cur.rowcount
            cur.execute(
                """
                DELETE FROM ops_task_tracker
                WHERE farm_id = %s AND ops_task_id = %s AND notes = %s
                """,
                (FARM_ID, OPS_TASK_ID, TRACKER_NOTE_MARKER),
            )
            deleted = cur.rowcount
        conn.commit()
    print(f"  Unlinked {unlinked} grow_harvest_weight rows")
    print(f"  Deleted {deleted} trackers")

# ---------------------------------------------------------------------------
# Row transform
# ---------------------------------------------------------------------------

def build_tracker_row(sheet_row, known_sites):
    """Transform one sheet row into an ops_task_tracker dict.

    Returns the row dict on success, or a dict with '_skip' key and reason on failure.
    """
    harvest_date = parse_date(sheet_row.get("HarvestDate"))
    if not harvest_date:
        return {"_skip": "no_date"}

    clock_in = parse_time(sheet_row.get("ClockInTime"))
    if clock_in is None:
        return {"_skip": "no_clock_in"}

    # ClockOutTime empty means the session is still in progress — we still
    # insert the row with stop_time=NULL and is_completed=False.
    clock_out = parse_time(sheet_row.get("ClockOutTime"))

    start_time = combine_datetime(harvest_date, clock_in)
    stop_time = combine_datetime(harvest_date, clock_out) if clock_out else None
    # Note: a handful of legacy rows have stop_time < start_time (AM/PM
    # data entry errors like 11:04 AM -> 12:44 AM). We preserve them as
    # recorded; data corrections happen in the sheet, not here.

    gh = normalize_gh(sheet_row.get("Greenhouse"))
    if not gh or gh not in known_sites:
        return {"_skip": "unknown_site", "_detail": gh}

    number_of_people = parse_int(sheet_row.get("NumberOfPeople"))

    reported_by_raw = str(sheet_row.get("ReportedBy", "")).strip().lower()
    reported_by = reported_by_raw if "@" in reported_by_raw else AUDIT_USER

    return {
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "site_id": gh,
        "ops_task_id": OPS_TASK_ID,
        "start_time": start_time.isoformat(),
        "stop_time": stop_time.isoformat() if stop_time else None,
        "is_completed": stop_time is not None,
        "number_of_people": number_of_people,
        "notes": TRACKER_NOTE_MARKER,
        "created_by": reported_by,
        "updated_by": reported_by,
    }

# ---------------------------------------------------------------------------
# Link harvest weights to trackers
# ---------------------------------------------------------------------------

def link_weights_to_trackers(trackers):
    """For each (date, site_id) pair, link the earliest tracker to matching
    grow_harvest_weight rows.

    Uses a single SQL UPDATE with a VALUES-based join — ~6,000 roundtrips
    collapse into one query.

    `trackers` is a list of dicts as returned from insert: each must have
    id, start_time, site_id.
    """
    print("\nLinking grow_harvest_weight to trackers (earliest-first)...")

    # Sort by start_time, then pick the earliest tracker per (date, site)
    sorted_trackers = sorted(trackers, key=lambda t: t["start_time"])
    earliest_per_pair = {}  # (date_str, site_id) -> tracker_id
    for t in sorted_trackers:
        key = (t["start_time"][:10], t["site_id"])
        if key not in earliest_per_pair:
            earliest_per_pair[key] = t["id"]

    print(f"  {len(earliest_per_pair)} unique (date, site) pairs out of {len(trackers)} trackers")

    if not earliest_per_pair:
        print("  Nothing to link")
        return

    # Build list of (harvest_date, site_id, tracker_id) tuples
    rows = [(d, s, tid) for (d, s), tid in earliest_per_pair.items()]

    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            # Build the VALUES list safely via mogrify, then splice into a
            # single UPDATE that joins grow_harvest_weight with the VALUES
            # table on (harvest_date, site_id).
            values_sql = ",".join(
                cur.mogrify("(%s, %s, %s)", row).decode("utf-8") for row in rows
            )
            cur.execute(
                f"""
                UPDATE grow_harvest_weight w
                SET ops_task_tracker_id = v.tracker_id::uuid
                FROM (VALUES {values_sql}) AS v(harvest_date, site_id, tracker_id)
                WHERE w.farm_id = %s
                  AND w.harvest_date = v.harvest_date::date
                  AND w.site_id = v.site_id
                  AND w.ops_task_tracker_id IS NULL
                """,
                (FARM_ID,),
            )
            total_linked = cur.rowcount
        conn.commit()

    print(f"  Linked {total_linked} grow_harvest_weight rows to trackers")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW CUKE HARVEST SCHEDULE MIGRATION")
    print("=" * 60)

    clear_existing()

    # Load known cuke greenhouse site IDs for validation
    sites = (
        supabase.table("org_site")
        .select("id")
        .eq("farm_id", FARM_ID)
        .eq("org_site_subcategory_id", "greenhouse")
        .execute()
        .data
    )
    known_sites = {s["id"] for s in sites}

    print("\nReading grow_C_harvest_sched...")
    ws = gc.open_by_key(GROW_SHEET_ID).worksheet("grow_C_harvest_sched")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    rows = []
    skip_counts = {}
    unknown_sites = set()

    for r in records:
        result = build_tracker_row(r, known_sites)
        if "_skip" in result:
            reason = result["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            if reason == "unknown_site":
                unknown_sites.add(result.get("_detail"))
            continue
        rows.append(result)

    print(f"\n  Built {len(rows)} tracker rows")
    for reason, count in sorted(skip_counts.items()):
        print(f"  Skipped {count} rows: {reason}")
    if unknown_sites:
        print(f"  Unknown greenhouses ({len(unknown_sites)}): {sorted(x for x in unknown_sites if x)}")

    inserted = insert_rows(supabase, "ops_task_tracker", rows)

    # Link harvest weights to the newly-created trackers
    link_weights_to_trackers(inserted)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
