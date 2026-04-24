"""
Migrate Food Safety Checklist Logs (Lettuce PH Pre/Post + foreign material events)
====================================================================================
Migrates fsafe_log_L_ph_pre and fsafe_log_L_ph_post tabs into the
checklist workflow. ATP swabs route to fsafe_result. Historical foreign
material events (~18 rows) become standalone foreign_material_event
trackers — one tracker per material type, with photos copied to each.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_L_ph_pre:  ~580 rows -> lettuce_ph_pre_ops template (44 questions)
  - fsafe_log_L_ph_post: ~395 rows -> lettuce_ph_post_ops template + ATP fsafe_result + foreign material events

Site: lettuce_ph

Retired questions (is_deleted=true) — workflow consolidated this year:
  PH Pre:  Boot Room / Packing Room / South Side Foot Dip Checked (booleans),
           Cooler Humidity (numeric, no recent fills)

No-range numerics (is_required=false):
  Floor Foamer Concentration, Packing Room Humidity

Numeric ranges from fsafe_test_name:
  Foot Dip Concentration:                 800-1000
  Cooler Temperature - Lettuce PH:         32-40
  Pack Room Temperature - Lettuce PH:      40-50
  Cleaner Dilution Concentration:           4-8
  Equipment Sanitizer Concentration:      200-400

Foreign material handling (option ii):
  For each row with a non-empty 'Types of Foreign Material' value, split on '&'
  and create ONE separate tracker PER material type. Each tracker gets a single
  ops_template_result on the org-scoped foreign_material_event template, plus
  copies of all photos from that sheet row attached to its result.

Usage:
    python migrations/20260401000015_fsafe_lettuce_ph_checklist.py

Rerunnable: clears trackers/results/atp results scoped to lettuce
food_safety_log at site 'lettuce_ph', plus foreign_material_event data
created by this script.
"""

import re
import sys
from datetime import datetime
from difflib import SequenceMatcher
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
FARM_ID = "lettuce"
SITE_ID = "lettuce_ph"
ATP_LAB_ID = "hf"
ATP_TEST_ID = "atp_rlu"
FM_TEMPLATE_ID = "foreign_material_event"
FM_ENUM_OPTIONS = [
    "Glass", "Metal", "Wood", "Plastic", "Hair",
    "Insect", "Rubber", "Paper", "Excessive Soil", "Other",
]

# ---------------------------------------------------------------------------
# Question definitions
# ---------------------------------------------------------------------------

PH_PRE_QUESTIONS = [
    # Pack date gate (kept as boolean, not required since meaning is conditional)
    ("Is Pack Date",                                "boolean", {"boolean_pass_value": True, "is_required": False}),

    # Restroom block (slight column drift in 2024 — not required)
    ("Toilet Works",                                "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Toilet Clean",                                "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Toilet Paper Stocked",                        "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Paper Towels Restocked",                      "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Soap Dispensers Refilled",                    "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Trash Bin Emptied",                           "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Floor Drain Cleared",                         "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Sink Cleaned",                                "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Floor Swept and Mopped",                      "boolean", {"boolean_pass_value": True, "is_required": False}),

    # Core packhouse cleanliness block (always filled)
    ("Dryer and Bin Fill Tables Clean",             "boolean", {"boolean_pass_value": True}),
    ("Blending Tables Clean",                       "boolean", {"boolean_pass_value": True}),
    ("Packing Tables Clean",                        "boolean", {"boolean_pass_value": True}),
    ("Pro Seal Feed Conveyor Clean",                "boolean", {"boolean_pass_value": True}),
    ("Pro Seal Machine Clean",                      "boolean", {"boolean_pass_value": True}),
    ("Metal Detector Clean",                        "boolean", {"boolean_pass_value": True}),
    ("Accumulation Table Clean",                    "boolean", {"boolean_pass_value": True}),
    ("Case-Up Table Clean",                         "boolean", {"boolean_pass_value": True}),
    ("Packing Room Clean",                          "boolean", {"boolean_pass_value": True}),
    ("Cooler Clean",                                "boolean", {"boolean_pass_value": True}),
    ("Box Assembly Area Clean",                     "boolean", {"boolean_pass_value": True}),
    ("Dry Storage Room Clean",                      "boolean", {"boolean_pass_value": True}),
    ("Changing and Break Areas Clean",              "boolean", {"boolean_pass_value": True}),
    ("Restrooms Clean and Stocked",                 "boolean", {"boolean_pass_value": True}),
    ("Handwash Sinks Clean and Stocked",            "boolean", {"boolean_pass_value": True}),
    ("Boot Room Clean",                             "boolean", {"boolean_pass_value": True}),
    ("Packaging and Totes Stored Off the Floor",    "boolean", {"boolean_pass_value": True}),
    ("Hand Sanitizers Stocked",                     "boolean", {"boolean_pass_value": True}),

    # Worker hygiene mini-block (slight 2024 drift — not required)
    ("No Jewelry, Personal Items, Food or Drinks in Processing Area", "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Protective Clothing and Dedicated Footwear Worn", "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Washing Hands in Compliance",                 "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("No Visible Wounds, Sores or Illnesses",       "boolean", {"boolean_pass_value": True, "is_required": False}),

    ("Doors Closed and Sealed",                     "boolean", {"boolean_pass_value": True}),

    # Retired booleans — workflow consolidated this year, kept for history
    ("Boot Room Foot Dip Checked",                  "boolean", {"boolean_pass_value": True, "is_required": False, "is_deleted": True}),
    ("Packing Room Foot Dip Checked",               "boolean", {"boolean_pass_value": True, "is_required": False, "is_deleted": True}),
    ("South Side Foot Dip Checked",                 "boolean", {"boolean_pass_value": True, "is_required": False, "is_deleted": True}),

    # Numeric measurements
    ("Boot Room Foot Dip Concentration",            "numeric", {"minimum_value": 800, "maximum_value": 1000}),
    ("Packing Room Foot Dip Concentration",         "numeric", {"minimum_value": 800, "maximum_value": 1000}),
    ("South Side Foot Dip Concentration",           "numeric", {"minimum_value": 800, "maximum_value": 1000}),
    ("Floor Foamer Concentration",                  "numeric", {"is_required": False}),
    ("Packing Room Temperature",                    "numeric", {"minimum_value": 40, "maximum_value": 50}),
    ("Packing Room Humidity",                       "numeric", {"is_required": False}),
    ("Cooler Temperature",                          "numeric", {"minimum_value": 32, "maximum_value": 40}),
    # Retired — no recent fills
    ("Cooler Humidity",                             "numeric", {"is_required": False, "is_deleted": True}),
]

PH_POST_QUESTIONS = [
    ("Dryer and Bin Fill Tables Clean",             "boolean", {"boolean_pass_value": True}),
    ("Blending Bins Clean",                         "boolean", {"boolean_pass_value": True}),
    ("Blending Tables Clean",                       "boolean", {"boolean_pass_value": True}),
    ("Packing Tables Clean",                        "boolean", {"boolean_pass_value": True}),
    ("Pro Seal Feed Conveyor Clean",                "boolean", {"boolean_pass_value": True}),
    ("Pro Seal Machine Clean",                      "boolean", {"boolean_pass_value": True}),
    ("Metal Detector Clean",                        "boolean", {"boolean_pass_value": True}),
    ("Accumulation Table Clean",                    "boolean", {"boolean_pass_value": True}),
    ("Case-Up Table Clean",                         "boolean", {"boolean_pass_value": True}),
    ("Packing Room Clean",                          "boolean", {"boolean_pass_value": True}),
    ("Cooler Clean",                                "boolean", {"boolean_pass_value": True}),
    ("Box Assembly Area Clean",                     "boolean", {"boolean_pass_value": True}),
    ("Dry Storage Room Clean",                      "boolean", {"boolean_pass_value": True}),
    ("Changing and Break Areas Clean",              "boolean", {"boolean_pass_value": True}),
    ("Restrooms Clean and Stocked",                 "boolean", {"boolean_pass_value": True}),
    ("Handwash Sinks Clean and Stocked",            "boolean", {"boolean_pass_value": True}),
    ("Drain Clean",                                 "boolean", {"boolean_pass_value": True}),
    ("Test Strip Is Not Expired",                   "boolean", {"boolean_pass_value": True, "is_required": False}),

    # Numerics with ranges from fsafe_test_name
    ("Cleaner Dilution Concentration",              "numeric", {"minimum_value":   4, "maximum_value":    8}),
    ("Boot Room Foot Dip Concentration",            "numeric", {"minimum_value": 800, "maximum_value": 1000}),
    ("Packing Room Foot Dip Concentration",         "numeric", {"minimum_value": 800, "maximum_value": 1000}),
    ("South Side Foot Dip Concentration",           "numeric", {"minimum_value": 800, "maximum_value": 1000}),
    ("Equipment Sanitizer Concentration",           "numeric", {"minimum_value": 200, "maximum_value":  400}),
    ("Cooler Temperature",                          "numeric", {"minimum_value":  32, "maximum_value":   40}),
    ("Packing Room Temperature",                    "numeric", {"minimum_value":  40, "maximum_value":   50, "is_required": False}),
]

TEMPLATES = [
    {
        "id": "lettuce_ph_pre_ops",
        "name": "PH Pre Ops",
        "tab": "fsafe_log_L_ph_pre",
        "questions": PH_PRE_QUESTIONS,
        "description": "Lettuce packhouse pre-operations checklist (migrated from legacy fsafe sheet)",
    },
    {
        "id": "lettuce_ph_post_ops",
        "name": "PH Post Ops",
        "tab": "fsafe_log_L_ph_post",
        "questions": PH_POST_QUESTIONS,
        "description": "Lettuce packhouse post-operations cleanup checklist (migrated from legacy fsafe sheet)",
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
# ATP fuzzy matching (lettuce farm)
# ---------------------------------------------------------------------------

def normalize_site_name(s):
    s = str(s).strip().lower()
    s = re.sub(r"^(ph|gh)\s*-\s*", "", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s*#\s*", "#", s)
    return s


def build_site_matcher(supabase):
    result = (
        supabase.table("org_site")
        .select("id,name,site_id_parent")
        .eq("farm_name", FARM_ID)
        .eq("org_site_category_id", "food_safety")
        .execute()
    )
    sites = result.data

    def prefer_score(name):
        n = name.lower()
        if "fcs" in n: return 3
        if "leg" in n or "bottom shelf" in n: return 0
        return 2

    candidates = [(s["id"], s["name"], normalize_site_name(s["name"]), prefer_score(s["name"])) for s in sites]
    cache = {}

    def match(raw_name):
        if raw_name in cache:
            return cache[raw_name]
        target = normalize_site_name(raw_name)
        if not target:
            cache[raw_name] = None
            return None
        best = None
        for sid, sname, snorm, pref in candidates:
            ratio = SequenceMatcher(None, target, snorm).ratio()
            if target in snorm or snorm in target:
                ratio = max(ratio, 0.9)
            if best is None or (ratio, pref) > (best[0], best[1]):
                best = (ratio, pref, sid, sname)
        if best and best[0] >= 0.78:
            cache[raw_name] = best[2]
            return best[2]
        cache[raw_name] = None
        return None

    return match, candidates


def auto_create_atp_site(supabase, raw_name, candidates):
    new_id = "lettuce_ph_" + to_id(raw_name)
    display_name = "PH - " + str(raw_name).strip()
    row = audit({
        "id": new_id,
        "org_id": ORG_ID,
        "farm_name": FARM_ID,
        "name": display_name,
        "org_site_category_id": "food_safety",
        "site_id_parent": SITE_ID,
        "display_order": 999,
    })
    try:
        supabase.table("org_site").upsert(row).execute()
    except Exception as e:
        print(f"  WARN failed to create ATP site '{raw_name}': {type(e).__name__}: {e}")
        return None
    candidates.append((new_id, display_name, normalize_site_name(display_name), 2))
    return new_id


# ---------------------------------------------------------------------------
# Setup: templates, questions, task links
# ---------------------------------------------------------------------------

def upsert_templates(supabase):
    rows = []
    next_order = 30
    for t in TEMPLATES:
        rows.append(audit({
            "id": t["id"],
            "org_id": ORG_ID,
            "farm_name": FARM_ID,
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
        supabase.table("ops_template_question").delete().eq("ops_template_id", t["id"]).execute()
    print("  Cleared")

    rows = []
    for t in TEMPLATES:
        for order, (q_text, rtype, kw) in enumerate(t["questions"], start=1):
            rows.append(audit({
                "org_id": ORG_ID,
                "farm_name": FARM_ID,
                "ops_template_id": t["id"],
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
    for t in TEMPLATES:
        supabase.table("ops_task_template").delete().eq(
            "ops_template_id", t["id"]
        ).eq("ops_task_name", TASK_ID).execute()

    rows = []
    for t in TEMPLATES:
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_name": FARM_ID,
            "ops_task_name": TASK_ID,
            "ops_template_id": t["id"],
        }))
    insert_rows(supabase, "ops_task_template", rows)


# ---------------------------------------------------------------------------
# Foreign material template setup (org-scoped, idempotent enum update)
# ---------------------------------------------------------------------------

def load_foreign_material_question_id(supabase):
    """Look up the foreign_material_event enum question ID.

    The template and its question are created by the fsafe lookup migration
    (20260401000008_fsafe.py). This script only inserts the historical
    foreign material event results, so it just needs to fetch the existing
    question ID to link results to.
    """
    print("\nLoading foreign_material_event question id...")
    result = (
        supabase.table("ops_template_question")
        .select("id")
        .eq("ops_template_id", FM_TEMPLATE_ID)
        .eq("question_text", "Type of foreign material")
        .execute()
    )
    if not result.data:
        raise SystemExit(
            f"ERROR: foreign_material_event template is missing its question. "
            f"Run 20260401000008_fsafe.py first."
        )
    fm_question_id = result.data[0]["id"]
    print(f"  foreign_material_event question id = {fm_question_id}")
    return fm_question_id


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    template_ids = [t["id"] for t in TEMPLATES]
    print("\nClearing existing checklist data for these templates...")

    # Capture tracker IDs from our own results before deleting anything.
    # This scopes the tracker delete precisely so we don't touch glass/
    # calibration trackers at the same site.
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
    # Foreign material trackers (lettuce-scoped)
    fm_result_rows = (
        supabase.table("ops_template_result")
        .select("id,ops_task_tracker_id")
        .eq("ops_template_id", FM_TEMPLATE_ID)
        .eq("farm_name", FARM_ID)
        .execute()
        .data
    )
    fm_result_ids = [r["id"] for r in fm_result_rows]
    for r in fm_result_rows:
        tracker_ids_to_delete.add(r["ops_task_tracker_id"])

    # Clear photos first (they FK to results) — only the lettuce foreign
    # material results have photos.
    if fm_result_ids:
        for i in range(0, len(fm_result_ids), 100):
            chunk = fm_result_ids[i:i + 100]
            supabase.table("ops_template_result_photo").delete().in_("ops_template_result_id", chunk).execute()
        print(f"  Cleared {len(fm_result_ids)} foreign material photos")

    for tid in template_ids:
        supabase.table("ops_template_result").delete().eq("ops_template_id", tid).execute()
    print("  Cleared ops_template_result (PH templates)")

    # Foreign material event results scoped to lettuce farm
    supabase.table("ops_template_result").delete().eq("ops_template_id", FM_TEMPLATE_ID).eq("farm_name", FARM_ID).execute()
    print("  Cleared ops_template_result (foreign_material_event, lettuce)")

    for tid in template_ids:
        supabase.table("ops_corrective_action_taken").delete().eq("ops_template_id", tid).execute()
    print("  Cleared ops_corrective_action_taken")

    # Delete the captured trackers in chunks
    if tracker_ids_to_delete:
        ids = list(tracker_ids_to_delete)
        for i in range(0, len(ids), 100):
            chunk = ids[i:i + 100]
            supabase.table("ops_task_tracker").delete().in_("id", chunk).execute()
        print(f"  Cleared {len(ids)} lettuce PH trackers")

    supabase.table("fsafe_result").delete().eq("fsafe_lab_test_id", ATP_TEST_ID).eq("farm_name", FARM_ID).execute()
    print(f"  Cleared fsafe_result (atp_rlu, lettuce)")


# ---------------------------------------------------------------------------
# Per-template migration (Pre/Post checklists)
# ---------------------------------------------------------------------------

def migrate_template(supabase, gc, template_def, q_map, email_map, stub_cache):
    tab = template_def["tab"]
    template_id = template_def["id"]
    questions = template_def["questions"]

    print(f"\n=== {template_id} <- {tab} ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet(tab)
    records = ws.get_all_records()
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
            "farm_name": FARM_ID,
            "site_id": SITE_ID,
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

    inserted_trackers = insert_rows(supabase, "ops_task_tracker", trackers)

    result_rows = []
    for tracker_idx, q_id, rtype, raw in pending_results:
        tracker = inserted_trackers[tracker_idx]
        row = {
            "org_id": ORG_ID,
            "farm_name": FARM_ID,
            "ops_task_tracker_id": tracker["id"],
            "ops_template_id": template_id,
            "ops_template_question_id": q_id,
            "site_id": SITE_ID,
            "created_by": tracker["created_by"],
            "updated_by": tracker["updated_by"],
        }
        if rtype == "boolean":
            row["response_boolean"] = parse_bool_cell(raw)
        elif rtype == "numeric":
            row["response_numeric"] = parse_numeric_cell(raw)
        elif rtype == "enum":
            v = str(raw).strip() if raw is not None else None
            row["response_enum"] = v or None
        result_rows.append(row)

    insert_rows(supabase, "ops_template_result", result_rows)


# ---------------------------------------------------------------------------
# ATP migration (PH Post only)
# ---------------------------------------------------------------------------

def migrate_atp(supabase, gc, email_map, stub_cache):
    print("\n=== ATP swabs (Lettuce PH Post) -> fsafe_result ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_L_ph_post")
    records = ws.get_all_records()

    matcher, candidates = build_site_matcher(supabase)
    auto_created = {}

    rows = []
    skipped_no_date = 0
    skipped_no_site = 0

    for r in records:
        sampled_at = parse_datetime(r.get("Reported Time")) or parse_datetime(r.get("Checked Date"))
        if not sampled_at:
            skipped_no_date += 1
            continue
        verified_at = parse_datetime(r.get("Verified Time"))
        verified_by_id = resolve_verifier(supabase, str(r.get("Verified By", "")).strip(), email_map, stub_cache)
        reported_by_raw = str(r.get("Reported By", "")).strip()
        reported_by = reported_by_raw.lower() if "@" in reported_by_raw else AUDIT_USER

        for slot in (1, 2, 3):
            site_raw = str(r.get(f"ATP Site {slot}", "")).strip()
            result_raw = r.get(f"ATP Results {slot}", "")
            if not site_raw and result_raw in ("", None):
                continue

            value = parse_numeric_cell(result_raw)

            site_id = matcher(site_raw) if site_raw else None
            if site_raw and not site_id:
                if site_raw in auto_created:
                    site_id = auto_created[site_raw]
                else:
                    site_id = auto_create_atp_site(supabase, site_raw, candidates)
                    if site_id:
                        auto_created[site_raw] = site_id

            if not site_id:
                skipped_no_site += 1
                continue

            result_pass = None
            if value is not None:
                result_pass = (0 <= value <= 30)

            rows.append({
                "org_id": ORG_ID,
                "farm_name": FARM_ID,
                "site_id": site_id,
                "fsafe_lab_name": ATP_LAB_ID,
                "fsafe_lab_test_id": ATP_TEST_ID,
                "result_numeric": value,
                "result_pass": result_pass,
                "status": "completed",
                "initial_retest_vector": "initial",
                "sampled_at": sampled_at,
                "sampled_by": verified_by_id,
                "completed_at": sampled_at,
                "verified_at": verified_at,
                "verified_by": verified_by_id,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

    if skipped_no_date:
        print(f"  Skipped {skipped_no_date} rows: no parseable date")
    if skipped_no_site:
        print(f"  Skipped {skipped_no_site} ATP slots: no resolvable site")
    print(f"  Auto-created {len(auto_created)} new ATP sites under {SITE_ID}")
    insert_rows(supabase, "fsafe_result", rows)


# ---------------------------------------------------------------------------
# Foreign material event migration (option ii: one tracker per material)
# ---------------------------------------------------------------------------

def migrate_foreign_material(supabase, gc, fm_question_id, email_map, stub_cache):
    print("\n=== Foreign Material Events (Lettuce PH Post) ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_L_ph_post")
    records = ws.get_all_records()

    # Normalize options for fuzzy match (lowercase)
    enum_lower = {opt.lower(): opt for opt in FM_ENUM_OPTIONS}

    def map_to_enum(raw_material):
        """Best-effort match a raw material string to a canonical enum option."""
        if not raw_material:
            return None
        s = raw_material.strip().lower()
        if not s:
            return None
        if s in enum_lower:
            return enum_lower[s]
        # Substring match
        for opt_lower, opt in enum_lower.items():
            if opt_lower in s or s in opt_lower:
                return opt
        return "Other"

    # Build per-tracker work units. Each material -> 1 tracker, 1 result, N photo rows
    trackers = []
    pending = []  # list of dicts: {tracker_idx, material, photo_urls, sampled_at, ...}

    skipped_missing_date = 0
    multi_material_rows = 0

    for r in records:
        types_raw = str(r.get("Types of Foreign Material", "")).strip()
        if not types_raw:
            continue

        sampled_at = parse_datetime(r.get("Reported Time")) or parse_datetime(r.get("Checked Date"))
        if not sampled_at:
            skipped_missing_date += 1
            continue
        verified_at = parse_datetime(r.get("Verified Time"))
        verified_by_id = resolve_verifier(supabase, str(r.get("Verified By", "")).strip(), email_map, stub_cache)
        reported_by_raw = str(r.get("Reported By", "")).strip()
        reported_by = reported_by_raw.lower() if "@" in reported_by_raw else AUDIT_USER

        # Collect photo URLs from this row (1-3 columns)
        # Normalize legacy 'images/fsafe_foreign_material/' -> 'images/ops_template_result/'
        photo_urls = []
        for col in ("Foreign Material Photo 01", "Foreign Material Photo 02", "Foreign Material Photo 03"):
            v = str(r.get(col, "")).strip()
            if v:
                v = v.replace("images/fsafe_foreign_material/", "images/ops_template_result/")
                photo_urls.append(v)

        # Split material types on '&'
        materials = [m.strip() for m in types_raw.split("&") if m.strip()]
        if len(materials) > 1:
            multi_material_rows += 1

        for material in materials:
            mapped = map_to_enum(material)
            tracker_idx = len(trackers)
            trackers.append({
                "org_id": ORG_ID,
                "farm_name": FARM_ID,
                "site_id": SITE_ID,
                "ops_task_name": TASK_ID,
                "start_time": sampled_at,
                "stop_time": sampled_at,
                "is_completed": True,
                "verified_at": verified_at,
                "verified_by": verified_by_id,
                "notes": f"Foreign material event (raw: {types_raw})",
                "created_by": reported_by,
                "updated_by": reported_by,
            })
            pending.append({
                "tracker_idx": tracker_idx,
                "mapped_enum": mapped,
                "raw_material": material,
                "raw_full": types_raw,
                "photo_urls": photo_urls,
                "reported_by": reported_by,
            })

    print(f"  {len(trackers)} foreign material trackers from "
          f"{len(set(p['raw_full'] for p in pending))} sheet rows ({multi_material_rows} with multiple materials)")
    if skipped_missing_date:
        print(f"  Skipped {skipped_missing_date} rows: no parseable date")

    if not trackers:
        return

    inserted_trackers = insert_rows(supabase, "ops_task_tracker", trackers)

    # Create one ops_template_result per material
    result_rows = []
    for p in pending:
        tracker = inserted_trackers[p["tracker_idx"]]
        result_rows.append({
            "org_id": ORG_ID,
            "farm_name": FARM_ID,
            "ops_task_tracker_id": tracker["id"],
            "ops_template_id": FM_TEMPLATE_ID,
            "ops_template_question_id": fm_question_id,
            "site_id": SITE_ID,
            "response_enum": p["mapped_enum"],
            "response_text": p["raw_material"],
            "created_by": p["reported_by"],
            "updated_by": p["reported_by"],
        })
    inserted_results = insert_rows(supabase, "ops_template_result", result_rows)

    # Photos: one row per (result × photo_url)
    photo_rows = []
    for p, result_row in zip(pending, inserted_results):
        for url in p["photo_urls"]:
            photo_rows.append({
                "org_id": ORG_ID,
                "farm_name": FARM_ID,
                "ops_template_result_id": result_row["id"],
                "photo_url": url,
                "created_by": p["reported_by"],
                "updated_by": p["reported_by"],
            })
    insert_rows(supabase, "ops_template_result_photo", photo_rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE CHECKLIST MIGRATION - Lettuce PH Pre/Post + Foreign Material")
    print("=" * 60)

    clear_existing_data(supabase)
    upsert_templates(supabase)
    q_map = reseed_questions(supabase)
    upsert_task_template_links(supabase)
    fm_question_id = load_foreign_material_question_id(supabase)

    email_map = load_employee_email_map(supabase)
    stub_cache = {}

    for template_def in TEMPLATES:
        migrate_template(supabase, gc, template_def, q_map, email_map, stub_cache)

    migrate_atp(supabase, gc, email_map, stub_cache)
    migrate_foreign_material(supabase, gc, fm_question_id, email_map, stub_cache)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
