"""
Migrate Cuke Harvest Data
=========================
Migrates grow_C_harvest into grow_harvest_weight with one row per
weigh-in record. Each sheet row is a single pallet weigh-in tied to
a seed batch via SeedingCycle + variety suffix.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_C_harvest: ~4,872 rows -> ~4,872 grow_harvest_weight rows

Seed batch linkage:
  - Production harvests: batch_code = SeedingCycle + "P"
  - Trial harvests:      batch_code = SeedingCycle + "T" (or "T2", "T3", "T4")

Grade mapping (sheet grade -> grow_grade.id):
  1 -> on_grade
  2 -> off_grade

Container mapping (variety + grade -> grow_harvest_container.id):
  K1 -> pallet_k1     K2 -> pallet_k2
  E1 -> pallet_e1     E2 -> pallet_e2
  J1 -> pallet_j1     J2 -> pallet_j2

Weight columns:
  - PalletWeight         -> gross_weight (-1 sentinel when empty)
  - GreenhouseNetWeight  -> net_weight
  - weight_uom           hardcoded to 'pound'
  - number_of_containers hardcoded to 1

Also upserts 6 grow_harvest_container rows (one pallet per
variety+grade) with tare regression formulas from the legacy sheet.

Usage:
    python migrations/20260401000026_grow_cuke_harvest.py

Rerunnable: deletes all grow_harvest_weight rows for farm_id='cuke',
then reinserts.
"""

import sys
from datetime import datetime, timedelta
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
from _pg import get_pg_conn, paginate_select, pg_bulk_insert

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
FARM_ID = "cuke"

GRADE_MAP = {
    "1": "1",
    "2": "2",
}

VARIETY_MAP = {
    "K": "k",
    "J": "j",
    "E": "e",
}

# Default invnt_item per variety for stub seed batches
DEFAULT_ITEM = {
    "K": "delta_star_minis_rz",
    "J": "f1_tsx_cu235jp_tokita",
    "E": "english",
}
TRIAL_TYPE_ID = "legacy_trial"

# Container ID = pallet_{variety_lower}{grade_number}
# e.g. Variety=K, Grade=1 -> pallet_k1
CONTAINERS = [
    {
        "id": "pallet_k1",
        "name": "Pallet K1",
        "grow_variety_id": "k",
        "grow_grade_id": "1",
        "tare_formula": "ROUND(0.0316203631692461 * gross_weight + -0.835015982812408) * 3 + 48",
    },
    {
        "id": "pallet_k2",
        "name": "Pallet K2",
        "grow_variety_id": "k",
        "grow_grade_id": "2",
        "tare_formula": "ROUND(0.0285084470508113 * gross_weight + 0.38656882092243) * 3",
    },
    {
        "id": "pallet_e1",
        "name": "Pallet E1",
        "grow_variety_id": "e",
        "grow_grade_id": "1",
        "tare_formula": "ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48",
    },
    {
        "id": "pallet_e2",
        "name": "Pallet E2",
        "grow_variety_id": "e",
        "grow_grade_id": "2",
        "tare_formula": "ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3",
    },
    {
        "id": "pallet_j1",
        "name": "Pallet J1",
        "grow_variety_id": "j",
        "grow_grade_id": "1",
        "tare_formula": "ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48",
    },
    {
        "id": "pallet_j2",
        "name": "Pallet J2",
        "grow_variety_id": "j",
        "grow_grade_id": "2",
        "tare_formula": "ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3",
    },
]

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


def parse_numeric(val, default=None):
    if val is None:
        return default
    s = str(val).strip().replace(",", "")
    if not s:
        return default
    try:
        return float(s)
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
# Setup: harvest containers
# ---------------------------------------------------------------------------

def ensure_containers(supabase):
    """Upsert 6 pallet container rows (one per variety+grade) with tare formulas."""
    print("\n--- grow_harvest_container ---")
    rows = []
    for spec in CONTAINERS:
        rows.append(audit({
            "id": spec["id"],
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "name": spec["name"],
            "grow_variety_id": spec["grow_variety_id"],
            "grow_grade_id": spec["grow_grade_id"],
            "weight_uom": "pound",
            "tare_weight": None,
            "is_tare_calculated": True,
            "tare_formula": spec["tare_formula"],
            "tare_formula_inputs": None,
        }))
    supabase.table("grow_harvest_container").upsert(rows).execute()
    print(f"  Upserted {len(rows)} rows: {[r['id'] for r in rows]}")


# ---------------------------------------------------------------------------
# Seed batch lookup
# ---------------------------------------------------------------------------

def build_batch_lookup(supabase):
    """Build a dict of batch_code -> id from grow_seed_batch for cuke farm.

    Paginated to bypass the 1000-row PostgREST cap (this table will grow
    well past 1000 as the farm expands).
    """
    batches = paginate_select(
        supabase, "grow_seed_batch", "id,batch_code",
        eq_filters={"farm_id": FARM_ID},
    )
    return {b["batch_code"]: b["id"] for b in batches}


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    """Delete all cuke harvest weights and containers so the migration is rerunnable."""
    print("\nClearing existing cuke harvest data...")
    supabase.table("grow_harvest_weight").delete().eq(
        "farm_id", FARM_ID
    ).execute()
    print("  Cleared grow_harvest_weight")
    supabase.table("grow_harvest_container").delete().eq(
        "farm_id", FARM_ID
    ).execute()
    print("  Cleared grow_harvest_container")


def ensure_grades(supabase):
    """Ensure grow_grade rows use id='1' and '2' instead of 'on_grade'/'off_grade'."""
    print("\n--- grow_grade ---")
    # Delete old-style IDs if they exist (no-op if already correct)
    for old_id in ("on_grade", "off_grade"):
        try:
            supabase.table("grow_grade").delete().eq("id", old_id).execute()
        except Exception:
            pass
    rows = [
        audit({
            "id": "1",
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "code": "1",
            "name": "On Grade",
        }),
        audit({
            "id": "2",
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "code": "2",
            "name": "Off Grade",
        }),
    ]
    supabase.table("grow_grade").upsert(rows).execute()
    print("  Upserted grades: 1 (On Grade), 2 (Off Grade)")

# ---------------------------------------------------------------------------
# Stub seed batches for missing cycles
# ---------------------------------------------------------------------------

def ensure_stub_batches(supabase, records, existing_lookup, known_sites):
    """Create stub seed batch rows for harvest cycles not in grow_seed_batch.

    Scans all harvest records, identifies batch codes not in existing_lookup,
    and upserts stub rows with -1 sentinel values so every harvest row can
    link to a seed batch.
    """
    missing = {}  # batch_code -> {site_id, variety, is_trial, harvest_date}

    for r in records:
        variety = str(r.get("Variety", "")).strip().upper()
        if variety not in VARIETY_MAP:
            continue

        cycle = str(r.get("SeedingCycle", "")).strip()
        if not cycle:
            continue

        is_trial = str(r.get("is_trial", "")).strip().upper() == "TRUE"
        suffix = "T" if is_trial else "P"
        batch_code = f"{cycle}{suffix}"

        if batch_code in existing_lookup or batch_code in missing:
            continue

        gh = normalize_gh(r.get("Greenhouse"))
        if not gh or gh not in known_sites:
            continue

        harvest_date = parse_date(r.get("HarvestDate"))

        missing[batch_code] = {
            "site_id": gh,
            "variety": variety,
            "is_trial": is_trial,
            "harvest_date": harvest_date,
        }

    if not missing:
        print("\n  No missing seed batches to stub")
        return

    rows = []
    for batch_code, meta in missing.items():
        item_id = DEFAULT_ITEM[meta["variety"]]

        # Back-derive seeding date: harvest is ~42 days after seeding
        if meta["harvest_date"]:
            seeding_date = meta["harvest_date"] - timedelta(days=42)
            transplant_date = seeding_date + timedelta(days=14)
            est_harvest = meta["harvest_date"]
        else:
            seeding_date = datetime(2000, 1, 1).date()
            transplant_date = datetime(2000, 1, 15).date()
            est_harvest = datetime(2000, 2, 12).date()

        row = audit({
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "site_id": meta["site_id"],
            "batch_code": batch_code,
            "invnt_item_id": item_id,
            "seeding_uom": "bag",
            "number_of_units": -1,
            "seeds_per_unit": -1,
            "number_of_rows": -1,
            "seeding_date": seeding_date.isoformat(),
            "transplant_date": transplant_date.isoformat(),
            "estimated_harvest_date": est_harvest.isoformat(),
            "status": "harvested",
            "notes": "Stub: auto-created by harvest migration (no seeding sheet data)",
        })
        if meta["is_trial"]:
            row["grow_trial_type_id"] = TRIAL_TYPE_ID

        rows.append(row)

    print(f"\n  Creating {len(rows)} stub seed batches for unmatched cycles")
    insert_rows(supabase, "grow_seed_batch", rows, upsert=True, on_conflict="org_id,batch_code")


# ---------------------------------------------------------------------------
# Row transform
# ---------------------------------------------------------------------------

def build_harvest_row(sheet_row, batch_lookup, known_sites):
    """Transform one sheet row into a grow_harvest_weight dict.

    Returns the row dict on success, or a dict with '_skip' key and reason on failure.
    """
    harvest_date = parse_date(sheet_row.get("HarvestDate"))
    if not harvest_date:
        return {"_skip": "no_date"}

    net_weight = parse_numeric(sheet_row.get("GreenhouseNetWeight"))
    if net_weight is None:
        return {"_skip": "no_weight"}

    gh = normalize_gh(sheet_row.get("Greenhouse"))
    if not gh or gh not in known_sites:
        return {"_skip": "unknown_site", "_detail": gh}

    variety = str(sheet_row.get("Variety", "")).strip().upper()
    if variety not in VARIETY_MAP:
        return {"_skip": "unknown_variety", "_detail": variety}

    grade = str(sheet_row.get("Grade", "")).strip()
    if grade not in GRADE_MAP:
        return {"_skip": "unknown_grade", "_detail": grade}

    cycle = str(sheet_row.get("SeedingCycle", "")).strip()
    if not cycle:
        return {"_skip": "no_cycle"}

    is_trial = str(sheet_row.get("is_trial", "")).strip().upper() == "TRUE"
    suffix = "T" if is_trial else "P"
    batch_code = f"{cycle}{suffix}"
    batch_id = batch_lookup.get(batch_code)

    # For trials, try disambiguation suffixes T2, T3
    if not batch_id and is_trial:
        for n in range(2, 5):
            batch_id = batch_lookup.get(f"{cycle}T{n}")
            if batch_id:
                break

    if not batch_id:
        return {"_skip": "unmatched_batch", "_detail": batch_code}

    gross_weight = parse_numeric(sheet_row.get("PalletWeight"), default=-1)

    variety_lower = VARIETY_MAP[variety]
    container_id = f"pallet_{variety_lower}{grade}"
    grade_id = GRADE_MAP[grade]

    reported_by_raw = str(sheet_row.get("ReportedBy", "")).strip().lower()
    reported_by = reported_by_raw if "@" in reported_by_raw else AUDIT_USER

    return {
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "site_id": gh,
        "ops_task_tracker_id": None,
        "grow_seed_batch_id": batch_id,
        "grow_grade_id": grade_id,
        "harvest_date": harvest_date.isoformat(),
        "grow_harvest_container_id": container_id,
        "number_of_containers": 1,
        "weight_uom": "pound",
        "gross_weight": gross_weight,
        "net_weight": net_weight,
        "created_by": reported_by,
        "updated_by": reported_by,
    }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW CUKE HARVEST MIGRATION")
    print("=" * 60)

    clear_existing(supabase)
    ensure_grades(supabase)
    ensure_containers(supabase)

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

    print("\nReading grow_C_harvest...")
    ws = gc.open_by_key(GROW_SHEET_ID).worksheet("grow_C_harvest")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    # Create stub seed batches for cycles not in grow_seed_batch
    batch_lookup = build_batch_lookup(supabase)
    print(f"\n  Loaded {len(batch_lookup)} seed batch codes for lookup")
    ensure_stub_batches(supabase, records, batch_lookup, known_sites)

    # Rebuild lookup after stubs were created
    batch_lookup = build_batch_lookup(supabase)
    print(f"  Now {len(batch_lookup)} seed batch codes after stubs")

    rows = []
    skip_counts = {}
    unmatched_batches = set()

    for r in records:
        result = build_harvest_row(r, batch_lookup, known_sites)
        if "_skip" in result:
            reason = result["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            if reason == "unmatched_batch":
                unmatched_batches.add(result["_detail"])
            continue
        rows.append(result)

    print(f"\n  Built {len(rows)} harvest weight rows")
    for reason, count in sorted(skip_counts.items()):
        print(f"  Skipped {count} rows: {reason}")
    if unmatched_batches:
        print(f"  Unmatched batch codes ({len(unmatched_batches)}): {sorted(unmatched_batches)}")

    # Bulk insert via psycopg2 — 53k rows in one transaction is orders
    # of magnitude faster than ~530 PostgREST roundtrips.
    print(f"\n--- grow_harvest_weight ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_harvest_weight", rows)
        conn.commit()
    print(f"  Inserted {len(rows)} rows")

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
