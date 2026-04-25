"""
[RETIRED — retained for reference only]
----------------------------------------
As of 2026-04-17 this script is no longer part of the nightly run. Cuke
seed batches migrated to the new grow_cuke_seed_batch table (see
20260417000001_cuke_plantmap.py) and that table is now static. The
grow_C_seeding Google Sheet is frozen. Running this script will fail
because grow_seed_batch has been renamed to grow_lettuce_seed_batch.

Migrate Cuke Seeding Data
==========================
Migrates grow_C_seeding into grow_seed_batch with one batch row per
(sheet row x variety block). One sheet row plants 1-3 main varieties
(K/J/E columns) plus 0-3 trial varieties — each becomes its own batch
row with a unique batch_code suffix.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_C_seeding: 292 rows -> ~600-700 grow_seed_batch rows

Batch code format:
  - Main plantings: {SeedingCycle}{variety_letter}P  (e.g. 1912HIKP, 200101EP)
  - Trial seedings: {SeedingCycle}{variety_letter}T  (e.g. 2509WAET)
  - If two trial slots in the same row share a variety letter, the second
    one is disambiguated as {cycle}{letter}T2.

Schema gaps (sheet doesn't track):
  - number_of_rows         hardcoded to -1 (sentinel for "unknown")
  - transplant_date        seeding_date + 14 days
  - estimated_harvest_date seeding_date + 42 days (6 weeks)
  - seeding_uom            hardcoded to 'bag'

Auto-creates two missing invnt_item rows for varieties not in the
existing register: 'english' and 'cumlaude'. Also seeds a single
generic grow_trial_type ('legacy_trial') so the 11 trial rows can
be properly flagged.

Variety mapping (sheet block letter -> grow_variety.id):
  K -> k (Keiki)
  J -> j (Japanese)
  E -> e (English)

Item resolution (sheet name -> invnt_item.id):
  'Delta Star'           -> delta_star_minis_rz   (existing)
  'Tokita'               -> f1_tsx_cu235jp_tokita (existing)
  'English'              -> english               (auto-created here)
  'Cumlaude / 102247687' -> cumlaude              (auto-created here)
  'Cumlade' (trial typo) -> cumlaude              (auto-created here)

Status mapping (sheet CycleStatus -> schema status):
  Complete         -> harvested
  Harvesting       -> harvesting
  Pre-harvesting   -> transplanted

Usage:
    python migrations/20260401000025_grow_cuke_seeding.py

Rerunnable: deletes batches with batch_code starting with the cuke
seeding cycle prefix, then reinserts.
"""

import re
import sys
from datetime import datetime, timedelta
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

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
FARM_ID = "cuke"
TRIAL_TYPE_ID = "legacy_trial"

# Variety block letter -> grow_variety.id
VARIETY_LETTER_MAP = {"K": "k", "J": "j", "E": "e"}

# Sheet status -> schema enum
STATUS_MAP = {
    "complete": "harvested",
    "harvesting": "harvesting",
    "pre-harvesting": "transplanted",
}

# Sheet variety name -> invnt_item.id (the existing items)
EXISTING_ITEM_MAP = {
    "delta star": "delta_star_minis_rz",
    "tokita":     "f1_tsx_cu235jp_tokita",
}

# Items this script will auto-create
ITEMS_TO_CREATE = [
    {
        "id": "english",
        "name": "English",
        "grow_variety_id": "E",
        "manufacturer": None,
    },
    {
        "id": "cumlaude",
        "name": "Cumlaude",
        "grow_variety_id": "E",
        "manufacturer": None,
        "description": "Trial seed variety, originally tracked in legacy sheet as 'Cumlaude / 102247687' or 'Cumlade'",
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


def parse_int(val, default=None):
    if val is None:
        return default
    s = str(val).strip().replace(",", "").replace("%", "")
    if not s:
        return default
    try:
        return int(float(s))
    except ValueError:
        return default


def normalize_gh(raw):
    """'1' -> '01', '1' -> '01', 'HI' -> 'hi'."""
    s = str(raw).strip().lower()
    if not s:
        return None
    if s.isdigit() and len(s) == 1:
        s = s.zfill(2)
    return s


# ---------------------------------------------------------------------------
# Setup: trial type + missing invnt_items
# ---------------------------------------------------------------------------

def ensure_trial_type(supabase):
    """Seed a single legacy_trial row in grow_trial_type so trial seeds can
    be flagged via grow_trial_type_name. Farm-scoped to cuke."""
    print("\n--- grow_trial_type ---")
    row = audit({
        "id": TRIAL_TYPE_ID,
        "org_id": ORG_ID,
        "farm_name": FARM_ID,
        "name": "Legacy Trial",
        "description": "Generic trial type used to flag historical trial seedings migrated from the legacy grow_C_seeding sheet",
    })
    supabase.table("grow_trial_type").upsert(row).execute()
    print(f"  Upserted {TRIAL_TYPE_ID}")


def ensure_missing_items(supabase):
    """Create the two invnt_item rows the cuke seeding sheet references but
    that don't exist in the current item register (English, Cumlaude)."""
    print("\n--- invnt_item (auto-create missing varieties) ---")
    rows = []
    for spec in ITEMS_TO_CREATE:
        rows.append(audit({
            "id": spec["id"],
            "org_id": ORG_ID,
            "farm_name": FARM_ID,
            "invnt_category_id": "seeds",
            "name": spec["name"],
            "qb_account": "1. Growing:Seeding",
            "description": spec.get("description"),
            "burn_uom": "seed",
            "onhand_uom": "seed",
            "order_uom": "pack",
            "burn_per_onhand": 1,
            "burn_per_order": 1000.0,
            "is_palletized": False,
            "order_per_pallet": 0,
            "pallet_per_truckload": 0,
            "is_frequently_used": False,
            "burn_per_week": 0.0,
            "cushion_weeks": 0.0,
            "is_auto_reorder": False,
            "reorder_point_in_burn": 0.0,
            "reorder_quantity_in_burn": 0.0,
            "requires_lot_tracking": False,
            "requires_expiry_date": False,
            "manufacturer": spec.get("manufacturer"),
            "grow_variety_id": spec["grow_variety_id"],
            "seed_is_pelleted": False,
            "photos": [],
            "is_active": True,
        }))
    supabase.table("invnt_item").upsert(rows).execute()
    print(f"  Upserted {len(rows)} rows: {[r['id'] for r in rows]}")


# ---------------------------------------------------------------------------
# Item lookup
# ---------------------------------------------------------------------------

def build_item_lookup(supabase):
    """Build a fuzzy lookup from sheet variety name -> invnt_item.id.

    Combines the explicit EXISTING_ITEM_MAP with fuzzy substring matching
    against all cuke seed items, plus the two we auto-created.
    """
    items = (
        supabase.table("invnt_item")
        .select("id,name")
        .eq("farm_name", FARM_ID)
        .eq("invnt_category_id", "seeds")
        .execute()
        .data
    )
    item_by_name_lower = {it["name"].lower(): it["id"] for it in items}

    def lookup(raw_name):
        if not raw_name:
            return None
        s = str(raw_name).strip()
        if not s:
            return None
        s_lower = s.lower()

        # Explicit map first
        for key, item_id in EXISTING_ITEM_MAP.items():
            if key in s_lower:
                return item_id

        # Auto-created items
        if "english" in s_lower:
            return "english"
        if "cumlaude" in s_lower or "cumlade" in s_lower:
            return "cumlaude"

        # Fuzzy: substring match against any item name
        for name_lower, item_id in item_by_name_lower.items():
            if s_lower in name_lower or name_lower in s_lower:
                return item_id

        return None

    return lookup


# ---------------------------------------------------------------------------
# Fan-out per sheet row
# ---------------------------------------------------------------------------

def derive_dates(seeding_date):
    """Schema requires transplant_date and estimated_harvest_date NOT NULL.
    The sheet doesn't track them, so we hardcode:
      - transplant_date         = seeding_date + 14 days
      - estimated_harvest_date  = seeding_date + 42 days (6 weeks)
    """
    return (
        seeding_date + timedelta(days=14),
        seeding_date + timedelta(days=42),
    )


def build_main_batch(sheet_row, letter, item_lookup, status, site_id, reported_by):
    """Build a grow_seed_batch row from one variety block (K/J/E).

    Returns None if the block isn't filled (no plants_per_bag or count).
    """
    plants_per_bag = parse_int(sheet_row.get(f"{letter}PlantsPerBag"))
    number_of_seeds = parse_int(sheet_row.get(f"{letter}NumberOfSeeds"))
    name = str(sheet_row.get(f"{letter}Name", "")).strip()

    if not name and not number_of_seeds:
        return None
    if not plants_per_bag or not number_of_seeds:
        return None

    item_id = item_lookup(name)
    if not item_id:
        # Skipping is fine here — the only varieties we don't have are auto-created
        # by ensure_missing_items, so any unmatched name is genuinely unknown
        return {"_unmatched": name}

    seeding_date = parse_date(sheet_row.get("SeedingDate"))
    if not seeding_date:
        return None

    transplant_date, est_harvest = derive_dates(seeding_date)
    cycle = str(sheet_row.get("SeedingCycle", "")).strip()
    if not cycle:
        return None

    number_of_units = max(1, round(number_of_seeds / plants_per_bag))

    return {
        "org_id": ORG_ID,
        "farm_name": FARM_ID,
        "site_id": site_id,
        "batch_code": f"{cycle}{letter}P",
        "invnt_item_name": item_id,
        "seeding_uom": "bag",
        "number_of_units": number_of_units,
        "seeds_per_unit": plants_per_bag,
        "number_of_rows": -1,
        "seeding_date": seeding_date.isoformat(),
        "transplant_date": transplant_date.isoformat(),
        "estimated_harvest_date": est_harvest.isoformat(),
        "status": status,
        "notes": str(sheet_row.get("Notes", "")).strip() or None,
        "created_by": reported_by,
        "updated_by": reported_by,
    }


def build_trial_batches(sheet_row, item_lookup, status, site_id, reported_by):
    """Build 0-3 trial seed batches from trial_seed_{1,2,3}_* columns.

    Trials don't have plants_per_bag info — we hardcode seeds_per_unit=4
    (typical cuke planting) and round number_of_units accordingly.

    Batch code format: {cycle}{variety_letter}T (e.g. 2509WAET). When two
    trial slots in the same row share a variety letter, the second one
    gets a numeric suffix: {cycle}{letter}T2.
    """
    rows = []
    seeding_date = parse_date(sheet_row.get("SeedingDate"))
    if not seeding_date:
        return rows
    transplant_date, est_harvest = derive_dates(seeding_date)
    cycle = str(sheet_row.get("SeedingCycle", "")).strip()
    if not cycle:
        return rows

    used_codes = set()  # batch codes already produced for this sheet row

    for slot in (1, 2, 3):
        variety_letter = str(sheet_row.get(f"trial_seed_{slot}_variety", "")).strip().upper()
        name_lot = str(sheet_row.get(f"trial_seed_{slot}_name_lot", "")).strip()
        count = parse_int(sheet_row.get(f"trial_seed_{slot}_count"))
        if not name_lot or not count:
            continue
        if variety_letter not in VARIETY_LETTER_MAP:
            # Variety letter is required to build the batch code in the
            # requested format; skip slots without one (shouldn't happen
            # in current data but defensive).
            rows.append({"_unmatched": f"{name_lot} (missing trial variety letter)"})
            continue
        item_id = item_lookup(name_lot)
        if not item_id:
            rows.append({"_unmatched": name_lot})
            continue

        # Disambiguate within-row collisions on variety letter
        base_code = f"{cycle}{variety_letter}T"
        code = base_code
        n = 2
        while code in used_codes:
            code = f"{base_code}{n}"
            n += 1
        used_codes.add(code)

        seeds_per_unit = 4
        number_of_units = max(1, round(count / seeds_per_unit))
        rows.append({
            "org_id": ORG_ID,
            "farm_name": FARM_ID,
            "site_id": site_id,
            "batch_code": code,
            "invnt_item_name": item_id,
            "grow_trial_type_name": TRIAL_TYPE_ID,
            "seeding_uom": "bag",
            "number_of_units": number_of_units,
            "seeds_per_unit": seeds_per_unit,
            "number_of_rows": -1,
            "seeding_date": seeding_date.isoformat(),
            "transplant_date": transplant_date.isoformat(),
            "estimated_harvest_date": est_harvest.isoformat(),
            "status": status,
            "notes": str(sheet_row.get("Notes", "")).strip() or None,
            "created_by": reported_by,
            "updated_by": reported_by,
        })
    return rows


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    """Clear cuke seed batches with our batch_code suffixes so the migration
    is rerunnable.

    Cuke seeding cycle codes look like '1912HI', '200101'. Our batch codes
    end with '{K|J|E}P' for main plantings or '{K|J|E}T' for trials, optionally
    followed by a digit for trial collision disambiguation. We match the
    end-of-string suffixes so we don't touch any unrelated cuke batches.
    """
    print("\nClearing existing cuke seed batches...")
    # PostgREST doesn't support OR across .like calls, so we issue separate
    # deletes for each suffix family. Trial collision codes (T2, T3) match
    # via the % wildcard before the digit.
    suffixes = ["KP", "JP", "EP", "KT", "JT", "ET"]
    for s in suffixes:
        supabase.table("grow_seed_batch").delete().eq(
            "farm_name", FARM_ID
        ).like("batch_code", f"%{s}").execute()
    # Trial disambiguation suffixes ({letter}T2, {letter}T3 ...)
    for s in ["KT_", "JT_", "ET_"]:
        # PostgREST .like uses _ as a single-char wildcard, which is what we want
        supabase.table("grow_seed_batch").delete().eq(
            "farm_name", FARM_ID
        ).like("batch_code", f"%{s}").execute()
    print("  Cleared")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW CUKE SEEDING MIGRATION")
    print("=" * 60)

    clear_existing(supabase)
    ensure_trial_type(supabase)
    ensure_missing_items(supabase)
    item_lookup = build_item_lookup(supabase)

    # Load known cuke greenhouse site IDs for validation
    sites = (
        supabase.table("org_site")
        .select("id")
        .eq("farm_name", FARM_ID)
        .eq("org_site_subcategory_id", "greenhouse")
        .execute()
        .data
    )
    known_sites = {s["id"] for s in sites}

    print("\nReading grow_C_seeding...")
    ws = gc.open_by_key(GROW_SHEET_ID).worksheet("grow_C_seeding")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    rows = []
    skipped_no_date = 0
    skipped_no_site = 0
    skipped_no_cycle = 0
    unmatched_names = set()
    main_batches = 0
    trial_batches = 0

    for r in records:
        seeding_date = parse_date(r.get("SeedingDate"))
        if not seeding_date:
            skipped_no_date += 1
            continue

        gh = normalize_gh(r.get("Greenhouse"))
        if not gh or gh not in known_sites:
            skipped_no_site += 1
            continue

        cycle = str(r.get("SeedingCycle", "")).strip()
        if not cycle:
            skipped_no_cycle += 1
            continue

        status = STATUS_MAP.get(str(r.get("CycleStatus", "")).strip().lower(), "harvested")
        reported_by_raw = str(r.get("ReportedBy", "")).strip().lower()
        reported_by = reported_by_raw if "@" in reported_by_raw else AUDIT_USER

        # Main variety blocks (K, J, E)
        for letter in ("K", "J", "E"):
            batch = build_main_batch(r, letter, item_lookup, status, gh, reported_by)
            if not batch:
                continue
            if "_unmatched" in batch:
                unmatched_names.add(batch["_unmatched"])
                continue
            rows.append(batch)
            main_batches += 1

        # Trial seeds
        for trial in build_trial_batches(r, item_lookup, status, gh, reported_by):
            if "_unmatched" in trial:
                unmatched_names.add(trial["_unmatched"])
                continue
            rows.append(trial)
            trial_batches += 1

    print(f"\n  Built {len(rows)} batches: {main_batches} main + {trial_batches} trial")
    if skipped_no_date:
        print(f"  Skipped {skipped_no_date} sheet rows: no parseable seeding date")
    if skipped_no_site:
        print(f"  Skipped {skipped_no_site} sheet rows: unknown greenhouse")
    if skipped_no_cycle:
        print(f"  Skipped {skipped_no_cycle} sheet rows: no SeedingCycle")
    if unmatched_names:
        print(f"  Unmatched variety names ({len(unmatched_names)}): {sorted(unmatched_names)}")

    insert_rows(supabase, "grow_seed_batch", rows)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
