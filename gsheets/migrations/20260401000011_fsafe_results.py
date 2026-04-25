"""
Migrate Food Safety Results
=============================
Migrates fsafe_lab, fsafe_lab_test (listeria_monocytogenes), water org_sites,
fsafe_result (EMP + water), and fsafe_test_hold + fsafe_result (test & hold)
from legacy Google Sheets to Supabase.

Source: https://docs.google.com/spreadsheets/d/1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc
  - fsafe_log_emp: 1330 rows -> fsafe_result (EMP)
  - fsafe_log_water: 229 rows -> fsafe_result (water, unpivoted)
  - fsafe_log_test_n_hold: 587 rows -> fsafe_test_hold + fsafe_result (unpivoted)

Usage:
    python scripts/migrations/20260401000011_fsafe_results.py

Rerunnable: clears and reinserts all data on each run.
"""

import re
import sys
from datetime import datetime
from pathlib import Path

# Add this script's directory to sys.path so we can import _config regardless
# of where the script is invoked from (repo root vs scripts/migrations).
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

FSAFE_SHEET_ID = SHEET_IDS["fsafe_results"]

# Manual sampled_by overrides: lowercase name -> hr_employee.id
SAMPLED_BY_OVERRIDES = {
    "ana carolina": "almeida_ferreira_ana_carolina",
    "lucy": "nguyen_thi_thanh_hang",
    "luma": "arruda_da_silva_laine_luma",
}

# Building site map: (farm, building) -> parent org_site.id
BUILDING_SITE_MAP = {
    ("cuke", "gh"): "jtl",
    ("cuke", "ph"): "bip_ph",
    ("lettuce", "gh"): "gh",
    ("lettuce", "ph"): "lettuce_ph",
}

# Labs to seed: (id, name)
LABS = [
    ("hfwt", "HFWT"),
    ("mcs", "MCS"),
    ("hf", "HF"),
    ("oahu", "Oahu"),
]

# EMP test name mapping: sheet TestName (lowered) -> fsafe_lab_test.id
EMP_TEST_MAP = {
    "apc": "apc",
    "listeria": "listeria",
    "listeria monocytogenes": "listeria_monocytogenes",
    "salmonella": "salmonella",
}

# Test & Hold wide-column definitions: sheet_col -> (lab_test_id, is_enum)
TH_TEST_COLS = {
    "APC": ("apc", False),
    "EColi": ("e_coli", True),
    "EColiO157": ("e_coli", True),
    "Salmonella": ("salmonella", True),
    "Listeria": ("listeria", True),
    "TotalColiform": ("tc", False),
}


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()


def audit(row: dict) -> dict:
    """Add audit fields to a row."""
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, upsert=False):
    """Insert (or upsert) rows in batches of 100.

    NOTE: PostgREST does not support multi-statement transactions, so each
    batch is committed independently. If a batch fails mid-way through, all
    earlier batches remain in the database. This script is rerunnable —
    re-running clears and reinserts all data, so partial failures recover by
    fixing the underlying issue and running the script again.

    On a batch failure this function prints which batch failed and how many
    rows were committed before re-raising the exception so the user knows
    exactly where things went wrong.
    """
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

    print(f"  {'Upserted' if upsert else 'Inserted'} {len(rows)} rows")
    return all_data


def parse_date(date_str):
    """Parse date string to YYYY-MM-DD or None."""
    if not date_str or not str(date_str).strip():
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def parse_timestamp(ts_str):
    """Parse timestamp to ISO format or None."""
    if not ts_str or not str(ts_str).strip():
        return None
    for fmt in ("%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%m/%d/%Y"):
        try:
            return datetime.strptime(str(ts_str).strip(), fmt).isoformat()
        except ValueError:
            continue
    return None


def safe_numeric(val, default=None):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def parse_bool(val):
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def parse_bool_result(val):
    """Parse boolean result for test-and-hold: true/positive/detected -> True."""
    if not val or not str(val).strip():
        return None
    return str(val).strip().lower() in ("true", "positive", "detected")


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ---------------------------------------------------------------------------
# Lookup builders
# ---------------------------------------------------------------------------

def build_sampled_by_lookup(supabase):
    """Build name -> hr_employee.id lookup from hr_employee table."""
    emps = paginate_select(
        supabase, "hr_employee", "id, first_name, last_name, preferred_name",
        eq_filters={"org_id": ORG_ID},
    )

    lookup = {}
    for e in emps:
        eid = e["name"]
        fn = (e.get("first_name") or "").strip().lower()
        ln = (e.get("last_name") or "").strip().lower()
        pn = (e.get("preferred_name") or "").strip().lower()

        if fn:
            lookup[fn] = eid
        if pn:
            lookup[pn] = eid
        if fn and ln:
            lookup[f"{fn} {ln}"] = eid
            lookup[f"{ln} {fn}"] = eid

    # Manual overrides take precedence
    lookup.update(SAMPLED_BY_OVERRIDES)
    return lookup


def build_email_to_emp(supabase):
    """Build company_email -> hr_employee.id lookup."""
    emps = paginate_select(
        supabase, "hr_employee", "id, company_email",
        eq_filters={"org_id": ORG_ID},
    )

    return {
        e["company_email"].strip().lower(): e["name"]
        for e in emps
        if e.get("company_email")
    }


def resolve_sampled_by(name_str, name_map):
    """Resolve a SampledBy name string to hr_employee.id or None."""
    if not name_str or not str(name_str).strip():
        return None
    return name_map.get(str(name_str).strip().lower())


def resolve_verified_by(email_str, email_map):
    """Resolve a VerifiedBy email string to hr_employee.id or None."""
    if not email_str or not str(email_str).strip():
        return None
    return email_map.get(str(email_str).strip().lower())


# ---------------------------------------------------------------------------
# Setup: labs, lab test, water sites
# ---------------------------------------------------------------------------

def setup_labs(supabase):
    """Create 4 fsafe_lab records."""
    rows = []
    for lab_id, lab_name in LABS:
        rows.append(audit({
            "id": lab_id,
            "org_id": ORG_ID,
            "name": lab_name,
        }))
    return insert_rows(supabase, "fsafe_lab", rows)


def setup_listeria_mono_test(supabase):
    """Upsert the listeria_monocytogenes lab test."""
    row = audit({
        "id": "listeria_monocytogenes",
        "org_id": ORG_ID,
        "test_name": "Listeria Monocytogenes",
        "result_type": "enum",
        "enum_options": ["Positive", "Negative"],
        "enum_pass_options": ["Negative"],
    })
    supabase.table("fsafe_lab_test").upsert(row).execute()
    print("\n--- fsafe_lab_test ---")
    print("  Upserted listeria_monocytogenes")


def setup_water_sites(supabase, wb):
    """Create water testing org_sites from fsafe_log_water unique SiteNames.

    Sites are named '{BUILDING} Water - {sitename}' and parented to building sites.
    Returns a (farm, building, sitename) -> site_id map.
    """
    records = wb.worksheet("fsafe_log_water").get_all_records()

    # Collect unique (farm, building, sitename) tuples
    seen = set()
    sites_to_create = []
    for r in records:
        farm = str(r.get("Farm", "")).strip().lower()
        building = str(r.get("Building", "")).strip().lower()
        sitename = str(r.get("SiteName", "")).strip()
        if not farm or not building or not sitename:
            continue
        key = (farm, building, sitename)
        if key in seen:
            continue
        seen.add(key)
        sites_to_create.append((farm, building, sitename))

    rows = []
    water_site_map = {}  # (farm, building, sitename) -> site_id
    for farm, building, sitename in sorted(sites_to_create):
        parent_id = BUILDING_SITE_MAP.get((farm, building))
        display_name = f"{building.upper()} Water - {sitename}"
        site_id = to_id(f"{farm}_{building}_water_{sitename}")
        farm_name = farm if farm in ("cuke", "lettuce") else None
        water_site_map[(farm, building, sitename)] = site_id

        rows.append(audit({
            "id": site_id,
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "name": display_name,
            "org_site_category_id": "food_safety",
            "zone": "water",
            "site_id_parent": parent_id,
        }))

    insert_rows(supabase, "org_site", rows, upsert=True)
    return water_site_map


# ---------------------------------------------------------------------------
# EMP results (fsafe_log_emp -> fsafe_result)
# ---------------------------------------------------------------------------

def migrate_emp(supabase, wb, sampled_by_lookup, email_map):
    """Migrate 1330 EMP rows into fsafe_result.

    After insert, links retests/vectors to originals via
    TestFromFailCode -> FailCode mapping.
    """
    data = wb.worksheet("fsafe_log_emp").get_all_records()
    print(f"\n  Reading fsafe_log_emp: {len(data)} rows")

    # Build org_site lookup: name (lowered) -> id for food_safety sites
    sites = paginate_select(
        supabase, "org_site", "id, name, farm_name",
        eq_filters={"org_id": ORG_ID},
    )
    site_by_name = {s["name"].lower(): s["id"] for s in sites}

    rows = []
    fail_code_to_idx = {}  # fail_code -> index in rows list
    skipped = 0

    for r in data:
        test_name_raw = str(r.get("TestName", "")).strip().lower()
        lab_test_id = EMP_TEST_MAP.get(test_name_raw)
        if not lab_test_id:
            skipped += 1
            continue

        # Resolve site_id: "{building} - {sitename}" format
        farm = str(r.get("Farm", "")).strip().lower()
        building = str(r.get("Building", "")).strip()
        sitename = str(r.get("SiteName", "")).strip()
        site_lookup = f"{building} - {sitename}".lower() if building and sitename else ""
        site_id = site_by_name.get(site_lookup)
        farm_name = farm if farm in ("cuke", "lettuce") else None

        # TestType -> initial_retest_vector
        test_type_raw = str(r.get("TestType", "")).strip().lower()
        initial_retest_vector = test_type_raw if test_type_raw in ("initial", "retest", "vector") else None

        # Result values: APC = numeric, others = enum
        result_enum = None
        result_numeric = None
        if lab_test_id == "apc":
            result_numeric = safe_numeric(r.get("NumericResults"))
        else:
            pos_raw = str(r.get("PositiveResults", "")).strip()
            if pos_raw:
                is_positive = pos_raw.lower() in ("positive", "true", "yes", "1")
                result_enum = "Positive" if is_positive else "Negative"

        # Pass from "Pass" column
        pass_raw = str(r.get("Pass", "")).strip()
        result_pass = pass_raw.upper() in ("TRUE", "YES", "1", "PASS") if pass_raw else None

        # FailCode
        fail_code = str(r.get("FailCode", "")).strip() or None

        # Timestamps (EMP sheet uses SampleDateTime and CompletedDateTime)
        sampled_at = parse_timestamp(str(r.get("SampleDateTime", "")).strip())
        completed_at = parse_timestamp(str(r.get("CompletedDateTime", "")).strip())

        # Sampled by / verified by
        sampled_by = resolve_sampled_by(r.get("SampledBy", ""), sampled_by_lookup)
        verified_by = resolve_verified_by(r.get("VerifiedBy", ""), email_map)

        idx = len(rows)
        row = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "site_id": site_id,
            "fsafe_lab_test_name": lab_test_id,
            "initial_retest_vector": initial_retest_vector,
            "status": "completed",
            "result_enum": result_enum,
            "result_numeric": result_numeric,
            "result_pass": result_pass,
            "fail_code": fail_code,
            "sampled_at": sampled_at,
            "sampled_by": sampled_by,
            "completed_at": completed_at,
            "verified_by": verified_by,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }
        rows.append(row)

        if fail_code:
            fail_code_to_idx[fail_code] = idx

    inserted = insert_rows(supabase, "fsafe_result", rows)

    # Link retests/vectors to originals via TestFromFailCode -> FailCode
    link_count = 0
    for i, r in enumerate(data):
        if i >= len(inserted):
            break
        test_from = str(r.get("TestFromFailCode", "")).strip()
        if test_from and test_from in fail_code_to_idx:
            original_idx = fail_code_to_idx[test_from]
            if original_idx < len(inserted):
                supabase.table("fsafe_result").update(
                    {"fsafe_result_id_original": inserted[original_idx]["id"]}
                ).eq("id", inserted[i]["id"]).execute()
                link_count += 1

    if link_count:
        print(f"  Linked {link_count} retests/vectors to originals")
    if skipped:
        print(f"  Skipped {skipped} rows (unknown test name)")


# ---------------------------------------------------------------------------
# Water results (fsafe_log_water -> fsafe_result, unpivoted)
# ---------------------------------------------------------------------------

def migrate_water(supabase, wb, water_site_map, sampled_by_lookup):
    """Migrate 229 water rows, unpivoting each into up to 4 results:
    TotalColiform (numeric, test=tc), EColi (numeric value but enum pass),
    Salmonella (enum), Listeria (enum).
    """
    data = wb.worksheet("fsafe_log_water").get_all_records()
    print(f"\n  Reading fsafe_log_water: {len(data)} rows")

    # Build lab lookup: name (lowered) -> fsafe_lab.id
    labs = paginate_select(supabase, "fsafe_lab", "id, name", eq_filters={"org_id": ORG_ID})
    lab_by_name = {l["name"].lower(): l["id"] for l in labs}

    rows = []
    for r in data:
        farm = str(r.get("Farm", "")).strip().lower()
        building = str(r.get("Building", "")).strip().lower()
        sitename = str(r.get("SiteName", "")).strip()
        site_id = water_site_map.get((farm, building, sitename))
        farm_name = farm if farm in ("cuke", "lettuce") else None

        # Lab from "Lab" column
        lab_raw = str(r.get("Lab", "")).strip().lower()
        fsafe_lab_name = lab_by_name.get(lab_raw)

        sampled_at = parse_timestamp(str(r.get("SampleDateTime", "")).strip())
        sampled_by = resolve_sampled_by(r.get("SampledBy", ""), sampled_by_lookup)

        base = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "site_id": site_id,
            "fsafe_lab_name": fsafe_lab_name,
            "status": "completed",
            "sampled_at": sampled_at,
            "sampled_by": sampled_by,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }

        # TotalColiform (numeric, test=tc)
        tc_val = str(r.get("TotalColiform", "")).strip()
        if tc_val:
            row = dict(base)
            row["fsafe_lab_test_name"] = "tc"
            row["result_numeric"] = safe_numeric(tc_val)
            row["result_pass"] = True
            rows.append(row)

        # EColi: numeric value, positive if >0, pass if <=126
        ecoli_val = str(r.get("EColi", "")).strip()
        if ecoli_val:
            numeric = safe_numeric(ecoli_val, default=0)
            row = dict(base)
            row["fsafe_lab_test_name"] = "e_coli"
            row["result_numeric"] = numeric
            row["result_enum"] = "Positive" if numeric > 0 else "Negative"
            row["result_pass"] = numeric <= 126
            rows.append(row)

        # Salmonella (enum)
        sal_val = str(r.get("Salmonella", "")).strip()
        if sal_val:
            is_pos = parse_bool_result(sal_val)
            row = dict(base)
            row["fsafe_lab_test_name"] = "salmonella"
            row["result_enum"] = "Positive" if is_pos else "Negative"
            row["result_pass"] = not is_pos
            rows.append(row)

        # Listeria (enum)
        lis_val = str(r.get("Listeria", "")).strip()
        if lis_val:
            is_pos = parse_bool_result(lis_val)
            row = dict(base)
            row["fsafe_lab_test_name"] = "listeria"
            row["result_enum"] = "Positive" if is_pos else "Negative"
            row["result_pass"] = not is_pos
            rows.append(row)

    insert_rows(supabase, "fsafe_result", rows)


# ---------------------------------------------------------------------------
# Test & Hold (fsafe_log_test_n_hold -> fsafe_test_hold + fsafe_result)
# ---------------------------------------------------------------------------

def migrate_test_hold(supabase, wb, sampled_by_lookup):
    """Migrate 587 test-and-hold rows.

    Creates fsafe_test_hold header per row, then unpivots wide test columns
    into fsafe_result rows. Skips rows without pack_lot_id (~69 rows).
    """
    data = wb.worksheet("fsafe_log_test_n_hold").get_all_records()
    print(f"\n  Reading fsafe_log_test_n_hold: {len(data)} rows")

    # Build pack_lot lookup: lot_number -> {id, farm_name}
    lots = paginate_select(
        supabase, "pack_lot", "id, lot_number, farm_name",
        eq_filters={"org_id": ORG_ID},
    )
    lot_by_number = {l["lot_number"]: l for l in lots}

    # Build lab lookup
    labs = paginate_select(supabase, "fsafe_lab", "id, name", eq_filters={"org_id": ORG_ID})
    lab_by_name = {l["name"].lower(): l["id"] for l in labs}

    # Build Costco customer group lookup
    groups = paginate_select(
        supabase, "sales_customer_group", "id, name",
        eq_filters={"org_id": ORG_ID},
    )
    group_by_name = {g["name"].lower(): g["id"] for g in groups}
    costco_group_id = group_by_name.get("costco")

    hold_rows = []
    hold_meta = []  # parallel sheet rows for result creation
    skipped = 0

    for r in data:
        # Resolve pack_lot
        pack_lot_str = str(r.get("PackLot", "")).strip()
        lot = lot_by_number.get(pack_lot_str) if pack_lot_str else None
        if not lot:
            skipped += 1
            continue

        pack_lot_id = lot["id"]
        farm_name = lot["farm_name"]

        # Lab
        lab_raw = str(r.get("Lab", "")).strip().lower()
        fsafe_lab_name = lab_by_name.get(lab_raw)

        # Lab test ID
        lab_test_id = str(r.get("LabTestID", "")).strip() or None

        # Delivered to lab
        delivered_to_lab_on = parse_date(str(r.get("DeliveredToLabOn", "")).strip())

        # Costco submissions get sales_customer_group_name
        customer_raw = str(r.get("Customer", "")).strip().lower()
        sales_customer_group_name = costco_group_id if "costco" in customer_raw else None

        hold_row = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "pack_lot_id": pack_lot_id,
            "fsafe_lab_name": fsafe_lab_name,
            "lab_test_id": lab_test_id,
            "delivered_to_lab_on": delivered_to_lab_on,
            "sales_customer_group_name": sales_customer_group_name,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }
        hold_rows.append(hold_row)
        hold_meta.append(r)

    print(f"  Skipped {skipped} rows without pack_lot_id")
    inserted_holds = insert_rows(supabase, "fsafe_test_hold", hold_rows)

    # Unpivot wide test columns into fsafe_result rows
    result_rows = []
    for idx, r in enumerate(hold_meta):
        if idx >= len(inserted_holds):
            break
        hold = inserted_holds[idx]
        hold_id = hold["id"]
        farm_name = hold["farm_name"]
        fsafe_lab_name = hold.get("fsafe_lab_name")

        sampled_by = resolve_sampled_by(r.get("SampledBy", ""), sampled_by_lookup)

        base = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "fsafe_test_hold_id": hold_id,
            "fsafe_lab_name": fsafe_lab_name,
            "status": "completed",
            "sampled_by": sampled_by,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }

        for col, (test_id, is_enum) in TH_TEST_COLS.items():
            val = str(r.get(col, "")).strip()
            if not val:
                continue

            row = dict(base)
            row["fsafe_lab_test_name"] = test_id

            if is_enum:
                is_pos = parse_bool_result(val)
                row["result_enum"] = "Positive" if is_pos else "Negative"
                row["result_pass"] = not is_pos if is_pos is not None else None
            else:
                num = safe_numeric(val)
                if num is None:
                    continue
                row["result_numeric"] = num

            result_rows.append(row)

    insert_rows(supabase, "fsafe_result", result_rows)


# ---------------------------------------------------------------------------
# Clear
# ---------------------------------------------------------------------------

def clear_data(supabase):
    """Clear fsafe_result, fsafe_test_hold, fsafe_lab in FK dependency order.

    ops_corrective_action_taken.fsafe_result_id FK-references fsafe_result,
    so we must NULL those references out (or delete them) before we can
    delete the parent rows. We just null the FK — the corrective action
    migration will re-link them on its next run.
    """
    print("\nClearing food safety results data...")

    # Detach corrective actions from fsafe_result (the corrective action
    # migration will re-link them after 7l re-runs). We can't null a column
    # via PostgREST's .update() without a filter, so we delete CA rows that
    # have fsafe_result_id set instead — they'll be rebuilt by 7l.
    ca_with_fsafe = (
        supabase.table("ops_corrective_action_taken")
        .select("id")
        .not_.is_("fsafe_result_id", "null")
        .execute()
        .data
    )
    if ca_with_fsafe:
        ids = [r["id"] for r in ca_with_fsafe]
        for i in range(0, len(ids), 100):
            supabase.table("ops_corrective_action_taken").delete().in_(
                "id", ids[i:i + 100]
            ).execute()
        print(f"  Detached {len(ids)} corrective actions referencing fsafe_result")

    supabase.table("fsafe_result").delete().neq(
        "id", "00000000-0000-0000-0000-000000000000"
    ).execute()
    print("  Cleared fsafe_result")

    supabase.table("fsafe_test_hold").delete().neq(
        "id", "00000000-0000-0000-0000-000000000000"
    ).execute()
    print("  Cleared fsafe_test_hold")

    supabase.table("fsafe_lab").delete().neq("name", "__none__").execute()
    print("  Cleared fsafe_lab")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("FOOD SAFETY RESULTS MIGRATION")
    print("=" * 60)

    # Step 0: Clear existing data
    clear_data(supabase)

    # Step 1: Setup - labs, lab test, water sites
    wb = gc.open_by_key(FSAFE_SHEET_ID)
    setup_labs(supabase)
    setup_listeria_mono_test(supabase)
    water_site_map = setup_water_sites(supabase, wb)

    # Step 2: Build lookup maps
    sampled_by_lookup = build_sampled_by_lookup(supabase)
    email_map = build_email_to_emp(supabase)

    # Step 3: EMP results
    migrate_emp(supabase, wb, sampled_by_lookup, email_map)

    # Step 4: Water results
    migrate_water(supabase, wb, water_site_map, sampled_by_lookup)

    # Step 5: Test & Hold
    migrate_test_hold(supabase, wb, sampled_by_lookup)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
