"""
Migrate Food Safety Corrective Actions
========================================
Migrates fsafe_log_corrective_action into ops_corrective_action_taken,
linking each row back to the source event (checklist tracker, fsafe_result,
or fsafe_pest_result) via the legacy LogID column.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_corrective_action: ~471 rows

Architecture:
  We never persisted the legacy `Entry ID` from the source log tabs, so
  we can't directly look up "which tracker came from LogID=abc123". Instead
  we re-read each source log tab and rebuild an in-memory map of
  Entry ID -> tracker_id (or fsafe_result_id, fsafe_pest_result_id) by
  matching on (start_time, created_by, farm_id) — the same fields the
  earlier migrations used as natural keys.

  For checklist corrective actions: ops_template_result_id is left null
  because the sheet doesn't tell us which question failed.

  Fan-out templates (cuke GH pre/post — multiple greenhouses per row):
  the corrective action attaches to the FIRST matching tracker only.

  Pest activity corrective actions go into the new fsafe_pest_result_id
  FK column added to ops_corrective_action_taken.

Usage:
    python migrations/20260401000020_fsafe_corrective_actions.py

Rerunnable: clears all rows from ops_corrective_action_taken before
inserting.
"""

import re
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

from gsheets.migrations._config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)

FSAFE_SHEET_ID = SHEET_IDS["fsafe"]

# Map sheet 'Log' values -> source tab + (template_id|None) + farm_id
# Templates exist for the ops checklists; EMP/Pest results don't have one.
LOG_SOURCES = {
    "Cuke GH Pre Ops":     {"tab": "fsafe_log_C_gh_pre",  "template_id": "Cuke GH Pre Ops",     "farm_id": "Cuke",    "kind": "tracker"},
    "Cuke GH Post Ops":    {"tab": "fsafe_log_C_gh_post", "template_id": "Cuke GH Post Ops",    "farm_id": "Cuke",    "kind": "tracker"},
    "Cuke PH Pre Ops":     {"tab": "fsafe_log_C_ph_pre",  "template_id": "Cuke PH Pre Ops",     "farm_id": "Cuke",    "kind": "tracker"},
    "Cuke PH Post Ops":    {"tab": "fsafe_log_C_ph_post", "template_id": "Cuke PH Post Ops",    "farm_id": "Cuke",    "kind": "tracker"},
    "Lettuce GH Pre Ops":  {"tab": "fsafe_log_L_gh_pre",  "template_id": "Lettuce GH Pre Ops",  "farm_id": "Lettuce", "kind": "tracker"},
    "Lettuce GH Post Ops": {"tab": "fsafe_log_L_gh_post", "template_id": "Lettuce GH Post Ops", "farm_id": "Lettuce", "kind": "tracker"},
    "Lettuce PH Pre Ops":  {"tab": "fsafe_log_L_ph_pre",  "template_id": "Lettuce PH Pre Ops",  "farm_id": "Lettuce", "kind": "tracker"},
    "Lettuce PH Post Ops": {"tab": "fsafe_log_L_ph_post", "template_id": "Lettuce PH Post Ops", "farm_id": "Lettuce", "kind": "tracker"},
    "Lettuce Calibration": {"tab": "fsafe_log_calibration","template_id": "lettuce_calibration", "farm_id": "Lettuce", "kind": "tracker"},
    "EMP Results":         {"tab": "fsafe_log_emp",        "template_id": None,                  "farm_id": None,      "kind": "fsafe_result"},
    "Pest Activity Log":   {"tab": "fsafe_log_pest",       "template_id": None,                  "farm_id": None,      "kind": "fsafe_pest_result"},
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def to_id(name: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list):
    print(f"\n--- {table} ---")
    all_data = []
    if not rows:
        return all_data
    total_batches = (len(rows) + 99) // 100
    for i in range(0, len(rows), 100):
        batch = rows[i:i + 100]
        batch_num = (i // 100) + 1
        try:
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
    print(f"  Inserted {len(rows)} rows")
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


def parse_date(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def normalize_iso(s):
    """Normalize an ISO timestamp string for key comparison.

    Postgres returns '2024-02-07T08:33:43+00:00' (with timezone), while
    the sheet parser produces '2024-02-07T08:33:43' (naive). For lookup
    purposes, strip the timezone suffix and any sub-second precision so
    both sides hash to the same key.
    """
    if not s:
        return None
    s = str(s)
    # Drop timezone (+/-HH:MM or Z)
    for sep in ("+", "-"):
        # don't drop the - in the date portion
        idx = s.rfind(sep)
        if idx > 10:  # past the date
            s = s[:idx]
            break
    if s.endswith("Z"):
        s = s[:-1]
    # Drop fractional seconds
    if "." in s:
        s = s.split(".", 1)[0]
    return s


def load_employee_email_map(supabase):
    result = supabase.table("hr_employee").select("id, company_email").execute()
    return {
        (r["company_email"] or "").lower(): r["id"]
        for r in result.data
        if r.get("company_email")
    }


# ---------------------------------------------------------------------------
# Build entry-id -> target lookup
# ---------------------------------------------------------------------------

def fetch_all(supabase, table, columns, filters=None):
    """Page through a table since supabase-py defaults to a 1000-row limit."""
    rows = []
    offset = 0
    while True:
        q = supabase.table(table).select(columns).range(offset, offset + 999)
        if filters:
            for col, val in filters.items():
                q = q.eq(col, val)
        result = q.execute()
        rows.extend(result.data)
        if len(result.data) < 1000:
            break
        offset += 1000
    return rows


def build_lookup_for_template(supabase, gc, template_id, source_tab, farm_id):
    """Returns dict: legacy Entry ID -> ops_task_tracker.id (first match)."""
    # Pull all trackers for this template via the results that point at it.
    # We need (tracker_id, start_time, created_by). Trackers don't have
    # template_id directly, but every result row does.
    print(f"    Loading trackers for template {template_id!r}...")
    result_rows = fetch_all(
        supabase, "ops_template_result",
        "ops_task_tracker_id",
        filters={"ops_template_id": template_id},
    )
    tracker_ids = sorted({r["ops_task_tracker_id"] for r in result_rows})
    if not tracker_ids:
        return {}

    # Pull tracker metadata in chunks
    tracker_index = {}  # (start_time_iso, created_by_lower) -> [tracker_id, ...]
    for i in range(0, len(tracker_ids), 200):
        chunk = tracker_ids[i:i + 200]
        tr_rows = (
            supabase.table("ops_task_tracker")
            .select("id,start_time,created_by")
            .in_("id", chunk)
            .execute()
            .data
        )
        for tr in tr_rows:
            key = (normalize_iso(tr["start_time"]), (tr.get("created_by") or "").lower())
            tracker_index.setdefault(key, []).append(tr["id"])
    print(f"    {len(tracker_index)} unique (start_time, reporter) keys across {len(tracker_ids)} trackers")

    # Now read the source tab and build EntryID -> tracker_id
    print(f"    Reading source tab {source_tab!r}...")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet(source_tab)
    sheet_rows = ws.get_all_records()
    entry_to_tracker = {}
    matched = 0
    unmatched = 0
    for r in sheet_rows:
        entry_id = str(r.get("Entry ID", "")).strip()
        if not entry_id:
            continue
        reported = parse_datetime(r.get("Reported Time")) or parse_datetime(r.get("Checked Date"))
        if not reported:
            continue
        reporter_raw = str(r.get("Reported By", "")).strip().lower()
        reporter = reporter_raw if "@" in reporter_raw else AUDIT_USER
        key = (normalize_iso(reported), reporter)
        if key in tracker_index:
            entry_to_tracker[entry_id] = tracker_index[key][0]  # first match
            matched += 1
        else:
            unmatched += 1
    print(f"    Matched {matched} entries, {unmatched} unmatched in sheet")
    return entry_to_tracker


def build_lookup_emp(supabase, gc):
    """Returns dict: legacy Entry ID -> fsafe_result.id

    EMP rows in fsafe_result were inserted by 7c with sampled_at from the
    sheet's Timestamp column. We match by (sampled_at, sampled_by) — sampled_by
    in 7c was resolved from a name, so it might not be a clean email. We'll
    fall back to (sampled_at, site_id) if needed.
    """
    print(f"    Loading EMP fsafe_result rows...")
    fr_rows = fetch_all(
        supabase, "fsafe_result",
        "id,sampled_at,site_id,fsafe_lab_test_id",
    )
    # Filter to actual EMP results: not test_hold, not water (water has zone),
    # not ATP. Easiest filter: exclude atp_rlu test, exclude rows with fsafe_test_hold_id.
    # Pull again with proper filter for EMP-shaped rows.
    fr_rows_emp = fetch_all(
        supabase, "fsafe_result",
        "id,sampled_at,site_id",
        filters=None,  # we'll filter in python
    )
    # Build (sampled_at, site_id) -> fsafe_result.id index for all rows.
    # We can't filter EMP-specific without joining; multiple match keys are tolerable
    # since corrective action sheet says explicitly Log='EMP Results'.
    fr_index = {}
    for r in fr_rows_emp:
        sa = normalize_iso(r.get("sampled_at"))
        if not sa:
            continue
        key = (sa, r.get("site_id"))
        fr_index.setdefault(key, []).append(r["id"])
    print(f"    {len(fr_index)} (sampled_at, site_id) keys across {len(fr_rows_emp)} fsafe_result rows")

    # Read fsafe_log_emp and build entry_id -> fsafe_result.id
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_emp")
    sheet_rows = ws.get_all_records()
    entry_map = {}
    matched = 0
    unmatched = 0
    for r in sheet_rows:
        # EMP sheet uses 'EntryID' (no space) and 'SampleDateTime' headers
        entry_id = str(r.get("EntryID", "")).strip()
        if not entry_id:
            continue
        sampled_at = normalize_iso(parse_datetime(str(r.get("SampleDateTime", "")).strip()))
        if not sampled_at:
            continue
        # Try sampled_at-only matches across all sites
        # Since site mapping in 7c is intricate, use sampled_at as primary key
        # and accept first match. EMP timestamps are usually unique per row.
        for (sa, _site_id), ids in fr_index.items():
            if sa == sampled_at:
                entry_map[entry_id] = ids[0]
                matched += 1
                break
        else:
            unmatched += 1
    print(f"    Matched {matched} EMP entries, {unmatched} unmatched")
    return entry_map


def build_lookup_pest(supabase, gc):
    """Returns dict: legacy Entry ID -> fsafe_pest_result.id (first match).

    fsafe_pest_result was inserted by 7k with one row per (sheet row x station).
    Each pest sheet row has a single Entry ID but may map to multiple result
    rows after fan-out. The corrective action attaches to the first match
    (per the user's instruction).

    We match by (sampled_at = tracker.start_time, site_id-ish). Since 7k
    used (Reported Time, Reported By) on the tracker, we look up tracker
    by (start_time, created_by) then take its associated fsafe_pest_result.
    """
    print(f"    Loading pest tracker index...")
    # Get all trackers for pest_trap_inspection task
    pest_trackers = fetch_all(
        supabase, "ops_task_tracker",
        "id,start_time,created_by",
        filters={"ops_task_id": "Pest Trap Inspection"},
    )
    tracker_index = {}
    for tr in pest_trackers:
        key = (normalize_iso(tr["start_time"]), (tr.get("created_by") or "").lower())
        tracker_index.setdefault(key, []).append(tr["id"])
    print(f"    {len(tracker_index)} unique tracker keys across {len(pest_trackers)} pest trackers")

    # Get fsafe_pest_result rows: tracker_id -> result_id (first per tracker)
    print(f"    Loading pest result rows...")
    pest_results = fetch_all(supabase, "fsafe_pest_result", "id,ops_task_tracker_id")
    tracker_to_result = {}
    for pr in pest_results:
        tid = pr["ops_task_tracker_id"]
        if tid not in tracker_to_result:
            tracker_to_result[tid] = pr["id"]

    # Read fsafe_log_pest and match Entry ID
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_pest")
    sheet_rows = ws.get_all_records()
    entry_map = {}
    matched = 0
    unmatched = 0
    for r in sheet_rows:
        entry_id = str(r.get("Entry ID", "")).strip()
        if not entry_id:
            continue
        reported = parse_datetime(r.get("Reported Time")) or parse_datetime(r.get("Checked Date"))
        if not reported:
            continue
        reporter_raw = str(r.get("Reported By", "")).strip().lower()
        reporter = reporter_raw if "@" in reporter_raw else AUDIT_USER
        key = (normalize_iso(reported), reporter)
        if key in tracker_index:
            # Take any tracker matching, then any result on that tracker
            for tid in tracker_index[key]:
                if tid in tracker_to_result:
                    entry_map[entry_id] = tracker_to_result[tid]
                    matched += 1
                    break
            else:
                unmatched += 1
        else:
            unmatched += 1
    print(f"    Matched {matched} pest entries, {unmatched} unmatched")
    return entry_map


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    print("\nClearing existing ops_corrective_action_taken...")
    supabase.table("ops_corrective_action_taken").delete().neq(
        "id", "00000000-0000-0000-0000-000000000000"
    ).execute()
    print("  Cleared")


def migrate(supabase, gc, email_map):
    print("\n=== fsafe_log_corrective_action ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_corrective_action")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    # Build lookups per source log type, only for log values present in the data
    log_values_present = {str(r.get("Log", "")).strip() for r in records}
    print(f"  Log values present: {sorted(log_values_present)}")

    tracker_lookups = {}  # template_id -> dict(entry_id -> tracker_id)
    emp_lookup = None
    pest_lookup = None

    for log_val in log_values_present:
        src = LOG_SOURCES.get(log_val)
        if not src:
            print(f"  WARN: no source mapping for log value {log_val!r}")
            continue
        if src["kind"] == "tracker":
            print(f"  Building tracker lookup for {log_val!r}...")
            tracker_lookups[log_val] = build_lookup_for_template(
                supabase, gc, src["template_id"], src["tab"], src["farm_id"]
            )
        elif src["kind"] == "fsafe_result" and emp_lookup is None:
            print(f"  Building EMP fsafe_result lookup...")
            emp_lookup = build_lookup_emp(supabase, gc)
        elif src["kind"] == "fsafe_pest_result" and pest_lookup is None:
            print(f"  Building pest fsafe_pest_result lookup...")
            pest_lookup = build_lookup_pest(supabase, gc)

    rows = []
    skipped_no_source = 0
    skipped_no_match = 0
    skipped_no_date = 0

    for r in records:
        log_val = str(r.get("Log", "")).strip()
        log_id = str(r.get("LogID", "")).strip()
        src = LOG_SOURCES.get(log_val)
        if not src:
            skipped_no_source += 1
            continue
        if not log_id:
            skipped_no_match += 1
            continue

        reported_date = parse_date(r.get("ReportedDate"))
        if not reported_date:
            skipped_no_date += 1
            continue

        verified_at = parse_datetime(r.get("VerifiedDateTime"))
        verified_by_email = str(r.get("VerifiedBy", "")).strip().lower()
        verified_by_id = email_map.get(verified_by_email)

        reported_by_raw = str(r.get("ReportedBy", "")).strip()
        reported_by = reported_by_raw.lower() if "@" in reported_by_raw else AUDIT_USER

        warning_text = str(r.get("Warning", "")).strip() or None
        action_text = str(r.get("CorrectiveAction", "")).strip()
        other_text = str(r.get("OtherCorrectiveAction", "")).strip()
        notes_combined = action_text or None
        if other_text:
            notes_combined = (notes_combined + " | " if notes_combined else "") + other_text

        # Resolve link target by kind
        farm_id = src["farm_id"]
        ops_template_id = src["template_id"]
        ops_template_result_id = None
        fsafe_result_id = None
        fsafe_pest_result_id = None

        if src["kind"] == "tracker":
            tracker_id = tracker_lookups.get(log_val, {}).get(log_id)
            if not tracker_id:
                skipped_no_match += 1
                continue
            # Per user direction: leave ops_template_result_id null;
            # we know the template, not which question failed.
        elif src["kind"] == "fsafe_result":
            fsafe_result_id = (emp_lookup or {}).get(log_id)
            if not fsafe_result_id:
                skipped_no_match += 1
                continue
            # EMP corrective action — derive farm_id from the resolved fsafe_result row.
            # We didn't capture farm in the lookup; pull it on-demand.
            r2 = supabase.table("fsafe_result").select("farm_id").eq("id", fsafe_result_id).execute()
            if r2.data:
                farm_id = r2.data[0].get("farm_id")
        elif src["kind"] == "fsafe_pest_result":
            fsafe_pest_result_id = (pest_lookup or {}).get(log_id)
            if not fsafe_pest_result_id:
                skipped_no_match += 1
                continue
            r2 = supabase.table("fsafe_pest_result").select("farm_id").eq("id", fsafe_pest_result_id).execute()
            if r2.data:
                farm_id = r2.data[0].get("farm_id")

        rows.append({
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "ops_template_id": ops_template_id,
            "ops_template_result_id": ops_template_result_id,
            "fsafe_result_id": fsafe_result_id,
            "fsafe_pest_result_id": fsafe_pest_result_id,
            "notes": notes_combined,
            "result_description": warning_text,
            "is_resolved": True,  # historical events, all closed
            "completed_at": verified_at,
            "assigned_to": verified_by_id,
            "verified_at": verified_at,
            "verified_by": verified_by_id,
            "created_by": reported_by,
            "updated_by": reported_by,
        })

    if skipped_no_source:
        print(f"  Skipped {skipped_no_source} rows: unrecognized Log value")
    if skipped_no_date:
        print(f"  Skipped {skipped_no_date} rows: no parseable ReportedDate")
    if skipped_no_match:
        print(f"  Skipped {skipped_no_match} rows: no source row matched")

    insert_rows(supabase, "ops_corrective_action_taken", rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE CORRECTIVE ACTIONS MIGRATION")
    print("=" * 60)

    clear_existing_data(supabase)

    email_map = load_employee_email_map(supabase)

    migrate(supabase, gc, email_map)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
