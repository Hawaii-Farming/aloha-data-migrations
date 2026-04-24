"""
Migrate Food Safety Checklist Logs (Cuke GH Pre/Post)
======================================================
Migrates the legacy fsafe_log_C_gh_pre and fsafe_log_C_gh_post tabs into the
ops_template / ops_template_question / ops_task_tracker / ops_template_result
checklist workflow.

Each historical sheet row is fanned out: one ops_task_tracker per greenhouse
listed in the row's Greenhouse(s) column, with one ops_template_result row per
question per tracker (the same boolean answers are copied across all the
greenhouses signed off in that submission).

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_C_gh_pre:  1109 rows -> cuke_gh_pre_ops template
  - fsafe_log_C_gh_post:  686 rows -> cuke_gh_post_ops template

Usage:
    python migrations/20260401000012_fsafe_cuke_gh_checklist.py

Rerunnable: clears trackers/results scoped to the cuke food_safety_log task
and the two templates' questions, then reinserts.
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
FARM_ID = "cuke"
CATCH_ALL_SITE_ID = "cuke_ghs"

# Template definitions: (template_id, name, sheet_tab, question_columns_in_order)
TEMPLATES = [
    {
        "id": "cuke_gh_pre_ops",
        "name": "GH Pre Ops",
        "tab": "fsafe_log_C_gh_pre",
        "questions": [
            "No Animal Intrusion",
            "Greenhouse Structure Intact",
            "Worker Hygiene is Satisfactory",
            "Worker Health Satisfactory",
            "Carts Clean and Operational",
            "PHI Satisfied",
            "Approved to Harvest",
        ],
    },
    {
        "id": "cuke_gh_post_ops",
        "name": "GH Post Ops",
        "tab": "fsafe_log_C_gh_post",
        "questions": [
            "Harvest Carts Cleaned",
            "Totes Removed",
            "Trash Removed",
            "Pallets and Pallet Jacks Removed",
            "Doors Closed and Locked",
        ],
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


# ---------------------------------------------------------------------------
# Datetime parsing
# ---------------------------------------------------------------------------

def parse_datetime(val):
    """Parse a sheet datetime/date value to ISO timestamp string or None.

    The fsafe sheets store Reported/Verified Time in a mix of formats:
      - '5/3/2024 15:02:00'  (full datetime)
      - '4/4/2023'           (date only -> default to 12:00:00)
      - '14:53:26'           (time only, no date -> None, caller falls back)
    """
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
    """Parse a checklist cell to True/False/None.

    Empty cell -> None (question not answered).
    """
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
# Greenhouse code normalization
# ---------------------------------------------------------------------------

def normalize_gh_codes(raw):
    """Split a Greenhouse(s) cell on '+' and normalize each code.

    Lowercases letters, zero-pads single digits ('2' -> '02'), strips
    whitespace, and dedupes while preserving order.
    """
    if not raw:
        return []
    out = []
    seen = set()
    for piece in str(raw).split("+"):
        code = piece.strip().lower()
        if not code:
            continue
        if code.isdigit() and len(code) == 1:
            code = code.zfill(2)
        if code not in seen:
            seen.add(code)
            out.append(code)
    return out


# ---------------------------------------------------------------------------
# Setup: catch-all site, templates, questions, task link
# ---------------------------------------------------------------------------

def ensure_catch_all_site(supabase):
    """Create the soft-deleted 'Cuke GHs' catch-all site for blank-greenhouse rows."""
    print("\n--- catch-all site ---")
    row = audit({
        "id": CATCH_ALL_SITE_ID,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "name": "Cuke GHs",
        "org_site_category_id": "growing",
        "is_deleted": True,
        "display_order": 999,
    })
    supabase.table("org_site").upsert(row).execute()
    print(f"  Upserted {CATCH_ALL_SITE_ID} (is_deleted=true)")


def load_known_sites(supabase):
    """Return set of cuke-farm org_site IDs for greenhouse FK validation."""
    result = (
        supabase.table("org_site")
        .select("id")
        .eq("farm_id", FARM_ID)
        .execute()
    )
    return {r["id"] for r in result.data}


def upsert_templates(supabase):
    """Upsert the 2 ops_template rows for cuke GH pre/post."""
    rows = []
    for i, t in enumerate(TEMPLATES):
        rows.append(audit({
            "id": t["id"],
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "name": t["name"],
            "org_module_id": "food_safety",
            "description": f"Cuke greenhouse {'pre' if 'pre' in t['id'] else 'post'}-operations checklist (migrated from legacy fsafe sheet)",
            "display_order": i + 1,
        }))
    insert_rows(supabase, "ops_template", rows, upsert=True)


def reseed_questions(supabase):
    """Clear and reinsert ops_template_question rows for these 2 templates.

    Returns: dict of {(template_id, question_text): question_id}
    """
    print("\nClearing existing questions for these templates...")
    for t in TEMPLATES:
        supabase.table("ops_template_question").delete().eq(
            "ops_template_id", t["id"]
        ).execute()
    print("  Cleared")

    rows = []
    for t in TEMPLATES:
        for order, q_text in enumerate(t["questions"], start=1):
            rows.append(audit({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "ops_template_id": t["id"],
                "question_text": q_text,
                "response_type": "boolean",
                "boolean_pass_value": True,
                "is_required": True,
                "include_photo": False,
                "display_order": order,
            }))

    inserted = insert_rows(supabase, "ops_template_question", rows)

    # Build lookup map: (template_id, question_text) -> id
    q_map = {}
    for r in inserted:
        q_map[(r["ops_template_id"], r["question_text"])] = r["id"]
    return q_map


def upsert_task_template_links(supabase):
    """Link both templates to the food_safety_log ops_task."""
    # Clear any existing links for these templates first (UUID PK so we can't upsert by template)
    for t in TEMPLATES:
        supabase.table("ops_task_template").delete().eq(
            "ops_template_id", t["id"]
        ).eq("ops_task_id", TASK_ID).execute()

    rows = []
    for t in TEMPLATES:
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "ops_task_id": TASK_ID,
            "ops_template_id": t["id"],
        }))
    insert_rows(supabase, "ops_task_template", rows)


# ---------------------------------------------------------------------------
# Stub-employee creation for unknown verifier emails
# ---------------------------------------------------------------------------

def load_employee_email_map(supabase):
    """Return {company_email_lower: hr_employee_id}."""
    employees = paginate_select(supabase, "hr_employee", "id, company_email")
    return {
        (r["company_email"] or "").lower(): r["id"]
        for r in employees
        if r.get("company_email")
    }


def create_stub_employee(supabase, email):
    """Create a deleted hr_employee stub for an external verifier email.

    Returns the new employee id.
    """
    local = email.split("@")[0]
    parts = re.split(r"[._-]+", local)
    first = (parts[0] if parts else local).title() or "External"
    last = (parts[1] if len(parts) > 1 else "Verifier").title() or "Verifier"

    emp_id = to_id(f"{last} {first}")
    if not emp_id:
        emp_id = to_id(email.replace("@", "_at_"))

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


# ---------------------------------------------------------------------------
# Tracker + result fan-out
# ---------------------------------------------------------------------------

def clear_existing_data(supabase):
    """Clear trackers and results for these 2 templates so the migration is rerunnable.

    Order: results -> corrective_actions -> trackers (children before parents).
    """
    template_ids = [t["id"] for t in TEMPLATES]

    print("\nClearing existing checklist data for these templates...")

    # Results
    for tid in template_ids:
        supabase.table("ops_template_result").delete().eq("ops_template_id", tid).execute()
    print("  Cleared ops_template_result")

    # Corrective actions (none expected, but tied via ops_template_id)
    for tid in template_ids:
        supabase.table("ops_corrective_action_taken").delete().eq("ops_template_id", tid).execute()
    print("  Cleared ops_corrective_action_taken (if any)")

    # Trackers — scope to cuke food_safety_log task
    supabase.table("ops_task_tracker").delete().eq("ops_task_id", TASK_ID).eq("farm_id", FARM_ID).execute()
    print("  Cleared ops_task_tracker (cuke food_safety_log)")


def migrate_template(supabase, gc, template_def, q_map, known_sites, email_map, stub_cache):
    """Process one template's sheet tab and create trackers + results."""
    tab = template_def["tab"]
    template_id = template_def["id"]
    questions = template_def["questions"]

    print(f"\n=== {template_id} <- {tab} ===")
    ws = gc.open_by_key(FSAFE_SHEET_ID).worksheet(tab)
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    trackers = []
    pending_results = []  # (tracker_index, ops_template_question_id, response_boolean)
    skipped_unknown_codes = []
    skipped_missing_date = 0
    catch_all_used = 0

    for r in records:
        # Resolve start_time
        reported = parse_datetime(r.get("Reported Time"))
        if not reported:
            reported = parse_datetime(r.get("Checked Date"))
        if not reported:
            skipped_missing_date += 1
            continue

        verified_at = parse_datetime(r.get("Verified Time"))

        # Reporter email -> created_by/updated_by audit fields (preserve original)
        reported_by_raw = str(r.get("Reported By", "")).strip()
        reported_by = reported_by_raw.lower() if "@" in reported_by_raw else AUDIT_USER

        # Verifier email -> hr_employee.id (auto-create stub if missing)
        verifier_email = str(r.get("Verified By", "")).strip().lower()
        verified_by_id = None
        if verifier_email and "@" in verifier_email:
            verified_by_id = email_map.get(verifier_email)
            if not verified_by_id:
                if verifier_email in stub_cache:
                    verified_by_id = stub_cache[verifier_email]
                else:
                    new_id = create_stub_employee(supabase, verifier_email)
                    if new_id:
                        stub_cache[verifier_email] = new_id
                        email_map[verifier_email] = new_id
                        verified_by_id = new_id

        # Resolve greenhouse codes -> site IDs
        codes = normalize_gh_codes(r.get("Greenhouse(s)", ""))
        site_ids = []
        if not codes:
            site_ids = [CATCH_ALL_SITE_ID]
            catch_all_used += 1
        else:
            for code in codes:
                if code in known_sites:
                    site_ids.append(code)
                else:
                    skipped_unknown_codes.append(code)
            if not site_ids:
                # All codes unknown — fall back to catch-all rather than dropping
                site_ids = [CATCH_ALL_SITE_ID]
                catch_all_used += 1

        # Build per-site trackers and queue results
        for site_id in site_ids:
            tracker_idx = len(trackers)
            trackers.append({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "site_id": site_id,
                "ops_task_id": TASK_ID,
                "start_time": reported,
                "stop_time": reported,
                "is_completed": True,
                "verified_at": verified_at,
                "verified_by": verified_by_id,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

            for q_text in questions:
                q_id = q_map.get((template_id, q_text))
                if not q_id:
                    continue
                response = parse_bool_cell(r.get(q_text))
                pending_results.append((tracker_idx, q_id, response))

    print(f"  Building {len(trackers)} trackers (catch-all used {catch_all_used} times)")
    if skipped_missing_date:
        print(f"  Skipped {skipped_missing_date} rows: no parseable date")
    if skipped_unknown_codes:
        from collections import Counter
        c = Counter(skipped_unknown_codes)
        print(f"  Unknown greenhouse codes ({len(c)}): {dict(c.most_common(10))}")

    # Insert trackers and capture their UUIDs
    inserted_trackers = insert_rows(supabase, "ops_task_tracker", trackers)
    if len(inserted_trackers) != len(trackers):
        raise RuntimeError(
            f"Tracker insert mismatch: queued {len(trackers)} but got back {len(inserted_trackers)}"
        )

    # Build results with real tracker IDs
    result_rows = []
    for tracker_idx, q_id, response in pending_results:
        tracker = inserted_trackers[tracker_idx]
        result_rows.append({
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "ops_task_tracker_id": tracker["id"],
            "ops_template_id": template_id,
            "ops_template_question_id": q_id,
            "site_id": tracker["site_id"],
            "response_boolean": response,
            "created_by": tracker["created_by"],
            "updated_by": tracker["updated_by"],
        })

    insert_rows(supabase, "ops_template_result", result_rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FSAFE CHECKLIST MIGRATION - Cuke GH Pre/Post")
    print("=" * 60)

    clear_existing_data(supabase)
    ensure_catch_all_site(supabase)
    upsert_templates(supabase)
    q_map = reseed_questions(supabase)
    upsert_task_template_links(supabase)

    known_sites = load_known_sites(supabase)
    email_map = load_employee_email_map(supabase)
    stub_cache = {}

    for template_def in TEMPLATES:
        migrate_template(supabase, gc, template_def, q_map, known_sites, email_map, stub_cache)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
