"""
Migrate Spray Pre-Check Survey
===============================
Migrates grow_spray_pre_check into ops_task_tracker + ops_template_result
tied to the existing 'spraying' task. Pre-check events are per-tank
equipment inspections recorded before a spraying event.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_spray_pre_check: ~722 rows (all cuke farm)

Sheet columns:
  CheckedDate, Farm, SiteName (tank name, possibly concatenated with +),
  Oil, Valves, LinesAndFittings, Calibration (boolean),
  GallonsPerMinute (numeric), MaintenanceRequired (boolean),
  Notes, CheckedBy, ReportedDateTime, EntryID

Setup (upserted):
  - ops_template: Cuke Spray Pre-Check (farm_id=Cuke)
  - 6 ops_template_question rows (deterministic UUIDs via uuid5)
  - ops_task_template: link spray_pre_check template to the spraying task

Per sheet row:
  - 1 ops_task_tracker (ops_task_id=Spraying, farm_id=Cuke, site_id=NULL,
    notes carries Notes + marker, created_by from CheckedBy)
  - N * 6 ops_template_result rows where N = tanks in SiteName:
    - Split SiteName on '+' (e.g. "Tank 3+Tank 1" -> 2 tanks)
    - Resolve each to cuke_spray_tank_{n}
    - Create 6 results per tank, each scoped by equipment_id

Distinguishing pre-check trackers from real spray trackers
(both have ops_task_id='spraying'):
  - Pre-check trackers have no grow_spray_input rows, only template_results
  - Notes marker "Legacy spray pre-check migration"

Rerunnable: identifies our trackers via notes marker, deletes template
results and trackers. Template and questions are not cleared.

Usage:
    python migrations/20260401000032_grow_spray_pre_check.py
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

from gsheets.migrations._config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)
from gsheets.migrations._pg import get_pg_conn, pg_bulk_insert

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
NOTES_MARKER = "Legacy spray pre-check migration"
OPS_TASK_ID = "Spraying"
TEMPLATE_ID = "Cuke Spray Pre-Check"
FARM_ID = "Cuke"

# Deterministic UUID namespace for the pre-check questions so re-runs
# reference the same question rows rather than creating duplicates.
QUESTION_NAMESPACE = uuid.UUID("c5e8c5a2-5a5e-5a5e-5a5e-5a5e5a5e5a5e")

# (sheet_column, question_text, response_type, pass_value, display_order)
QUESTIONS = [
    ("Oil",                "Oil checked",                  "Boolean", True,  1),
    ("Valves",             "Valves checked",               "Boolean", True,  2),
    ("LinesAndFittings",   "Lines and fittings checked",   "Boolean", True,  3),
    ("Calibration",        "Calibration checked",          "Boolean", True,  4),
    ("GallonsPerMinute",   "Gallons per minute",           "Numeric", None,  5),
    ("MaintenanceRequired","Maintenance required",         "Boolean", False, 6),
]

SPRAYER_NAME_MAP = {
    "tank 1":            "Cuke Spray Tank 1",
    "tank 2":            "Cuke Spray Tank 2",
    "tank 3":            "Cuke Spray Tank 3",
    "fogger":            "Cuke Fogger",
    "fogger 1":          "Cuke Fogger 1",
    "fogger 2":          "Cuke Fogger 2",
    "backpack sprayer":  "Cuke Backpack Sprayer",
}


def question_uuid(question_text: str) -> str:
    return str(uuid.uuid5(QUESTION_NAMESPACE, question_text))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
    for fmt in (
        "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M",
        "%m/%d/%y %H:%M:%S", "%m/%d/%y %H:%M",
        "%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d",
    ):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def parse_bool(val):
    if val is None:
        return None
    s = str(val).strip().lower()
    if s in ("true", "yes", "1", "t", "y"):
        return True
    if s in ("false", "no", "0", "f", "n"):
        return False
    return None


def parse_numeric(val):
    if val is None:
        return None
    s = str(val).strip().replace(",", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def resolve_user(raw: str) -> str:
    s = str(raw).strip().lower()
    return s if "@" in s else AUDIT_USER


def split_tanks(site_name: str) -> list[str]:
    """'Tank 3+Tank 1' -> ['cuke_spray_tank_3', 'cuke_spray_tank_1'].

    Normalizes spacing so 'Tank1' and 'Tank 1' both work.
    """
    ids = []
    for part in str(site_name).split("+"):
        # Normalize: lowercase, collapse whitespace, then insert a space between
        # "tank"/"fogger" and a trailing digit if missing.
        key = re.sub(r"\s+", " ", part.strip().lower())
        key = re.sub(r"^(tank|fogger)(\d)", r"\1 \2", key)
        if key in SPRAYER_NAME_MAP:
            ids.append(SPRAYER_NAME_MAP[key])
    return ids


# ---------------------------------------------------------------------------
# Setup: template, questions, task-template link
# ---------------------------------------------------------------------------

def ensure_template(supabase):
    """Upsert ops_template, ops_template_question rows, and ops_task_template link."""
    print(f"\n--- ops_template ---")
    supabase.table("ops_template").upsert({
        "id": TEMPLATE_ID,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "description": "Per-tank equipment inspection run before a spraying event. Migrated from the legacy grow_spray_pre_check sheet.",
        "created_by": AUDIT_USER,
        "updated_by": AUDIT_USER,
    }).execute()
    print(f"  Upserted {TEMPLATE_ID}")

    print(f"\n--- ops_template_question ---")
    question_rows = []
    for (_, qtext, rtype, pass_val, order) in QUESTIONS:
        row = {
            "id": question_uuid(qtext),
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "ops_template_id": TEMPLATE_ID,
            "question_text": qtext,
            "response_type": rtype,
            "is_required": True,
            "include_photo": False,
            "display_order": order,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }
        if rtype == "Boolean":
            row["boolean_pass_value"] = pass_val
        question_rows.append(row)
    supabase.table("ops_template_question").upsert(question_rows).execute()
    print(f"  Upserted {len(question_rows)} questions")

    print(f"\n--- ops_task_template (link) ---")
    # Unique constraint on (ops_task_id, ops_template_id) — use it for upsert conflict
    supabase.table("ops_task_template").upsert(
        {
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "ops_task_id": OPS_TASK_ID,
            "ops_template_id": TEMPLATE_ID,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        },
        on_conflict="ops_task_id,ops_template_id",
    ).execute()
    print(f"  Linked '{OPS_TASK_ID}' task to '{TEMPLATE_ID}' template")


# ---------------------------------------------------------------------------
# Clear existing rows for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    """Delete previously-migrated pre-check rows (identified by notes marker)."""
    print("\nClearing existing legacy pre-check rows...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                DELETE FROM ops_template_result
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_id = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d1 = cur.rowcount
            cur.execute(
                """
                DELETE FROM ops_task_tracker
                WHERE ops_task_id = %s AND notes LIKE %s
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d2 = cur.rowcount
        conn.commit()
    print(f"  Deleted: {d1} ops_template_result, {d2} ops_task_tracker")


# ---------------------------------------------------------------------------
# Row builder
# ---------------------------------------------------------------------------

def build_rows(sheet_row):
    """Return {'tracker': dict, 'results': [dicts]} or {'_skip': reason}."""
    reported = parse_datetime(sheet_row.get("ReportedDateTime"))
    checked = parse_datetime(sheet_row.get("CheckedDate"))
    start = reported or checked
    if not start:
        return {"_skip": "no_date"}

    tanks = split_tanks(sheet_row.get("SiteName", ""))
    if not tanks:
        return {"_skip": "unknown_equipment", "_detail": str(sheet_row.get("SiteName", "")).strip()}

    reporter = resolve_user(sheet_row.get("CheckedBy", ""))
    notes_raw = str(sheet_row.get("Notes", "")).strip()
    tracker_notes_parts = [f"SiteName: {sheet_row.get('SiteName', '').strip()}"]
    if notes_raw:
        tracker_notes_parts.append(f"Notes: {notes_raw}")
    tracker_notes_parts.append(NOTES_MARKER)
    tracker_notes = " | ".join(tracker_notes_parts)

    tracker_id = str(uuid.uuid4())
    tracker = {
        "id": tracker_id,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "site_id": None,
        "ops_task_id": OPS_TASK_ID,
        "start_time": start.isoformat(),
        "stop_time": start.isoformat(),
        "is_completed": True,
        "notes": tracker_notes,
        "created_by": reporter,
        "updated_by": reporter,
    }

    results = []
    for tank_id in tanks:
        for (sheet_col, qtext, rtype, _pass, _order) in QUESTIONS:
            result = {
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "ops_task_tracker_id": tracker_id,
                "ops_template_id": TEMPLATE_ID,
                "ops_template_question_id": question_uuid(qtext),
                "site_id": None,
                "equipment_id": tank_id,
                "response_boolean": None,
                "response_numeric": None,
                "response_enum": None,
                "response_text": None,
                "created_by": reporter,
                "updated_by": reporter,
            }
            raw = sheet_row.get(sheet_col)
            if rtype == "Boolean":
                result["response_boolean"] = parse_bool(raw)
            elif rtype == "Numeric":
                result["response_numeric"] = parse_numeric(raw)
            results.append(result)

    return {"tracker": tracker, "results": results}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("SPRAY PRE-CHECK MIGRATION")
    print("=" * 60)

    clear_existing()
    ensure_template(supabase)

    wb = gc.open_by_key(GROW_SHEET_ID)
    print("\nReading grow_spray_pre_check...")
    records = wb.worksheet("grow_spray_pre_check").get_all_records()
    print(f"  {len(records)} rows")

    trackers = []
    results = []
    skip_counts = {}
    unknown_equipment = set()

    for r in records:
        out = build_rows(r)
        if "_skip" in out:
            reason = out["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            if reason == "unknown_equipment":
                unknown_equipment.add(out["_detail"])
            continue
        trackers.append(out["tracker"])
        results.extend(out["results"])

    print(f"\n  Built {len(trackers)} trackers, {len(results)} template_result rows")
    for reason, cnt in sorted(skip_counts.items()):
        print(f"  Skipped {cnt} rows: {reason}")
    if unknown_equipment:
        print(f"  Unknown SiteName values: {sorted(unknown_equipment)}")

    with get_pg_conn() as conn:
        print(f"\n--- ops_task_tracker ---")
        pg_bulk_insert(conn, "ops_task_tracker", trackers)
        print(f"  Inserted {len(trackers)} rows")
        print(f"\n--- ops_template_result ---")
        pg_bulk_insert(conn, "ops_template_result", results)
        print(f"  Inserted {len(results)} rows")
        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
