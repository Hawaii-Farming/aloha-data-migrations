"""
Migrate Lettuce Seeding + Harvest Data
=======================================
Migrates grow_L_seeding into grow_lettuce_seed_batch and grow_harvest_weight.
Each sheet row contains a complete cycle (seeding + harvest) so we
insert one seed_batch and (when harvested) one harvest_weight per row.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_L_seeding: ~5,000 rows (Feb 2024 through Mar 2026)

Setup (upserted):
  - 1 grow_harvest_container (board; tare=0)
  - grow_trial_type rows for each unique trialtype
  - grow_cycle_pattern rows for each unique harvestdayspattern
  - invnt_item auto-created for any seedname not already in the register
  - invnt_lot auto-created for each unique (seedname, seedlot) pair

Per-row inserts:
  - grow_lettuce_seed_batch: one per sheet row (batch_code = seedingcycle verbatim)
    Uses grow_seed_mix_id when seedname matches a mix (e.g. "Mixed Version 2.0")
    Otherwise uses invnt_item_id. CHECK constraint enforces XOR.
  - grow_harvest_weight: one per harvested row (harvestdate AND
    greenhousenetweight both populated). number_of_containers=1
    (representative weigh-in of one board); gross_weight=net_weight
    (tare is 0 for the board container).

Rerunnable: identifies our rows via the notes marker
"Legacy lettuce migration" and deletes them before reinsert.

Usage:
    python migrations/20260401000028_grow_lettuce_seeding.py
"""

import re
import sys
import uuid
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
FARM_ID = "lettuce"
CONTAINER_ID = "board"
NOTES_MARKER = "Legacy lettuce migration"

# Variety letter -> grow_variety.id (sheet uses uppercase 2-letter codes)
VARIETY_MAP = {
    "GB": "gb", "GL": "gl", "RL": "rl", "GA": "ga",
    "GR": "gr", "RR": "rr", "RB": "rb", "GO": "go",
    "RO": "ro", "GC": "gc", "RC": "rc", "GF": "gf",
    "RF": "rf", "GG": "gg", "RG": "rg", "MT": "mt",
    "MS": "ms", "MG": "mg", "WC": "wc", "BB": "bb",
    "E": "e", "J": "j", "K": "k", "TR": "tr",
}

STATUS_MAP = {
    "harvested": "harvested",
    "harvesting": "harvesting",
    "pre-harvesting": "transplanted",
    "transplanted": "transplanted",
    "seeded": "seeded",
    "planned": "planned",
}


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def to_id(raw: str) -> str:
    """Slug a name into a TEXT PK (alphanumeric + underscores)."""
    if not raw:
        return ""
    return re.sub(r"[^a-z0-9_]+", "_", str(raw).lower()).strip("_")


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
    # ReportedDateTime is like "2/4/2024 11:55:13" — take date portion
    s = s.split(" ")[0]
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parse_int(val, default=None):
    if val is None:
        return default
    s = str(val).strip().replace(",", "")
    if not s:
        return default
    try:
        return int(float(s))
    except ValueError:
        return default


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


def parse_bool(val):
    s = str(val).strip().lower()
    return s in ("true", "yes", "1", "t", "y")


# ---------------------------------------------------------------------------
# Setup: container, trial types, cycle patterns, items, lots
# ---------------------------------------------------------------------------

def ensure_container(supabase):
    """Upsert the single lettuce 'board' harvest container."""
    print("\n--- grow_harvest_container ---")
    row = {
        "id": CONTAINER_ID,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "name": "Board",
        "grow_variety_id": None,
        "grow_grade_id": None,
        "weight_uom": "pound",
        "tare_weight": 0,
        "is_tare_calculated": False,
        "tare_formula": None,
        "tare_formula_inputs": None,
        "created_by": AUDIT_USER,
        "updated_by": AUDIT_USER,
    }
    supabase.table("grow_harvest_container").upsert(row).execute()
    print(f"  Upserted 1 row: {CONTAINER_ID}")


def ensure_trial_types(supabase, records):
    """Upsert a grow_trial_type per unique trialtype value in the sheet."""
    names = set()
    for r in records:
        if not parse_bool(r.get("istrial")):
            continue
        tt = str(r.get("trialtype", "")).strip()
        if tt:
            names.add(tt)
    if not names:
        return {}
    rows = []
    name_to_id = {}
    for name in sorted(names):
        tid = f"lettuce_{to_id(name)}"
        name_to_id[name] = tid
        rows.append({
            "id": tid,
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "name": name,
            "description": None,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })
    print(f"\n--- grow_trial_type ---")
    supabase.table("grow_trial_type").upsert(rows).execute()
    print(f"  Upserted {len(rows)} rows: {[r['id'] for r in rows]}")
    return name_to_id


def ensure_cycle_patterns(supabase, records):
    """Upsert a grow_cycle_pattern per unique harvestdayspattern."""
    names = set()
    for r in records:
        hp = str(r.get("harvestdayspattern", "")).strip()
        if hp:
            names.add(hp)
    if not names:
        return {}
    rows = []
    name_to_id = {}
    for name in sorted(names):
        pid = to_id(name)
        name_to_id[name] = pid
        rows.append({
            "id": pid,
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "name": name,
            "description": None,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })
    print(f"\n--- grow_cycle_pattern ---")
    supabase.table("grow_cycle_pattern").upsert(rows).execute()
    print(f"  Upserted {len(rows)} rows: {[r['id'] for r in rows]}")
    return name_to_id


def ensure_items(supabase, records, mix_names_lower):
    """Build seedname -> invnt_item.id lookup. Auto-create missing.

    Skips seednames that match a mix (those get grow_seed_mix_id instead).
    Returns: {seedname_lower: invnt_item.id}
    """
    # Load existing lettuce seed items (paginated — 186 rows today, near cap)
    existing = paginate_select(
        supabase, "invnt_item", "id,name,grow_variety_id",
        eq_filters={"farm_id": FARM_ID, "invnt_category_id": "seeds"},
    )
    by_name_lower = {it["name"].lower(): it["id"] for it in existing}

    # Find seednames in sheet that aren't a mix and aren't in invnt_item
    to_create = {}  # seedname (trimmed) -> {variety_letter, name}
    for r in records:
        sn = str(r.get("seedname", "")).strip()
        if not sn:
            continue
        sn_lower = sn.lower()
        if sn_lower in mix_names_lower:
            continue  # handled via grow_seed_mix
        if sn_lower in by_name_lower:
            continue  # already exists
        if sn in to_create:
            continue
        variety = str(r.get("variety", "")).strip().upper()
        to_create[sn] = {
            "variety_id": VARIETY_MAP.get(variety),
            "name": sn,
        }

    if to_create:
        rows = []
        for sn, spec in to_create.items():
            item_id = to_id(sn)
            rows.append({
                "id": item_id,
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "invnt_category_id": "seeds",
                "name": spec["name"],
                "qb_account": "1. Growing:Seeding",
                "description": None,
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
                "manufacturer": None,
                "grow_variety_id": spec["variety_id"],
                "seed_is_pelleted": False,
                "photos": [],
                "is_active": True,
                "created_by": AUDIT_USER,
                "updated_by": AUDIT_USER,
            })
            by_name_lower[sn.lower()] = item_id
        print(f"\n--- invnt_item (auto-create missing seeds) ---")
        supabase.table("invnt_item").upsert(rows).execute()
        print(f"  Upserted {len(rows)} rows")
    else:
        print(f"\n  All seednames in sheet already exist in invnt_item (or are mixes)")

    return by_name_lower


def ensure_lots(supabase, records, item_by_name_lower, mix_names_lower):
    """Build (seedname_lower, seedlot) -> invnt_lot.id lookup. Auto-create missing.

    Only creates lots for non-mix seednames (mixes don't carry their own lot).
    Returns: {(seedname_lower, seedlot_stripped): invnt_lot.id}
    """
    # Collect unique (seedname, seedlot) pairs from sheet
    wanted = {}  # (seedname_lower, seedlot) -> {item_id, lot_number}
    for r in records:
        sn = str(r.get("seedname", "")).strip()
        sl = str(r.get("seedlot", "")).strip()
        if not sn or not sl:
            continue
        sn_lower = sn.lower()
        if sn_lower in mix_names_lower:
            continue  # mixes don't get lots
        item_id = item_by_name_lower.get(sn_lower)
        if not item_id:
            continue
        key = (sn_lower, sl)
        if key in wanted:
            continue
        wanted[key] = {"item_id": item_id, "lot_number": sl}

    if not wanted:
        print(f"\n  No lots to create")
        return {}

    # Check which of these already exist in invnt_lot
    existing = paginate_select(
        supabase, "invnt_lot", "id,lot_number,invnt_item_id",
        eq_filters={"farm_id": FARM_ID},
    )
    existing_by_key = {(e["invnt_item_id"], e["lot_number"]): e["id"] for e in existing}

    rows = []
    lot_lookup = {}  # (seedname_lower, seedlot) -> lot_id
    for (sn_lower, sl), spec in wanted.items():
        ek = (spec["item_id"], sl)
        if ek in existing_by_key:
            lot_lookup[(sn_lower, sl)] = existing_by_key[ek]
            continue
        lot_id = to_id(f"{sn_lower}_{sl}")
        lot_lookup[(sn_lower, sl)] = lot_id
        rows.append({
            "id": lot_id,
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "invnt_item_id": spec["item_id"],
            "lot_number": sl,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    if rows:
        print(f"\n--- invnt_lot (auto-create missing lots) ---")
        supabase.table("invnt_lot").upsert(rows).execute()
        print(f"  Upserted {len(rows)} rows")
    else:
        print(f"\n  All lots already exist")

    return lot_lookup


def build_mix_lookup(supabase):
    """Build seedname_lower -> grow_seed_mix.id lookup for lettuce mixes."""
    mixes = paginate_select(
        supabase, "grow_seed_mix", "id,name",
        eq_filters={"farm_id": FARM_ID},
    )
    return {m["name"].lower(): m["id"] for m in mixes}


# ---------------------------------------------------------------------------
# Clear existing legacy rows for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    """Delete our previously-migrated lettuce rows (identified by notes marker)."""
    print("\nClearing existing lettuce legacy rows...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                DELETE FROM grow_harvest_weight
                WHERE grow_lettuce_seed_batch_id IN (
                    SELECT id FROM grow_lettuce_seed_batch
                    WHERE farm_id = %s AND notes LIKE %s
                )
                """,
                (FARM_ID, f"%{NOTES_MARKER}%"),
            )
            deleted_weights = cur.rowcount
            cur.execute(
                """
                DELETE FROM grow_lettuce_seed_batch
                WHERE farm_id = %s AND notes LIKE %s
                """,
                (FARM_ID, f"%{NOTES_MARKER}%"),
            )
            deleted_batches = cur.rowcount
        conn.commit()
    print(f"  Deleted {deleted_weights} grow_harvest_weight rows")
    print(f"  Deleted {deleted_batches} grow_lettuce_seed_batch rows")


# ---------------------------------------------------------------------------
# Row transform
# ---------------------------------------------------------------------------

def build_rows(
    sheet_row, known_sites, item_by_name_lower, mix_lookup,
    lot_lookup, trial_type_lookup, cycle_pattern_lookup,
):
    """Return (seed_batch_dict, harvest_weight_dict_or_None) or None if skipped."""
    seeding_date = parse_date(sheet_row.get("seedingdate"))
    if not seeding_date:
        return {"_skip": "no_seeding_date"}

    pond_raw = str(sheet_row.get("pond", "")).strip().lower()
    if not pond_raw or pond_raw not in known_sites:
        return {"_skip": "unknown_pond", "_detail": pond_raw}

    seedname = str(sheet_row.get("seedname", "")).strip()
    if not seedname:
        return {"_skip": "no_seedname"}

    cycle = str(sheet_row.get("seedingcycle", "")).strip()
    if not cycle:
        return {"_skip": "no_seedingcycle"}

    seedname_lower = seedname.lower()
    is_mix = seedname_lower in mix_lookup
    if is_mix:
        invnt_item_id = None
        grow_seed_mix_id = mix_lookup[seedname_lower]
    else:
        invnt_item_id = item_by_name_lower.get(seedname_lower)
        grow_seed_mix_id = None
        if not invnt_item_id:
            return {"_skip": "unknown_seedname", "_detail": seedname}

    seedlot = str(sheet_row.get("seedlot", "")).strip()
    invnt_lot_id = lot_lookup.get((seedname_lower, seedlot)) if seedlot else None

    is_trial = parse_bool(sheet_row.get("istrial"))
    trial_type_raw = str(sheet_row.get("trialtype", "")).strip()
    grow_trial_type_id = trial_type_lookup.get(trial_type_raw) if (is_trial and trial_type_raw) else None

    pattern_raw = str(sheet_row.get("harvestdayspattern", "")).strip()
    grow_cycle_pattern_id = cycle_pattern_lookup.get(pattern_raw) if pattern_raw else None

    transplant_date = parse_date(sheet_row.get("ponddate")) or (seeding_date + timedelta(days=2))
    est_harvest_date = parse_date(sheet_row.get("expectedharvestdate")) or (seeding_date + timedelta(days=21))

    status_raw = str(sheet_row.get("cyclestatus", "")).strip().lower()
    status = STATUS_MAP.get(status_raw, "harvested")

    reported_by_raw = str(sheet_row.get("reportedby", "")).strip().lower()
    created_by = reported_by_raw if "@" in reported_by_raw else AUDIT_USER

    notes_raw = str(sheet_row.get("notes", "")).strip()
    notes = f"{notes_raw} | {NOTES_MARKER}" if notes_raw else NOTES_MARKER

    batch_id = str(uuid.uuid4())

    # Capture sheet row's entryid (stable, unique per physical row) so we can
    # sort deterministically when applying disambiguation suffixes below.
    entryid = str(sheet_row.get("entryid", "")).strip()

    seed_batch = {
        "id": batch_id,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "site_id": pond_raw,
        "ops_task_tracker_id": None,
        "batch_code": cycle,
        "grow_cycle_pattern_id": grow_cycle_pattern_id,
        "grow_trial_type_id": grow_trial_type_id,
        "grow_seed_mix_id": grow_seed_mix_id,
        "invnt_item_id": invnt_item_id,
        "invnt_lot_id": invnt_lot_id,
        "seeding_uom": "board",
        "number_of_units": parse_int(sheet_row.get("boardsperpond"), default=-1),
        "seeds_per_unit": parse_int(sheet_row.get("seedsperboard"), default=-1),
        "number_of_rows": parse_int(sheet_row.get("rowspercycle"), default=-1),
        "seeding_date": seeding_date.isoformat(),
        "transplant_date": transplant_date.isoformat(),
        "estimated_harvest_date": est_harvest_date.isoformat(),
        "status": status,
        "notes": notes,
        "created_by": created_by,
        "updated_by": created_by,
        # Non-DB field — used only for stable disambiguation sort below.
        # Removed before insert.
        "_entryid": entryid,
    }

    # Build harvest_weight only if the cycle is actually harvested
    harvest_date = parse_date(sheet_row.get("harvestdate"))
    net_weight = parse_numeric(sheet_row.get("greenhousenetweight"))
    harvest_weight = None
    if harvest_date and net_weight is not None and net_weight > 0:
        harvest_weight = {
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "site_id": pond_raw,
            "ops_task_tracker_id": None,
            "grow_lettuce_seed_batch_id": batch_id,
            "grow_grade_id": None,
            "harvest_date": harvest_date.isoformat(),
            "grow_harvest_container_id": CONTAINER_ID,
            "number_of_containers": 1,
            "weight_uom": "pound",
            "gross_weight": net_weight,
            "net_weight": net_weight,
            "created_by": created_by,
            "updated_by": created_by,
        }

    return {"seed_batch": seed_batch, "harvest_weight": harvest_weight}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW LETTUCE SEEDING MIGRATION")
    print("=" * 60)

    clear_existing()

    # Load known lettuce pond site IDs
    sites = paginate_select(
        supabase, "org_site", "id",
        eq_filters={"farm_id": FARM_ID, "org_site_subcategory_id": "pond"},
    )
    known_sites = {s["id"] for s in sites}
    print(f"\n  Known lettuce ponds: {sorted(known_sites)}")

    print("\nReading grow_L_seeding...")
    ws = gc.open_by_key(GROW_SHEET_ID).worksheet("grow_L_seeding")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    # Setup: load mixes, create trial types, cycle patterns, items, lots
    mix_lookup = build_mix_lookup(supabase)
    mix_names_lower = set(mix_lookup.keys())
    print(f"\n  Loaded {len(mix_lookup)} existing lettuce mixes")

    ensure_container(supabase)
    trial_type_lookup = ensure_trial_types(supabase, records)
    cycle_pattern_lookup = ensure_cycle_patterns(supabase, records)
    item_by_name_lower = ensure_items(supabase, records, mix_names_lower)
    lot_lookup = ensure_lots(supabase, records, item_by_name_lower, mix_names_lower)

    # Transform rows
    seed_batches = []
    harvest_weights = []
    skip_counts = {}
    skip_details = {}

    for r in records:
        result = build_rows(
            r, known_sites, item_by_name_lower, mix_lookup,
            lot_lookup, trial_type_lookup, cycle_pattern_lookup,
        )
        if "_skip" in result:
            reason = result["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            if "_detail" in result:
                skip_details.setdefault(reason, set()).add(result["_detail"])
            continue
        seed_batches.append(result["seed_batch"])
        if result["harvest_weight"]:
            harvest_weights.append(result["harvest_weight"])

    # Disambiguate duplicate batch_codes — first occurrence keeps the cycle
    # code verbatim; subsequent duplicates get _2, _3, ... appended.
    # (The sheet has ~64 duplicate cycles, mostly Mixed Version mix seedings
    # of the same mix on the same day.)
    #
    # Sort by (batch_code, entryid) before applying suffixes so the suffix
    # is stable across re-runs: entryid is unique per sheet row, so adding
    # or removing OTHER rows (with different entryids) never shifts which
    # row gets which suffix. A given physical sheet row always gets the
    # same batch_code suffix as long as its entryid is stable.
    from collections import Counter as _Counter
    seed_batches.sort(key=lambda sb: (sb["batch_code"], sb.get("_entryid") or ""))
    seen = _Counter()
    dupe_count = 0
    for sb in seed_batches:
        code = sb["batch_code"]
        seen[code] += 1
        if seen[code] > 1:
            sb["batch_code"] = f"{code}_{seen[code]}"
            dupe_count += 1
    if dupe_count:
        print(f"  Disambiguated {dupe_count} duplicate batch_codes (appended _2, _3, ...)")

    # Strip the non-DB sort helper before insert
    for sb in seed_batches:
        sb.pop("_entryid", None)

    print(f"\n  Built {len(seed_batches)} seed_batch rows, {len(harvest_weights)} harvest_weight rows")
    for reason, count in sorted(skip_counts.items()):
        print(f"  Skipped {count} rows: {reason}")
        if reason in skip_details:
            details = sorted(x for x in skip_details[reason] if x)
            if details:
                print(f"    Values: {details[:10]}{' ...' if len(details) > 10 else ''}")

    if not seed_batches:
        print("\nNothing to insert.")
        return

    # Bulk insert via psycopg2 in a single transaction
    print(f"\n--- grow_lettuce_seed_batch ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_lettuce_seed_batch", seed_batches)
        print(f"  Inserted {len(seed_batches)} rows")
        if harvest_weights:
            print(f"\n--- grow_harvest_weight ---")
            pg_bulk_insert(conn, "grow_harvest_weight", harvest_weights)
            print(f"  Inserted {len(harvest_weights)} rows")
        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
