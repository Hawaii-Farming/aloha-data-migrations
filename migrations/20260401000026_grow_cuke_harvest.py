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

GRADE_MAP = {
    "1": "on_grade",
    "2": "off_grade",
}

VARIETY_MAP = {
    "K": "k",
    "J": "j",
    "E": "e",
}

# Container ID = pallet_{variety_lower}{grade_number}
# e.g. Variety=K, Grade=1 -> pallet_k1
CONTAINERS = [
    {
        "id": "pallet_k1",
        "name": "Pallet",
        "grow_variety_id": "k",
        "grow_grade_id": "on_grade",
        "tare_formula": "ROUND(0.0316203631692461 * gross_weight + -0.835015982812408) * 3 + 48",
    },
    {
        "id": "pallet_k2",
        "name": "Pallet",
        "grow_variety_id": "k",
        "grow_grade_id": "off_grade",
        "tare_formula": "ROUND(0.0285084470508113 * gross_weight + 0.38656882092243) * 3",
    },
    {
        "id": "pallet_e1",
        "name": "Pallet",
        "grow_variety_id": "e",
        "grow_grade_id": "on_grade",
        "tare_formula": "ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48",
    },
    {
        "id": "pallet_e2",
        "name": "Pallet",
        "grow_variety_id": "e",
        "grow_grade_id": "off_grade",
        "tare_formula": "ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3",
    },
    {
        "id": "pallet_j1",
        "name": "Pallet",
        "grow_variety_id": "j",
        "grow_grade_id": "on_grade",
        "tare_formula": "ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48",
    },
    {
        "id": "pallet_j2",
        "name": "Pallet",
        "grow_variety_id": "j",
        "grow_grade_id": "off_grade",
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
    """Build a dict of batch_code -> id from grow_seed_batch for cuke farm."""
    batches = (
        supabase.table("grow_seed_batch")
        .select("id,batch_code")
        .eq("farm_id", FARM_ID)
        .execute()
        .data
    )
    return {b["batch_code"]: b["id"] for b in batches}


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    """Delete all cuke harvest weight rows so the migration is rerunnable."""
    print("\nClearing existing cuke harvest weights...")
    supabase.table("grow_harvest_weight").delete().eq(
        "farm_id", FARM_ID
    ).execute()
    print("  Cleared")

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
    ensure_containers(supabase)
    batch_lookup = build_batch_lookup(supabase)
    print(f"\n  Loaded {len(batch_lookup)} seed batch codes for lookup")

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

    insert_rows(supabase, "grow_harvest_weight", rows)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
