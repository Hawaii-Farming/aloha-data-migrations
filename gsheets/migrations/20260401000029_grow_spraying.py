"""
Migrate Spraying Applications
==============================
Migrates grow_spray_sched into ops_task_tracker + grow_spray_input +
grow_spray_equipment. Auto-creates missing invnt_item and
grow_spray_compliance rows so every sheet row can be migrated.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_spray_sched: ~1,057 rows (cuke ~762, lettuce ~295)

Setup (idempotent):
  - Auto-create missing invnt_item rows (category=chemicals_pesticides)
  - Auto-create missing grow_spray_compliance rows, taking PHI/REI from the
    first sheet row that uses each (product, farm). Sentinel defaults for
    other regulatory fields.
  - Auto-create missing spray equipment rows:
      Fogger             -> {farm}_fogger          (type=fogger)
      Fogger 1 / Fogger 2 -> {farm}_fogger_1 / _2  (type=fogger)
      Tank 1/2/3          -> {farm}_spray_tank_{n} (type=bag_pack_sprayer)
      Backpack Sprayer    -> {farm}_backpack_sprayer (type=bag_pack_sprayer)

Per sheet row:
  - 1 ops_task_tracker (ops_task_id=spraying)
  - 1-3 grow_spray_input rows (one per non-blank Product01/02/03)
  - 0-N grow_spray_equipment rows:
      - Sprayer blank + WaterGallons > 0 -> 1 row with equipment_id=NULL
      - Sprayer set (may contain + for multiple) -> fan out, WaterGallons
        split evenly across equipment

Applicator name is stored in tracker.notes alongside the legacy marker.
Rerunnable via notes marker "Legacy spraying migration" on ops_task_tracker.

Usage:
    python migrations/20260401000030_grow_spraying.py
"""

import json
import re
import sys
import uuid
from datetime import datetime, date
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
NOTES_MARKER = "Legacy spraying migration"

OPS_TASK_ID = "spraying"
PESTICIDE_CATEGORY_ID = "chemicals_pesticides"

# Sheet Units -> sys_uom.code
UOM_MAP = {
    "gallon": "gallon", "gallons": "gallon",
    "fluid_ounce": "fluid_ounce", "fluid ounce": "fluid_ounce", "fl oz": "fluid_ounce",
    "ounce": "ounce", "ounces": "ounce", "oz": "ounce",
    "pound": "pound", "pounds": "pound", "lb": "pound",
    "gram": "gram", "grams": "gram", "g": "gram",
    "kilogram": "kilogram", "kilograms": "kilogram", "kg": "kilogram",
    "liter": "liter", "liters": "liter", "l": "liter",
    "milliliter": "milliliter", "milliliters": "milliliter", "ml": "milliliter",
}

# Sprayer name (lowercase) -> (equipment_id suffix, org_equipment.type)
SPRAYER_MAP = {
    "fogger": ("fogger", "fogger"),
    "fogger 1": ("fogger_1", "fogger"),
    "fogger 2": ("fogger_2", "fogger"),
    "tank 1": ("spray_tank_1", "bag_pack_sprayer"),
    "tank 2": ("spray_tank_2", "bag_pack_sprayer"),
    "tank 3": ("spray_tank_3", "bag_pack_sprayer"),
    "backpack sprayer": ("backpack_sprayer", "bag_pack_sprayer"),
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def to_id(raw: str) -> str:
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
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parse_time(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in ("%I:%M:%S %p", "%I:%M %p", "%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(s, fmt).time()
        except ValueError:
            continue
    return None


def parse_datetime(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in (
        "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M",
        "%m/%d/%y %H:%M:%S", "%m/%d/%y %H:%M",
    ):
        try:
            return datetime.strptime(s, fmt)
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


def parse_int(val, default=None):
    v = parse_numeric(val)
    if v is None:
        return default
    return int(v)


def normalize_uom(raw: str) -> str | None:
    if not raw:
        return None
    return UOM_MAP.get(str(raw).strip().lower())


def normalize_site(raw: str) -> str:
    """'03' stays '03'; 'HI' -> 'hi'."""
    s = str(raw).strip().lower()
    if s.isdigit() and len(s) == 1:
        s = s.zfill(2)
    return s


def resolve_farm(raw: str) -> str | None:
    s = str(raw).strip().lower()
    return s if s in ("cuke", "lettuce") else None


def split_targets(raw: str) -> list[str]:
    """'Powdery mildew;White fly;Aphids' -> ['Powdery mildew', 'White fly', 'Aphids']."""
    if not raw:
        return []
    return [t.strip() for t in str(raw).split(";") if t.strip()]


def split_sprayers(raw: str) -> list[str]:
    """'Fogger 1+Fogger 2' -> ['Fogger 1', 'Fogger 2']."""
    if not raw:
        return []
    return [s.strip() for s in str(raw).split("+") if s.strip()]


def sprayer_equipment_id(farm: str, sprayer_name: str) -> tuple[str | None, str | None]:
    """Returns (equipment_id, type) for a sprayer name. None, None if unknown."""
    key = sprayer_name.strip().lower()
    if key in SPRAYER_MAP:
        suffix, eq_type = SPRAYER_MAP[key]
        return f"{farm}_{suffix}", eq_type
    # Unknown sprayer — return None to skip equipment creation
    return None, None


# ---------------------------------------------------------------------------
# Setup: invnt_item, equipment, compliance
# ---------------------------------------------------------------------------

def build_item_lookup(supabase, sheet_records):
    """Return dict (farm, name_lower) -> invnt_item.id. Auto-creates missing."""
    existing = paginate_select(supabase, "invnt_item", "id,name,farm_id,invnt_category_id")
    by_farm_name = {}
    for it in existing:
        by_farm_name[(it["farm_id"], it["name"].lower())] = it["id"]
        # Also record farm-agnostic match for lookup flexibility
        by_farm_name.setdefault((None, it["name"].lower()), it["id"])

    # Collect unique (farm, product_name) pairs in sheet
    needed = {}  # (farm, name) -> {name_display}
    for r in sheet_records:
        farm = resolve_farm(r.get("Farm", ""))
        if not farm:
            continue
        for i in (1, 2, 3):
            name = str(r.get(f"Product0{i}", "")).strip()
            if not name:
                continue
            if (farm, name.lower()) in by_farm_name:
                continue
            # Not farm-scoped. Is there a farm-agnostic match?
            agnostic = by_farm_name.get((None, name.lower()))
            if agnostic:
                by_farm_name[(farm, name.lower())] = agnostic
                continue
            # Needs auto-create
            key = (farm, name.lower())
            if key not in needed:
                needed[key] = {"name": name, "farm": farm}

    if not needed:
        return by_farm_name

    # Build rows; generate unique IDs
    used_ids = set(by_farm_name.values())
    rows = []
    for (farm, _), spec in needed.items():
        base_id = to_id(spec["name"])
        final_id = base_id
        n = 2
        while final_id in used_ids:
            final_id = f"{base_id}_{n}"
            n += 1
        used_ids.add(final_id)
        by_farm_name[(farm, spec["name"].lower())] = final_id
        rows.append({
            "id": final_id,
            "org_id": ORG_ID,
            "farm_id": farm,
            "invnt_category_id": PESTICIDE_CATEGORY_ID,
            "name": spec["name"],
            "qb_account": "1. Growing:Chemicals/Pesticides",
            "description": None,
            "burn_uom": "fluid_ounce",
            "onhand_uom": "fluid_ounce",
            "order_uom": "fluid_ounce",
            "burn_per_onhand": 1,
            "burn_per_order": 1,
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
            "seed_is_pelleted": False,
            "photos": [],
            "is_active": True,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    print(f"\n--- invnt_item (auto-create missing chemicals) ---")
    for i in range(0, len(rows), 100):
        supabase.table("invnt_item").upsert(rows[i:i + 100]).execute()
    print(f"  Upserted {len(rows)} rows: {[r['id'] for r in rows]}")

    return by_farm_name


def ensure_sprayer_equipment(supabase, sheet_records):
    """Upsert org_equipment rows for every (farm, sprayer) pair in sheet."""
    needed = {}  # equipment_id -> {farm, name, type}
    for r in sheet_records:
        farm = resolve_farm(r.get("Farm", ""))
        if not farm:
            continue
        sprayer_raw = str(r.get("Sprayer", "")).strip()
        for sprayer_name in split_sprayers(sprayer_raw):
            eid, etype = sprayer_equipment_id(farm, sprayer_name)
            if not eid:
                continue
            if eid in needed:
                continue
            needed[eid] = {
                "farm": farm,
                "name": f"{farm.title()} {sprayer_name}",
                "type": etype,
            }

    if not needed:
        print("  No sprayer equipment to upsert")
        return

    rows = []
    for eid, spec in needed.items():
        rows.append({
            "id": eid,
            "org_id": ORG_ID,
            "farm_id": spec["farm"],
            "name": spec["name"],
            "type": spec["type"],
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })
    print(f"\n--- org_equipment (sprayers) ---")
    supabase.table("org_equipment").upsert(rows).execute()
    print(f"  Upserted {len(rows)} sprayer equipment rows")


def ensure_compliance_records(supabase, sheet_records, item_lookup):
    """Return dict (farm, item_id) -> compliance_id. Auto-creates missing.

    For each (farm, product) referenced in sheet but not in grow_spray_compliance,
    create a row using PHI/REI and target/UOM from the first sheet row where it
    appears.
    """
    existing = paginate_select(supabase, "grow_spray_compliance", "id,farm_id,invnt_item_id")
    by_pair = {(c["farm_id"], c["invnt_item_id"]): c["id"] for c in existing}

    # For each (farm, item_id) needed, grab PHI/REI/target/uom from first sheet row
    needed = {}  # (farm, item_id) -> defaults
    for r in sheet_records:
        farm = resolve_farm(r.get("Farm", ""))
        if not farm:
            continue
        for i in (1, 2, 3):
            name = str(r.get(f"Product0{i}", "")).strip()
            if not name:
                continue
            item_id = item_lookup.get((farm, name.lower()))
            if not item_id:
                continue
            if (farm, item_id) in by_pair:
                continue
            if (farm, item_id) in needed:
                continue

            phi = parse_int(r.get("PHIDays"), default=0) or 0
            rei = parse_int(r.get("REIlHours"), default=0) or 0
            targets = split_targets(r.get(f"Product0{i}Target"))
            uom = normalize_uom(r.get(f"Product0{i}Units")) or "fluid_ounce"
            qty_per_acre = parse_numeric(r.get(f"Product0{i}Quantity"), default=-1) or -1

            needed[(farm, item_id)] = {
                "phi": phi,
                "rei": rei,
                "targets": targets,
                "uom": uom,
                "max_qty_per_acre": qty_per_acre,
            }

    if not needed:
        return by_pair

    rows = []
    today = date.today().isoformat()
    for (farm, item_id), d in needed.items():
        new_id = str(uuid.uuid4())
        by_pair[(farm, item_id)] = new_id
        rows.append({
            "id": new_id,
            "org_id": ORG_ID,
            "farm_id": farm,
            "invnt_item_id": item_id,
            "epa_registration": "LEGACY_UNKNOWN",
            "phi_days": d["phi"],
            "rei_hours": d["rei"],
            "application_method": json.dumps([]),
            "target_pest_disease": json.dumps(d["targets"]),
            "application_uom": d["uom"],
            "maximum_quantity_per_acre": d["max_qty_per_acre"],
            "burn_uom": d["uom"],
            "application_per_burn": 1,
            "label_date": today,
            "effective_date": today,
            "expiration_date": None,
            "external_label_url": "LEGACY_MIGRATION",
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    print(f"\n--- grow_spray_compliance (auto-create missing) ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_spray_compliance", rows)
        conn.commit()
    print(f"  Inserted {len(rows)} compliance rows")

    return by_pair


# ---------------------------------------------------------------------------
# Clear existing legacy rows for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    """Delete previously-migrated spray events (identified by notes marker)."""
    print("\nClearing existing legacy spray rows...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                DELETE FROM grow_spray_input
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_id = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d1 = cur.rowcount
            cur.execute(
                """
                DELETE FROM grow_spray_equipment
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_id = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d2 = cur.rowcount
            cur.execute(
                """
                DELETE FROM ops_task_tracker
                WHERE ops_task_id = %s AND notes LIKE %s
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d3 = cur.rowcount
        conn.commit()
    print(f"  Deleted: {d1} grow_spray_input, {d2} grow_spray_equipment, {d3} ops_task_tracker")


# ---------------------------------------------------------------------------
# Row transform
# ---------------------------------------------------------------------------

def build_event_rows(
    sheet_row, known_sites, item_lookup, compliance_lookup,
):
    """Return dict with tracker + lists of inputs/equipment, or {'_skip': reason}."""
    farm = resolve_farm(sheet_row.get("Farm", ""))
    if not farm:
        return {"_skip": "no_farm"}

    spray_date = parse_date(sheet_row.get("SprayingDate"))
    if not spray_date:
        return {"_skip": "no_date"}

    site_id = normalize_site(sheet_row.get("SiteName", ""))
    if not site_id or site_id not in known_sites:
        return {"_skip": "unknown_site", "_detail": site_id}

    start_time_only = parse_time(sheet_row.get("SprayingStartTime"))
    stop_time_only = parse_time(sheet_row.get("SprayingStopTime"))
    scheduled_dt = parse_datetime(sheet_row.get("ScheduledDateTime"))

    start_dt = (
        datetime.combine(spray_date, start_time_only) if start_time_only
        else (scheduled_dt if scheduled_dt else datetime.combine(spray_date, datetime.min.time()))
    )
    stop_dt = (
        datetime.combine(spray_date, stop_time_only) if stop_time_only
        else None
    )

    applicator = str(sheet_row.get("Applicator", "")).strip()
    warning = str(sheet_row.get("Warning", "")).strip()
    action_req = str(sheet_row.get("ActionRequired", "")).strip()
    precheck = str(sheet_row.get("PreCheckCompleted", "")).strip()

    note_parts = []
    if applicator:
        note_parts.append(f"Applicator: {applicator}")
    if warning:
        note_parts.append(f"Warning: {warning}")
    if action_req:
        note_parts.append(f"ActionRequired: {action_req}")
    if precheck.upper() == "TRUE":
        note_parts.append("PreCheckCompleted: TRUE")
    note_parts.append(NOTES_MARKER)
    notes = " | ".join(note_parts)

    scheduled_by_raw = str(sheet_row.get("ScheduledBy", "")).strip().lower()
    created_by = scheduled_by_raw if "@" in scheduled_by_raw else AUDIT_USER

    tracker_id = str(uuid.uuid4())
    tracker = {
        "id": tracker_id,
        "org_id": ORG_ID,
        "farm_id": farm,
        "site_id": site_id,
        "ops_task_id": OPS_TASK_ID,
        "start_time": start_dt.isoformat(),
        "stop_time": stop_dt.isoformat() if stop_dt else None,
        "is_completed": stop_dt is not None,
        "notes": notes,
        "created_by": created_by,
        "updated_by": created_by,
    }

    # Build grow_spray_input rows (1-3)
    inputs = []
    input_skip_reasons = []
    for i in (1, 2, 3):
        name = str(sheet_row.get(f"Product0{i}", "")).strip()
        if not name:
            continue
        item_id = item_lookup.get((farm, name.lower()))
        if not item_id:
            input_skip_reasons.append(f"no_item:{name}")
            continue
        compliance_id = compliance_lookup.get((farm, item_id))
        if not compliance_id:
            input_skip_reasons.append(f"no_compliance:{name}")
            continue
        uom = normalize_uom(sheet_row.get(f"Product0{i}Units")) or "fluid_ounce"
        qty = parse_numeric(sheet_row.get(f"Product0{i}Quantity"), default=0) or 0
        targets = split_targets(sheet_row.get(f"Product0{i}Target"))

        inputs.append({
            "org_id": ORG_ID,
            "farm_id": farm,
            "ops_task_tracker_id": tracker_id,
            "grow_spray_compliance_id": compliance_id,
            "invnt_item_id": item_id,
            "invnt_lot_id": None,
            "target_pest_disease": json.dumps(targets),
            "application_uom": uom,
            "application_quantity": qty,
            "created_by": created_by,
            "updated_by": created_by,
        })

    # Build grow_spray_equipment rows (0-N)
    water_total = parse_numeric(sheet_row.get("WaterGallons"), default=0) or 0
    sprayer_raw = str(sheet_row.get("Sprayer", "")).strip()
    equipment_rows = []

    if sprayer_raw:
        sprayers = split_sprayers(sprayer_raw)
        # Split water evenly across sprayers
        water_per = (water_total / len(sprayers)) if water_total > 0 and sprayers else 0
        for sname in sprayers:
            eid, _ = sprayer_equipment_id(farm, sname)
            if not eid:
                # Unknown sprayer name — fall back to equipment_id=NULL
                equipment_rows.append({
                    "org_id": ORG_ID,
                    "farm_id": farm,
                    "ops_task_tracker_id": tracker_id,
                    "equipment_id": None,
                    "water_uom": "gallon",
                    "water_quantity": water_per,
                    "created_by": created_by,
                    "updated_by": created_by,
                })
            else:
                equipment_rows.append({
                    "org_id": ORG_ID,
                    "farm_id": farm,
                    "ops_task_tracker_id": tracker_id,
                    "equipment_id": eid,
                    "water_uom": "gallon",
                    "water_quantity": water_per,
                    "created_by": created_by,
                    "updated_by": created_by,
                })
    elif water_total > 0:
        # Legacy record: water recorded without sprayer — use NULL equipment
        equipment_rows.append({
            "org_id": ORG_ID,
            "farm_id": farm,
            "ops_task_tracker_id": tracker_id,
            "equipment_id": None,
            "water_uom": "gallon",
            "water_quantity": water_total,
            "created_by": created_by,
            "updated_by": created_by,
        })

    return {
        "tracker": tracker,
        "inputs": inputs,
        "equipment": equipment_rows,
        "input_skips": input_skip_reasons,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW SPRAYING MIGRATION")
    print("=" * 60)

    clear_existing()

    # Load known sites for spraying (all cuke/lettuce sites where plants grow)
    sites = paginate_select(supabase, "org_site", "id,farm_id,org_site_subcategory_id")
    known_sites = {
        s["id"] for s in sites
        if s.get("farm_id") in ("cuke", "lettuce")
        and s.get("org_site_subcategory_id") in ("greenhouse", "pond", None)
    }
    print(f"\n  Known cuke/lettuce sites: {len(known_sites)}")

    wb = gc.open_by_key(GROW_SHEET_ID)
    print("\nReading grow_spray_sched...")
    records = wb.worksheet("grow_spray_sched").get_all_records()
    print(f"  {len(records)} sheet rows")

    # Setup: items, equipment, compliance
    item_lookup = build_item_lookup(supabase, records)
    ensure_sprayer_equipment(supabase, records)
    compliance_lookup = ensure_compliance_records(supabase, records, item_lookup)

    # Build event rows
    trackers = []
    inputs = []
    equipment = []
    skip_counts = {}
    input_skip_counts = {}

    for r in records:
        result = build_event_rows(r, known_sites, item_lookup, compliance_lookup)
        if "_skip" in result:
            reason = result["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            continue
        trackers.append(result["tracker"])
        inputs.extend(result["inputs"])
        equipment.extend(result["equipment"])
        for r2 in result["input_skips"]:
            key = r2.split(":")[0]
            input_skip_counts[key] = input_skip_counts.get(key, 0) + 1

    print(f"\n  Built {len(trackers)} trackers, {len(inputs)} inputs, {len(equipment)} equipment rows")
    for reason, cnt in sorted(skip_counts.items()):
        print(f"  Skipped {cnt} rows: {reason}")
    for reason, cnt in sorted(input_skip_counts.items()):
        print(f"  Skipped {cnt} input slots: {reason}")

    # Bulk insert via psycopg2
    with get_pg_conn() as conn:
        print(f"\n--- ops_task_tracker ---")
        pg_bulk_insert(conn, "ops_task_tracker", trackers)
        print(f"  Inserted {len(trackers)} rows")
        print(f"\n--- grow_spray_input ---")
        pg_bulk_insert(conn, "grow_spray_input", inputs)
        print(f"  Inserted {len(inputs)} rows")
        print(f"\n--- grow_spray_equipment ---")
        pg_bulk_insert(conn, "grow_spray_equipment", equipment)
        print(f"  Inserted {len(equipment)} rows")
        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
