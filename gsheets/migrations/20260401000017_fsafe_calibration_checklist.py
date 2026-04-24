"""
Migrate Food Safety Calibration Logs (Cuke + Lettuce)
======================================================
Migrates fsafe_log_calibration into two equipment-scoped templates:
  - cuke_calibration    -> 18 questions, equipment-targeted
  - lettuce_calibration -> 18 questions, equipment-targeted

Each calibration session (one sheet row) becomes ONE ops_task_tracker
with multiple equipment-scoped ops_template_result rows. Equipment is
created in org_equipment for each thermometer / scale / luminometer.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_calibration: 50 rows (25 cuke + 25 lettuce)

Site: bip_ph (cuke equipment) / lettuce_ph (lettuce equipment).
Tracker site_id is null because results target equipment, not a site.

Pass criteria caveat:
  Temperature obs/NIST pairs require obs to be within +-2 degrees of
  NIST. The schema has no way to express that as a column-vs-column
  comparison, so the (obs) and (NIST) questions both have no min/max
  and is_required=false. The pass evaluation will be redesigned in a
  future template version. Scale calibration uses min=498/max=502
  from fsafe_test_name.Scale Calibariton. Luminometer questions are
  pass-on-true booleans.

Equipment-scoped uniqueness requires the partial index
uq_ops_template_result_checklist_equipment, added in
20260401000046_ops_template_result.sql.

Usage:
    python migrations/20260401000017_fsafe_calibration_checklist.py

Rerunnable: clears trackers/results scoped to each farm's calibration
template, leaves the equipment rows in place across reruns.
"""

import re
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
from _pg import paginate_select

FSAFE_SHEET_ID = SHEET_IDS["fsafe"]
TASK_ID = "food_safety_log"

# ---------------------------------------------------------------------------
# Per-farm config
# ---------------------------------------------------------------------------
# (template_id, farm_id, host_site_id, sheet_farm_value)
FARMS = [
    {"farm_id": "cuke",    "host_site_id": "bip_ph",     "sheet_farm": "Cuke",
     "template_id": "cuke_calibration",    "template_name": "Calibration"},
    {"farm_id": "lettuce", "host_site_id": "lettuce_ph", "sheet_farm": "Lettuce",
     "template_id": "lettuce_calibration", "template_name": "Calibration"},
]

# Equipment definitions per farm. id is farm-prefixed; name is unprefixed
# since farm_id already scopes the row.
def equipment_for(farm_id, host_site_id):
    rows = []
    rows.append({"id": f"{farm_id}_cooler_1_thermometer", "name": "Cooler 1 Thermometer"})
    rows.append({"id": f"{farm_id}_cooler_2_thermometer", "name": "Cooler 2 Thermometer"})
    rows.append({"id": f"{farm_id}_pack_room_thermometer", "name": "Pack Room Thermometer"})
    for n in range(1, 10):
        rows.append({"id": f"{farm_id}_scale_{n}", "name": f"Scale {n}"})
    rows.append({"id": f"{farm_id}_luminometer", "name": "Luminometer"})
    return [
        {**r, "farm_id": farm_id, "site_id": host_site_id, "type": "tool"}
        for r in rows
    ]


# Question rows: (question_text, response_type, kwargs, equipment_id_suffix, sheet_column, value_kind)
# value_kind: 'numeric' or 'boolean' — controls how the cell is parsed.
# equipment_id_suffix is the part after the farm prefix (e.g. 'cooler_1_thermometer').
QUESTION_DEFS = [
    # Cooler 1 Thermometer
    ("Cooler 1 Thermometer - Observed Reading",      "numeric", {"is_required": False},
     "cooler_1_thermometer", "Cooler 1 Temperature (obs)",  "numeric"),
    ("Cooler 1 Thermometer - NIST Reference Reading","numeric", {"is_required": False},
     "cooler_1_thermometer", "Cooler 1 Temperature (NIST)", "numeric"),

    # Cooler 2 Thermometer
    ("Cooler 2 Thermometer - Observed Reading",      "numeric", {"is_required": False},
     "cooler_2_thermometer", "Cooler 2 Temperature (obs)",  "numeric"),
    ("Cooler 2 Thermometer - NIST Reference Reading","numeric", {"is_required": False},
     "cooler_2_thermometer", "Cooler 2 Temperature (NIST)", "numeric"),

    # Pack Room Thermometer
    ("Pack Room Thermometer - Observed Reading",      "numeric", {"is_required": False},
     "pack_room_thermometer", "Pack Room Temperature (obs)",  "numeric"),
    ("Pack Room Thermometer - NIST Reference Reading","numeric", {"is_required": False},
     "pack_room_thermometer", "Pack Room Temperature (NIST)", "numeric"),

    # Scales 1-9 (range from fsafe_test_name.Scale Calibariton: 498-502)
    ("Scale 1 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_1", "Scale 1", "numeric"),
    ("Scale 2 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_2", "Scale 2", "numeric"),
    ("Scale 3 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_3", "Scale 3", "numeric"),
    ("Scale 4 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_4", "Scale 4", "numeric"),
    ("Scale 5 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_5", "Scale 5", "numeric"),
    ("Scale 6 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_6", "Scale 6", "numeric"),
    ("Scale 7 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_7", "Scale 7", "numeric"),
    ("Scale 8 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_8", "Scale 8", "numeric"),
    ("Scale 9 - Calibration Reading", "numeric", {"minimum_value": 498, "maximum_value": 502, "is_required": False},
     "scale_9", "Scale 9", "numeric"),

    # Luminometer (3 boolean tests, all on the same equipment).
    # Note: sheet column 'Luminometers Internal LED ' has a trailing space — preserved
    # in the lookup, but the question text is cleaned.
    ("Luminometer - Negative Control Test", "boolean", {"boolean_pass_value": True},
     "luminometer", "Luminometers Negative", "boolean"),
    ("Luminometer - Internal LED Test",     "boolean", {"boolean_pass_value": True},
     "luminometer", "Luminometers Internal LED ", "boolean"),
    ("Luminometer - Positive Control Test", "boolean", {"boolean_pass_value": True},
     "luminometer", "Luminometers Positive", "boolean"),
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


def parse_numeric_cell(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
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
# Setup: equipment, templates, questions, task links
# ---------------------------------------------------------------------------

def upsert_equipment(supabase):
    rows = []
    for farm in FARMS:
        for eq in equipment_for(farm["farm_id"], farm["host_site_id"]):
            rows.append(audit({
                "id": eq["id"],
                "org_id": ORG_ID,
                "farm_id": eq["farm_id"],
                "site_id": eq["site_id"],
                "type": eq["type"],
                "name": eq["name"],
            }))
    insert_rows(supabase, "org_equipment", rows, upsert=True)


def upsert_templates(supabase):
    rows = []
    next_order = 60
    for farm in FARMS:
        rows.append(audit({
            "id": farm["template_id"],
            "org_id": ORG_ID,
            "farm_id": farm["farm_id"],
            "name": farm["template_name"],
            "org_module_id": "food_safety",
            "description": (
                f"{farm['sheet_farm']} monthly equipment calibration: thermometers (obs vs NIST), "
                f"packing scales (498-502 g), and luminometer controls. "
                "Pass evaluation for the obs/NIST temperature delta (within +-2 degrees) is "
                "computed at query time, not in the question schema; will be redesigned later."
            ),
            "display_order": next_order,
        }))
        next_order += 1
    insert_rows(supabase, "ops_template", rows, upsert=True)


def reseed_questions(supabase):
    """Returns: dict of {(template_id, question_text): question_id}"""
    print("\nClearing existing questions for these templates...")
    for farm in FARMS:
        supabase.table("ops_template_question").delete().eq("ops_template_id", farm["template_id"]).execute()
    print("  Cleared")

    rows = []
    for farm in FARMS:
        for order, (q_text, rtype, kw, _eq_suffix, _sheet_col, _vk) in enumerate(QUESTION_DEFS, start=1):
            rows.append(audit({
                "org_id": ORG_ID,
                "farm_id": farm["farm_id"],
                "ops_template_id": farm["template_id"],
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
        q_map[(r["ops_template_id"], r["question_text"])] = r["id"]
    return q_map


def upsert_task_template_links(supabase):
    for farm in FARMS:
        supabase.table("ops_task_template").delete().eq(
            "ops_template_id", farm["template_id"]
        ).eq("ops_task_id", TASK_ID).execute()

    rows = []
    for farm in FARMS:
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_id": farm["farm_id"],
            "ops_task_id": TASK_ID,
            "ops_template_id": farm["template_id"],
        }))
    insert_rows(supabase, "ops_task_template", rows)


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    """Clear calibration data so the migration is rerunnable.

    Same orphaned-tracker pattern as the glass script: capture tracker IDs
    via existing results, delete the results, then delete the trackers.
    """
    print("\nClearing existing calibration data...")
    template_ids = [farm["template_id"] for farm in FARMS]

    tracker_ids_to_delete = set()
    for tid in template_ids:
        result = (
            supabase.table("ops_template_result")
            .select("ops_task_tracker_id")
            .eq("ops_template_id", tid)
            .execute()
        )
        for r in result.data:
            tracker_ids_to_delete.add(r["ops_task_tracker_id"])

    for tid in template_ids:
        supabase.table("ops_template_result").delete().eq("ops_template_id", tid).execute()
        supabase.table("ops_corrective_action_taken").delete().eq("ops_template_id", tid).execute()

    if tracker_ids_to_delete:
        # Delete in chunks of 100 since IN clauses get unwieldy
        ids = list(tracker_ids_to_delete)
        for i in range(0, len(ids), 100):
            chunk = ids[i:i + 100]
            supabase.table("ops_task_tracker").delete().in_("id", chunk).execute()
        print(f"  Cleared {len(ids)} orphaned calibration trackers")

    print("  Cleared ops_template_result + ops_corrective_action_taken (calibration templates)")


# ---------------------------------------------------------------------------
# Per-farm migration
# ---------------------------------------------------------------------------

def migrate_farm(supabase, farm, all_records, q_map, email_map, stub_cache):
    template_id = farm["template_id"]
    farm_id = farm["farm_id"]
    sheet_farm = farm["sheet_farm"]

    print(f"\n=== {template_id} ({sheet_farm}) ===")
    records = [r for r in all_records if str(r.get("Farm", "")).strip() == sheet_farm]
    print(f"  {len(records)} sheet rows")

    trackers = []
    pending = []  # (tracker_idx, q_id, equipment_id, value_kind, raw_value)
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

        # Calibration tracker — site_id null because results target equipment
        tracker_idx = len(trackers)
        trackers.append({
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "site_id": None,
            "ops_task_id": TASK_ID,
            "start_time": reported,
            "stop_time": reported,
            "is_completed": True,
            "verified_at": verified_at,
            "verified_by": verified_by_id,
            "created_by": reported_by,
            "updated_by": reported_by,
        })

        for q_text, _rtype, _kw, eq_suffix, sheet_col, value_kind in QUESTION_DEFS:
            q_id = q_map.get((template_id, q_text))
            if not q_id:
                continue
            equipment_id = f"{farm_id}_{eq_suffix}"
            pending.append((tracker_idx, q_id, equipment_id, value_kind, r.get(sheet_col)))

    print(f"  Building {len(trackers)} trackers")
    if skipped_missing_date:
        print(f"  Skipped {skipped_missing_date} rows: no parseable date")

    if not trackers:
        return

    inserted_trackers = insert_rows(supabase, "ops_task_tracker", trackers)

    result_rows = []
    for tracker_idx, q_id, equipment_id, value_kind, raw in pending:
        tracker = inserted_trackers[tracker_idx]
        row = {
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "ops_task_tracker_id": tracker["id"],
            "ops_template_id": template_id,
            "ops_template_question_id": q_id,
            "site_id": None,         # equipment-scoped
            "equipment_id": equipment_id,
            "created_by": tracker["created_by"],
            "updated_by": tracker["updated_by"],
        }
        if value_kind == "boolean":
            row["response_boolean"] = parse_bool_cell(raw)
        else:
            row["response_numeric"] = parse_numeric_cell(raw)
        result_rows.append(row)

    insert_rows(supabase, "ops_template_result", result_rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE CHECKLIST MIGRATION - Calibration (Cuke + Lettuce)")
    print("=" * 60)

    clear_existing_data(supabase)
    upsert_equipment(supabase)
    upsert_templates(supabase)
    q_map = reseed_questions(supabase)
    upsert_task_template_links(supabase)

    email_map = load_employee_email_map(supabase)
    stub_cache = {}

    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_calibration")
    all_records = ws.get_all_records()
    print(f"\nLoaded {len(all_records)} total rows from fsafe_log_calibration")

    for farm in FARMS:
        migrate_farm(supabase, farm, all_records, q_map, email_map, stub_cache)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
