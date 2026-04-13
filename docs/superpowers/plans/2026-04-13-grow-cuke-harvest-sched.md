# Grow Cuke Harvest Schedule Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate ~8,644 harvest crew session rows from the legacy `grow_C_harvest_sched` Google Sheet tab into `ops_task_tracker`, then link them to the already-migrated `grow_harvest_weight` rows.

**Architecture:** Each sheet row becomes one `ops_task_tracker` row (ops_task_id='harvesting', farm_id='cuke'). After all trackers are inserted, update `grow_harvest_weight.ops_task_tracker_id` by matching on (harvest_date, site_id). Earliest tracker per (date, site) wins via an `IS NULL` guard.

**Tech Stack:** Python 3, gspread, supabase-py, PostgreSQL (Supabase)

**Spec:** `docs/superpowers/specs/2026-04-13-grow-cuke-harvest-sched-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `migrations/20260401000027_grow_cuke_harvest_sched.py` | Create | Full migration script |

Single file. Follows the pattern of `migrations/20260401000026_grow_cuke_harvest.py`.

---

### Task 1: Create the migration file with docstring, imports, and constants

**Files:**
- Create: `migrations/20260401000027_grow_cuke_harvest_sched.py`

- [ ] **Step 1: Write the file**

```python
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
  SET ops_task_tracker_id = :id WHERE farm_id = 'cuke' AND
  harvest_date = :date AND site_id = :site AND ops_task_tracker_id IS NULL.
  The IS NULL guard means only the first tracker per (date, site) wins.

Usage:
    python migrations/20260401000027_grow_cuke_harvest_sched.py

Rerunnable: unlinks weigh-ins from our trackers, deletes our trackers
(identified by notes marker), then re-inserts.
"""

import sys
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

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
FARM_ID = "cuke"
OPS_TASK_ID = "harvesting"
TRACKER_NOTE_MARKER = "Legacy harvest schedule migration"
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000027_grow_cuke_harvest_sched.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 2: Add standard helper functions

**Files:**
- Modify: `migrations/20260401000027_grow_cuke_harvest_sched.py`

- [ ] **Step 1: Append helper functions**

Append to the file:

```python
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
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000027_grow_cuke_harvest_sched.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 3: Add clear/rerun function

**Files:**
- Modify: `migrations/20260401000027_grow_cuke_harvest_sched.py`

- [ ] **Step 1: Append clear function**

Append to the file:

```python
# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    """Unlink weigh-ins from our trackers and delete our trackers.

    Identifies our trackers by the notes marker so we don't touch any
    app-created harvesting trackers. Deletes in batches to stay under
    PostgREST URL length limits when the .in_() filter is used.
    """
    print("\nClearing existing harvest schedule trackers...")
    our_trackers = (
        supabase.table("ops_task_tracker")
        .select("id")
        .eq("farm_id", FARM_ID)
        .eq("ops_task_id", OPS_TASK_ID)
        .eq("notes", TRACKER_NOTE_MARKER)
        .execute()
        .data
    )
    tracker_ids = [t["id"] for t in our_trackers]
    print(f"  Found {len(tracker_ids)} existing trackers to clear")
    if not tracker_ids:
        return

    # Unlink grow_harvest_weight rows first (FK safety) in batches of 100
    for i in range(0, len(tracker_ids), 100):
        batch = tracker_ids[i:i + 100]
        supabase.table("grow_harvest_weight").update(
            {"ops_task_tracker_id": None}
        ).in_("ops_task_tracker_id", batch).execute()
    print(f"  Unlinked grow_harvest_weight rows")

    # Delete trackers in batches of 100
    for i in range(0, len(tracker_ids), 100):
        batch = tracker_ids[i:i + 100]
        supabase.table("ops_task_tracker").delete().in_("id", batch).execute()
    print(f"  Deleted {len(tracker_ids)} trackers")
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000027_grow_cuke_harvest_sched.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 4: Add row transform function

**Files:**
- Modify: `migrations/20260401000027_grow_cuke_harvest_sched.py`

- [ ] **Step 1: Append transform function**

Append to the file:

```python
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

    clock_out = parse_time(sheet_row.get("ClockOutTime"))
    if clock_out is None:
        return {"_skip": "no_clock_out"}

    start_time = combine_datetime(harvest_date, clock_in)
    stop_time = combine_datetime(harvest_date, clock_out)
    if stop_time < start_time:
        return {"_skip": "stop_before_start"}

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
        "stop_time": stop_time.isoformat(),
        "is_completed": True,
        "number_of_people": number_of_people,
        "notes": TRACKER_NOTE_MARKER,
        "created_by": reported_by,
        "updated_by": reported_by,
    }
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000027_grow_cuke_harvest_sched.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 5: Add linking function

**Files:**
- Modify: `migrations/20260401000027_grow_cuke_harvest_sched.py`

- [ ] **Step 1: Append linking function**

Append to the file:

```python
# ---------------------------------------------------------------------------
# Link harvest weights to trackers
# ---------------------------------------------------------------------------

def link_weights_to_trackers(supabase, trackers):
    """For each tracker (sorted earliest first), set ops_task_tracker_id on
    grow_harvest_weight rows matching (harvest_date, site_id).

    The IS NULL guard via filter ensures only the first tracker per
    (date, site) pair claims the weigh-ins.

    `trackers` is a list of dicts as returned from the insert: each must
    have id, start_time, site_id.
    """
    print("\nLinking grow_harvest_weight to trackers (earliest-first)...")

    # Sort by start_time so earliest claims first
    sorted_trackers = sorted(trackers, key=lambda t: t["start_time"])

    total_linked = 0
    for tracker in sorted_trackers:
        tracker_id = tracker["id"]
        harvest_date = tracker["start_time"][:10]  # YYYY-MM-DD prefix of ISO timestamp
        site_id = tracker["site_id"]

        result = (
            supabase.table("grow_harvest_weight")
            .update({"ops_task_tracker_id": tracker_id})
            .eq("farm_id", FARM_ID)
            .eq("harvest_date", harvest_date)
            .eq("site_id", site_id)
            .is_("ops_task_tracker_id", "null")
            .execute()
        )
        total_linked += len(result.data)

    print(f"  Linked {total_linked} grow_harvest_weight rows to trackers")
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000027_grow_cuke_harvest_sched.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 6: Add main function and run

**Files:**
- Modify: `migrations/20260401000027_grow_cuke_harvest_sched.py`

- [ ] **Step 1: Append main function**

Append to the file:

```python
# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW CUKE HARVEST SCHEDULE MIGRATION")
    print("=" * 60)

    clear_existing(supabase)

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

    for r in records:
        result = build_tracker_row(r, known_sites)
        if "_skip" in result:
            reason = result["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            continue
        rows.append(result)

    print(f"\n  Built {len(rows)} tracker rows")
    for reason, count in sorted(skip_counts.items()):
        print(f"  Skipped {count} rows: {reason}")

    inserted = insert_rows(supabase, "ops_task_tracker", rows)

    # Link harvest weights to the newly-created trackers
    link_weights_to_trackers(supabase, inserted)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify final syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000027_grow_cuke_harvest_sched.py').read()); print('syntax OK')"`

Expected: `syntax OK`

- [ ] **Step 3: Commit the migration script**

```bash
cd c:/Users/micha/Desktop/aloha-data-migrations
git add migrations/20260401000027_grow_cuke_harvest_sched.py
git commit -m "Add grow_C_harvest_sched migration script

Creates ~8,644 ops_task_tracker rows (ops_task_id='harvesting',
farm_id='cuke') from legacy Google Sheet. Links them to already-
migrated grow_harvest_weight rows by matching (harvest_date, site_id),
earliest-session-wins per (date, greenhouse)."
```

---

### Task 7: Run migration and verify

- [ ] **Step 1: Run the migration**

```bash
cd c:/Users/micha/Desktop/aloha-data-migrations
python migrations/20260401000027_grow_cuke_harvest_sched.py
```

Expected output:
```
============================================================
GROW CUKE HARVEST SCHEDULE MIGRATION
============================================================

Clearing existing harvest schedule trackers...
  Found 0 existing trackers to clear

Reading grow_C_harvest_sched...
  ~8644 sheet rows

  Built NNNN tracker rows
  Skipped N rows: ...

--- ops_task_tracker ---
  Inserted NNNN rows

Linking grow_harvest_weight to trackers (earliest-first)...
  Linked NNNN grow_harvest_weight rows to trackers

============================================================
DONE
============================================================
```

- [ ] **Step 2: Verify row counts**

```bash
python -c "
import sys; sys.path.insert(0, 'migrations')
from _config import SUPABASE_URL, require_supabase_key
from supabase import create_client
sb = create_client(SUPABASE_URL, require_supabase_key())

# Count our trackers
trackers = sb.table('ops_task_tracker').select('id', count='exact').eq('farm_id','cuke').eq('ops_task_id','harvesting').eq('notes','Legacy harvest schedule migration').execute()
print(f'Our trackers: {trackers.count}')

# Count linked harvest_weight rows
linked = sb.table('grow_harvest_weight').select('id', count='exact').eq('farm_id','cuke').not_.is_('ops_task_tracker_id','null').execute()
unlinked = sb.table('grow_harvest_weight').select('id', count='exact').eq('farm_id','cuke').is_('ops_task_tracker_id','null').execute()
print(f'Linked harvest_weight: {linked.count}')
print(f'Unlinked harvest_weight: {unlinked.count}')
"
```

Expected:
- ~8,644 trackers
- Most harvest_weight rows from Nov 2023 onward are linked
- Weigh-ins from Jan 2020 through Nov 2023 are unlinked (no schedule data existed)

- [ ] **Step 3: Re-run to verify idempotency**

```bash
python migrations/20260401000027_grow_cuke_harvest_sched.py
```

Expected: Same row counts. No duplicate key errors. `Found ~8644 existing trackers to clear` on this run.
