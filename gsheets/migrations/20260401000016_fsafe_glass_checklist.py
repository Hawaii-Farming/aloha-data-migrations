"""
Migrate Food Safety Glass Inspection Logs (Cuke + Lettuce)
============================================================
Migrates fsafe_log_glass into two farm-scoped templates:
  - cuke_glass    -> 5 questions, site bip_ph
  - lettuce_glass -> 8 questions, site lettuce_ph

The legacy sheet is one tab with a Farm column distinguishing rows.
Some columns are filled by only one farm (e.g. the GH Emergency Exit
Light questions are lettuce-only) so each farm gets its own template
with only the questions it actually answers.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_glass: 40 rows total (16 cuke + 24 lettuce)

Usage:
    python migrations/20260401000016_fsafe_glass_checklist.py

Rerunnable: clears trackers/results scoped to each farm's glass template.
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
from gsheets.migrations._pg import paginate_select

FSAFE_SHEET_ID = SHEET_IDS["fsafe"]
TASK_ID = "food_safety_log"

# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------
# Each farm gets its own template containing only the questions it actually
# fills in the legacy sheet.

CUKE_GLASS_QUESTIONS = [
    ("Forklift mirrors, head and back up lights",       "boolean", {"boolean_pass_value": True}),
    ("PH Windows",                                       "boolean", {"boolean_pass_value": True}),
    ("PH Emergency Exit Lights - East and North doors",  "boolean", {"boolean_pass_value": True}),
    ("PH Restroom - Soap & Towel Dispensers",            "boolean", {"boolean_pass_value": True}),
    ("PH Restrooms - Glass Mirrors",                     "boolean", {"boolean_pass_value": True}),
]

LETTUCE_GLASS_QUESTIONS = [
    ("GH Emergency Exit Lights - NW, NE and SW doors",      "boolean", {"boolean_pass_value": True}),
    ("GH Emergency Exit Light Fixtures - East and West",    "boolean", {"boolean_pass_value": True}),
    ("Forklift mirrors, head and back up lights",            "boolean", {"boolean_pass_value": True}),
    ("PH Windows",                                            "boolean", {"boolean_pass_value": True}),
    ("PH Emergency Exit Lights - East and North doors",       "boolean", {"boolean_pass_value": True}),
    ("PH Hand Wash - Soap & Towel Dispensers",                "boolean", {"boolean_pass_value": True}),
    ("PH Restroom - Soap & Towel Dispensers",                 "boolean", {"boolean_pass_value": True}),
    # Only 3 of 24 lettuce rows have this filled — not required
    ("PH Restrooms - Glass Mirrors",                          "boolean", {"boolean_pass_value": True, "is_required": False}),
]

TEMPLATES = [
    {
        "id": "cuke_glass",
        "name": "Glass Inspection",
        "farm_name": "Cuke",
        "site_id": "bip_ph",
        "sheet_farm": "Cuke",
        "questions": CUKE_GLASS_QUESTIONS,
        "description": "Cuke monthly glass and brittle plastic inspection (migrated from legacy fsafe sheet)",
    },
    {
        "id": "lettuce_glass",
        "name": "Glass Inspection",
        "farm_name": "Lettuce",
        "site_id": "lettuce_ph",
        "sheet_farm": "Lettuce",
        "questions": LETTUCE_GLASS_QUESTIONS,
        "description": "Lettuce monthly glass and brittle plastic inspection (migrated from legacy fsafe sheet)",
    },
]


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
        return None
    s = str(val).strip().upper()
    if not s:
        return None
    if s in ("TRUE", "YES", "1"):
        return True
    if s in ("FALSE", "NO", "0"):
        return False
    return None


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
        "sys_access_level_name": "Employee",
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
# Setup: templates, questions, task links
# ---------------------------------------------------------------------------

def upsert_templates(supabase):
    rows = []
    next_order = 50
    for t in TEMPLATES:
        rows.append(audit({
            "id": t["id"],
            "org_id": ORG_ID,
            "farm_name": t["farm_name"],
            "name": t["name"],
            "org_module_name": "food_safety",
            "description": t["description"],
            "display_order": next_order,
        }))
        next_order += 1
    insert_rows(supabase, "ops_template", rows, upsert=True)


def reseed_questions(supabase):
    print("\nClearing existing questions for these templates...")
    for t in TEMPLATES:
        supabase.table("ops_template_question").delete().eq("ops_template_name", t["id"]).execute()
    print("  Cleared")

    rows = []
    for t in TEMPLATES:
        for order, (q_text, rtype, kw) in enumerate(t["questions"], start=1):
            rows.append(audit({
                "org_id": ORG_ID,
                "farm_name": t["farm_name"],
                "ops_template_name": t["id"],
                "question_text": q_text,
                "response_type": rtype,
                "is_required": kw.get("is_required", True),
                "boolean_pass_value": kw.get("boolean_pass_value"),
                "minimum_value": kw.get("minimum_value"),
                "maximum_value": kw.get("maximum_value"),
                "enum_options": kw.get("enum_options"),
                "enum_pass_options": kw.get("enum_pass_options"),
                "include_photo": kw.get("include_photo", False),
                "display_order": order,
                "is_deleted": kw.get("is_deleted", False),
            }))

    inserted = insert_rows(supabase, "ops_template_question", rows)
    q_map = {}
    for r in inserted:
        q_map[(r["ops_template_name"], r["question_text"])] = r["id"]
    return q_map


def upsert_task_template_links(supabase):
    for t in TEMPLATES:
        supabase.table("ops_task_template").delete().eq(
            "ops_template_name", t["id"]
        ).eq("ops_task_name", TASK_ID).execute()

    rows = []
    for t in TEMPLATES:
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_name": t["farm_name"],
            "ops_task_name": TASK_ID,
            "ops_template_name": t["id"],
        }))
    insert_rows(supabase, "ops_task_template", rows)


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    """Clear glass-inspection data so the migration is rerunnable.

    Trackers at bip_ph/lettuce_ph are shared with the PH Pre/Post checklist
    trackers, so we can't blanket-delete by site. Instead we:
      1. Delete results for the glass templates (this orphans the trackers)
      2. Delete any orphaned glass trackers (trackers with no results) via SQL
    """
    print("\nClearing existing glass-inspection data...")
    template_ids = tuple(t["id"] for t in TEMPLATES)

    # Capture tracker IDs that point at our templates BEFORE we delete the results
    tracker_ids_to_delete = set()
    for tid in template_ids:
        result = (
            supabase.table("ops_template_result")
            .select("ops_task_tracker_id")
            .eq("ops_template_name", tid)
            .execute()
        )
        for r in result.data:
            tracker_ids_to_delete.add(r["ops_task_tracker_id"])

    # Now delete the results + corrective actions
    for tid in template_ids:
        supabase.table("ops_template_result").delete().eq("ops_template_name", tid).execute()
        supabase.table("ops_corrective_action_taken").delete().eq("ops_template_name", tid).execute()

    # Delete the previously-captured tracker IDs (now orphaned)
    if tracker_ids_to_delete:
        supabase.table("ops_task_tracker").delete().in_("id", list(tracker_ids_to_delete)).execute()
        print(f"  Cleared {len(tracker_ids_to_delete)} orphaned glass trackers")

    print("  Cleared ops_template_result + ops_corrective_action_taken (glass templates)")


# ---------------------------------------------------------------------------
# Per-template migration
# ---------------------------------------------------------------------------

def migrate_template(supabase, gc, template_def, q_map, all_records, email_map, stub_cache):
    template_id = template_def["id"]
    farm_name = template_def["farm_name"]
    site_id = template_def["site_id"]
    sheet_farm = template_def["sheet_farm"]
    questions = template_def["questions"]

    print(f"\n=== {template_id} ({sheet_farm}) ===")

    # Filter to rows for this farm
    records = [r for r in all_records if str(r.get("Farm", "")).strip() == sheet_farm]
    print(f"  {len(records)} sheet rows")

    trackers = []
    pending_results = []
    skipped_missing_date = 0

    for r in records:
        reported = parse_datetime(r.get("Reported Time")) or parse_datetime(r.get("Checked Date"))
        if not reported:
            skipped_missing_date += 1
            continue

        verified_at = parse_datetime(r.get("Verified Time"))
        verified_by_id = resolve_verifier(supabase, str(r.get("Verified By", "")).strip(), email_map, stub_cache)
        reported_by_raw = str(r.get("Reported By", "")).strip()
        reported_by = reported_by_raw.lower() if "@" in reported_by_raw else AUDIT_USER

        tracker_idx = len(trackers)
        trackers.append({
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "site_id": site_id,
            "ops_task_name": TASK_ID,
            "start_time": reported,
            "stop_time": reported,
            "is_completed": True,
            "verified_at": verified_at,
            "verified_by": verified_by_id,
            "created_by": reported_by,
            "updated_by": reported_by,
        })

        for q_text, rtype, _kw in questions:
            q_id = q_map.get((template_id, q_text))
            if not q_id:
                continue
            pending_results.append((tracker_idx, q_id, rtype, r.get(q_text)))

    print(f"  Building {len(trackers)} trackers")
    if skipped_missing_date:
        print(f"  Skipped {skipped_missing_date} rows: no parseable date")

    if not trackers:
        return

    inserted_trackers = insert_rows(supabase, "ops_task_tracker", trackers)

    result_rows = []
    for tracker_idx, q_id, rtype, raw in pending_results:
        tracker = inserted_trackers[tracker_idx]
        row = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "ops_task_tracker_id": tracker["id"],
            "ops_template_name": template_id,
            "ops_template_question_id": q_id,
            "site_id": site_id,
            "created_by": tracker["created_by"],
            "updated_by": tracker["updated_by"],
        }
        if rtype == "boolean":
            row["response_boolean"] = parse_bool_cell(raw)
        elif rtype == "numeric":
            try:
                v = str(raw).strip()
                row["response_numeric"] = float(v) if v else None
            except (ValueError, TypeError):
                row["response_numeric"] = None
        result_rows.append(row)

    insert_rows(supabase, "ops_template_result", result_rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE CHECKLIST MIGRATION - Glass Inspections (Cuke + Lettuce)")
    print("=" * 60)

    clear_existing_data(supabase)
    upsert_templates(supabase)
    q_map = reseed_questions(supabase)
    upsert_task_template_links(supabase)

    email_map = load_employee_email_map(supabase)
    stub_cache = {}

    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_glass")
    all_records = ws.get_all_records()
    print(f"\nLoaded {len(all_records)} total rows from fsafe_log_glass")

    for template_def in TEMPLATES:
        migrate_template(supabase, gc, template_def, q_map, all_records, email_map, stub_cache)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
