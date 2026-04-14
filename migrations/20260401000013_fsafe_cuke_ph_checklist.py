"""
Migrate Food Safety Checklist Logs (Cuke PH Pre/Post + Foreign Material)
==========================================================================
Migrates fsafe_log_C_ph_pre and fsafe_log_C_ph_post tabs into the
checklist workflow plus an org-scoped Foreign Material Event template.

ATP swab readings from PH Post are routed to fsafe_result (not
ops_template_result) per the workflow review — they're test results, not
checklist responses. The ATP partial index on ops_template_result was
removed from the schema accordingly.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_C_ph_pre:  ~1049 rows -> cuke_ph_pre_ops template
  - fsafe_log_C_ph_post: ~1067 rows -> cuke_ph_post_ops template
  - PH Post ATP columns -> ~2300 fsafe_result rows
  - Foreign Material Event template (org-scoped, no historical results)

Numeric pass ranges (min/max) for the 5 numeric questions in PH Post +
2 in PH Pre come from the fsafe_test_name lookup tab. Truck Temperature
has no defined range in the lookup (kept as a non-required numeric field).

Cleaner Dilution Concentration is migrated as numeric (per current spec)
but a soft-deleted legacy boolean question is also created on the PH Post
template to preserve the 688 historical TRUE/FALSE values that pre-date
the schema change.

Usage:
    python migrations/20260401000013_fsafe_cuke_ph_checklist.py

Rerunnable: clears trackers/results/atp results for cuke food_safety_log
at the bip_ph site, then reinserts.
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
FARM_ID = "cuke"
SITE_ID = "bip_ph"  # Cuke packhouse parent site
ATP_LAB_ID = "hf"   # Existing Hawaii Farming internal lab
ATP_TEST_ID = "atp_rlu"

# ---------------------------------------------------------------------------
# Question definitions
# ---------------------------------------------------------------------------
# Question rows: (sheet_column, response_type, kwargs)
# kwargs may include: is_required, boolean_pass_value, minimum_value,
#                     maximum_value, enum_options, enum_pass_options,
#                     include_photo, is_deleted

PH_PRE_QUESTIONS = [
    # Restroom block (drops off mid-history -> not required)
    ("Toilets Works",                       "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Toilets Clean",                       "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Toilet Papers Stocked",               "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Paper Towels Restocked",              "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Soap Dispensers Refilled",            "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Trash Bins Emptied",                  "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Floor Drains Cleared",                "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Sinks Cleaned",                       "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Floors Swept and Mopped",             "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Mirrors Cleaned",                     "boolean", {"boolean_pass_value": True, "is_required": False}),
    # Core packhouse block (always filled)
    ("No Evidence of Pests",                "boolean", {"boolean_pass_value": True}),
    ("No Structural Issues",                "boolean", {"boolean_pass_value": True}),
    ("Doors Closed and Sealed",             "boolean", {"boolean_pass_value": True}),
    ("Packing Scales Working",              "boolean", {"boolean_pass_value": True}),
    ("Packing Tables Clean",                "boolean", {"boolean_pass_value": True}),
    ("Packing Room Clean",                  "boolean", {"boolean_pass_value": True}),
    ("Coolers Clean",                       "boolean", {"boolean_pass_value": True}),
    ("Boxes Clean and Stored on Pallets",   "boolean", {"boolean_pass_value": True}),
    ("Changing and Break Areas Clean",      "boolean", {"boolean_pass_value": True}),
    ("No Hygiene Issues",                   "boolean", {"boolean_pass_value": True}),
    ("No Worker Health Issues",             "boolean", {"boolean_pass_value": True}),
    ("PPE Worn and No Jewelry",             "boolean", {"boolean_pass_value": True}),
    ("Staff Washing Hands",                 "boolean", {"boolean_pass_value": True}),
    # Block added later (~70% fill, not required)
    ("Harvest Totes Clean and off the Ground", "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Proper Use of Non-Food Totes",        "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Packhouse Sinks Clean",               "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("PackHouse Drain Clean",               "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Tote Sanitizing Stations Clean",      "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Chemical Storage Area Clean",         "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Packing Storage Clean",               "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Truck Bed Clean and Pest Free",       "boolean", {"boolean_pass_value": True, "is_required": False}),
    # Numeric measurements
    ("Truck Temperature",                   "numeric", {"is_required": False}),
    ("Cooler 1 Temperature",                "numeric", {"minimum_value": 45, "maximum_value": 60}),
    ("Cooler 2 Temperature",                "numeric", {"minimum_value": 45, "maximum_value": 60}),
]

PH_POST_QUESTIONS = [
    ("Used Totes Cleaned",                          "boolean", {"boolean_pass_value": True}),
    ("Packing Tables Cleaned",                      "boolean", {"boolean_pass_value": True}),
    ("Coolers Cleaned",                             "boolean", {"boolean_pass_value": True}),
    ("Packing Floor Cleaned",                       "boolean", {"boolean_pass_value": True}),
    ("Finished Product On Pallets and Refrigerated","boolean", {"boolean_pass_value": True}),
    ("Packing Scales Cleaned",                      "boolean", {"boolean_pass_value": True}),
    ("Packaging On Pallets and Stored",             "boolean", {"boolean_pass_value": True}),
    ("Hand Wash Sink Cleaned",                      "boolean", {"boolean_pass_value": True}),
    ("Restrooms Cleaned",                           "boolean", {"boolean_pass_value": True}),
    ("Test Strip Is Not Expired",                   "boolean", {"boolean_pass_value": True, "is_required": False}),
    ("Totes Washed",                                "boolean", {"boolean_pass_value": True, "is_required": False}),
    # Numeric measurements with ranges from fsafe_test_name
    ("Tote Wash Chlorine Concentration",            "numeric", {"minimum_value": 50,  "maximum_value": 200}),
    ("Cleaner Dilution Concentration",              "numeric", {"minimum_value": 4,   "maximum_value": 8}),
    ("Equipment Sanitizer Concentration",           "numeric", {"minimum_value": 200, "maximum_value": 400}),
    ("Cooler 1 Temperature",                        "numeric", {"minimum_value": 45,  "maximum_value": 60}),
    ("Cooler 2 Temperature",                        "numeric", {"minimum_value": 45,  "maximum_value": 60}),
    # Soft-deleted legacy question — preserves 688 historical TRUE/FALSE values
    # that existed before this column was changed to numeric.
    ("Cleaner Dilution Concentration (legacy boolean)", "boolean", {
        "boolean_pass_value": True, "is_required": False, "is_deleted": True,
    }),
]

TEMPLATES = [
    {
        "id": "cuke_ph_pre_ops",
        "name": "PH Pre Ops",
        "tab": "fsafe_log_C_ph_pre",
        "questions": PH_PRE_QUESTIONS,
        "farm_id": FARM_ID,
        "description": "Cuke packhouse pre-operations checklist (migrated from legacy fsafe sheet)",
    },
    {
        "id": "cuke_ph_post_ops",
        "name": "PH Post Ops",
        "tab": "fsafe_log_C_ph_post",
        "questions": PH_POST_QUESTIONS,
        "farm_id": FARM_ID,
        "description": "Cuke packhouse post-operations cleanup checklist (migrated from legacy fsafe sheet)",
    },
]

# NOTE: The org-scoped foreign_material_event template is created by the
# fsafe lookup migration (20260401000008_fsafe.py). Cuke PH has no historical
# foreign material events, so this script doesn't touch that template.

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
    """Parse a numeric cell to float, dropping non-numeric (e.g. legacy TRUE/FALSE)."""
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
# ATP fuzzy site matching
# ---------------------------------------------------------------------------

def normalize_site_name(s):
    """Lowercase, strip 'PH - ' / 'GH - ' prefix, collapse whitespace and #."""
    s = str(s).strip().lower()
    s = re.sub(r"^(ph|gh)\s*-\s*", "", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s*#\s*", "#", s)
    return s


def build_site_matcher(supabase):
    """Load existing cuke food_safety sites and return a matcher function."""
    result = (
        supabase.table("org_site")
        .select("id,name,site_id_parent")
        .eq("farm_id", FARM_ID)
        .eq("org_site_category_id", "food_safety")
        .execute()
    )
    sites = result.data
    # Index by normalized name -> list of (id, name, prefer_score)
    # prefer_score: fcs > generic > leg > bottom_shelf — so the same number prefers food contact
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

        best = None  # (score, prefer, id, matched_name)
        for sid, sname, snorm, pref in candidates:
            ratio = SequenceMatcher(None, target, snorm).ratio()
            # Boost containment matches: if normalized target is fully contained in snorm, bump
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
    """Create a new cuke food_safety site for an unmatched ATP swab name."""
    new_id = "cuke_ph_" + to_id(raw_name)
    display_name = "PH - " + str(raw_name).strip()
    row = audit({
        "id": new_id,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
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
    # Add to candidate list so future fuzzy lookups for casing variants resolve here
    candidates.append((new_id, display_name, normalize_site_name(display_name), 2))
    return new_id


# ---------------------------------------------------------------------------
# fsafe_lab_test for ATP RLU
# ---------------------------------------------------------------------------

def ensure_atp_lab_test(supabase):
    print("\n--- fsafe_lab_test (atp_rlu) ---")
    row = audit({
        "id": ATP_TEST_ID,
        "org_id": ORG_ID,
        "farm_id": None,
        "test_name": "ATP RLU",
        "test_methods": [],
        "test_description": "ATP swab — Relative Light Units. Used to verify cleaning of food contact surfaces.",
        "result_type": "numeric",
        "minimum_value": 0,
        "maximum_value": 30,
        "atp_site_count": 3,
        "required_retests": 0,
        "required_vector_tests": 0,
    })
    supabase.table("fsafe_lab_test").upsert(row).execute()
    print("  Upserted atp_rlu")


# ---------------------------------------------------------------------------
# Setup: templates, questions, task links
# ---------------------------------------------------------------------------

def upsert_templates(supabase):
    rows = []
    next_order = 10  # leave room for cuke_gh_pre/post at 1-2
    for t in TEMPLATES:
        rows.append(audit({
            "id": t["id"],
            "org_id": ORG_ID,
            "farm_id": t["farm_id"],
            "name": t["name"],
            "org_module_id": "food_safety",
            "description": t["description"],
            "display_order": next_order,
        }))
        next_order += 1
    insert_rows(supabase, "ops_template", rows, upsert=True)


def reseed_questions(supabase):
    """Returns: dict of {(template_id, question_text): question_id}"""
    print("\nClearing existing questions for these templates...")
    template_ids = [t["id"] for t in TEMPLATES]
    for tid in template_ids:
        supabase.table("ops_template_question").delete().eq("ops_template_id", tid).execute()
    print("  Cleared")

    rows = []
    for t in TEMPLATES:
        for order, (q_text, rtype, kw) in enumerate(t["questions"], start=1):
            row = {
                "org_id": ORG_ID,
                "farm_id": t["farm_id"],
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
            }
            rows.append(audit(row))

    inserted = insert_rows(supabase, "ops_template_question", rows)
    q_map = {}
    for r in inserted:
        q_map[(r["ops_template_id"], r["question_text"])] = r["id"]
    return q_map


def upsert_task_template_links(supabase):
    """Link the 2 farm templates to food_safety_log."""
    template_ids = [t["id"] for t in TEMPLATES]
    for tid in template_ids:
        supabase.table("ops_task_template").delete().eq(
            "ops_template_id", tid
        ).eq("ops_task_id", TASK_ID).execute()

    rows = []
    for t in TEMPLATES:
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_id": t["farm_id"],
            "ops_task_id": TASK_ID,
            "ops_template_id": t["id"],
        }))
    insert_rows(supabase, "ops_task_template", rows)


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    template_ids = [t["id"] for t in TEMPLATES]
    print("\nClearing existing checklist data for these templates...")

    # Capture tracker IDs from our own results before deleting, so we can
    # delete exactly those trackers (avoids touching glass/calibration trackers
    # at the same site).
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

    # Clear cuke PH template results
    for tid in template_ids:
        supabase.table("ops_template_result").delete().eq("ops_template_id", tid).execute()
    print("  Cleared ops_template_result")

    for tid in template_ids:
        supabase.table("ops_corrective_action_taken").delete().eq("ops_template_id", tid).execute()
    print("  Cleared ops_corrective_action_taken")

    # Delete the captured trackers in chunks
    if tracker_ids_to_delete:
        ids = list(tracker_ids_to_delete)
        for i in range(0, len(ids), 100):
            chunk = ids[i:i + 100]
            supabase.table("ops_task_tracker").delete().in_("id", chunk).execute()
        print(f"  Cleared {len(ids)} cuke PH trackers")

    # ATP fsafe_result rows
    supabase.table("fsafe_result").delete().eq("fsafe_lab_test_id", ATP_TEST_ID).eq("farm_id", FARM_ID).execute()
    print(f"  Cleared fsafe_result (atp_rlu, cuke)")


# ---------------------------------------------------------------------------
# Per-template migration
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
    pending_results = []  # (tracker_index, ops_template_question_id, response_type, raw_value)
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
            "farm_id": FARM_ID,
            "site_id": SITE_ID,
            "ops_task_id": TASK_ID,
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
            # Special case: legacy boolean column reads from the same sheet column
            # as the active numeric question
            if q_text.endswith("(legacy boolean)"):
                source_col = q_text.replace(" (legacy boolean)", "")
                pending_results.append((tracker_idx, q_id, "boolean", r.get(source_col)))
            else:
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
            "farm_id": FARM_ID,
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
# ATP migration to fsafe_result
# ---------------------------------------------------------------------------

def migrate_atp(supabase, gc, email_map, stub_cache):
    print("\n=== ATP swabs -> fsafe_result ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet("fsafe_log_C_ph_post")
    records = ws.get_all_records()

    matcher, candidates = build_site_matcher(supabase)
    auto_created = {}  # raw_name -> site_id (caches creation)

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

            # Resolve site_id
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
                "farm_id": FARM_ID,
                "site_id": site_id,
                "fsafe_lab_id": ATP_LAB_ID,
                "fsafe_lab_test_id": ATP_TEST_ID,
                "result_numeric": value,
                "result_pass": result_pass,
                "status": "completed",
                "initial_retest_vector": "initial",
                "sampled_at": sampled_at,
                "sampled_by": verified_by_id,  # we don't have a separate sampler in the sheet
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
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE CHECKLIST MIGRATION - Cuke PH Pre/Post + Foreign Material")
    print("=" * 60)

    clear_existing_data(supabase)
    ensure_atp_lab_test(supabase)
    upsert_templates(supabase)
    q_map = reseed_questions(supabase)
    upsert_task_template_links(supabase)

    email_map = load_employee_email_map(supabase)
    stub_cache = {}

    for template_def in TEMPLATES:
        migrate_template(supabase, gc, template_def, q_map, email_map, stub_cache)

    migrate_atp(supabase, gc, email_map, stub_cache)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
