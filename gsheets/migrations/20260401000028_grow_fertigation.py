"""
Migrate Fertigation Recipes + Applications
===========================================
Two sheets into four tables.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_fert_recipe_mix (~487 rows) -> grow_fertigation_recipe + grow_fertigation_recipe_item
  - grow_fert_sched (~1,329 rows)    -> grow_fertigation_recipe_site + ops_task_tracker + grow_fertigation

Setup (upserted):
  - 8 org_equipment tanks: {lettuce,cuke}_tank_{a,b,c,d} (type='tank')
  - invnt_item auto-create for unknown FertilizerName (category=fertilizers)

Recipes (from grow_fert_recipe_mix + any orphan recipe names in sched):
  - grow_fertigation_recipe: one per unique RecipeName (farm determined by sched usage)
  - grow_fertigation_recipe_item: one per recipe_mix row
      equipment_id = {farm}_tank_{letter} from sheet Tank (NULL for water recipes with blank Tank)

Applications (from grow_fert_sched):
  Each row fans out over concatenated sites (P2+P3+P4 -> 3 trackers).
  - grow_fertigation_recipe_site: unique (recipe, site) pairs
  - ops_task_tracker: one per (row, site), ops_task_id='fertigation'
  - grow_fertigation (per tracker):
      - one per tank with gallons > 0 (uom=gallon, equipment={farm}_tank_{letter})
      - one if TopUpWaterHours > 0 (uom=hour, equipment=NULL, recipe=Top Up Water (Hours))
      - one if FlushWaterGallons > 0 (uom=gallon, equipment=NULL, recipe=Flush Water (Gallons))

Name normalizations in sched RecipeName:
  - "Top Up Water (Hours) (Hours)" -> "Top Up Water (Hours)"
  - "Water" (lone, ambiguous) -> "Top Up Water (Hours)"

Rerunnable: all our rows carry the notes/description marker
"Legacy fertigation migration" and are deleted before reinsert.

Usage:
    python migrations/20260401000029_grow_fertigation.py
"""

import re
import sys
import uuid
from datetime import datetime
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
from gsheets.migrations._pg import get_pg_conn, paginate_select, pg_bulk_insert

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
NOTES_MARKER = "Legacy fertigation migration"

OPS_TASK_ID = "fertigation"
FERTILIZER_CATEGORY_ID = "fertilizers"

# Sheet Units -> sys_uom.code
UOM_MAP = {
    "gram": "gram", "grams": "gram", "g": "gram",
    "ounce": "ounce", "ounces": "ounce", "oz": "ounce",
    "pound": "pound", "pounds": "pound", "lb": "pound", "lbs": "pound",
    "gallon": "gallon", "gallons": "gallon", "gal": "gallon",
    "liter": "liter", "liters": "liter", "l": "liter",
    "milliliter": "milliliter", "milliliters": "milliliter", "ml": "milliliter",
    "kilogram": "kilogram", "kilograms": "kilogram", "kg": "kilogram",
    "hour": "hour", "hours": "hour", "hr": "hour", "hrs": "hour",
    "fluid_ounce": "fluid_ounce", "fl oz": "fluid_ounce",
}

# Sheet RecipeName typos/normalizations
RECIPE_NAME_NORMALIZATIONS = {
    "Top Up Water (Hours) (Hours)": "Top Up Water (Hours)",
    "Water": "Top Up Water (Hours)",  # single ambiguous row has TopUpWaterHours>0
}

# Canonical water recipe names (already in recipe_mix sheet)
TOP_UP_WATER_RECIPE = "Top Up Water (Hours)"
FLUSH_WATER_RECIPE = "Flush Water (Gallons)"


# ---------------------------------------------------------------------------
# Helpers
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


def parse_datetime(val):
    """Parse a timestamp like '2/4/2024 18:17:27'. Returns a datetime or None."""
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in (
        "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M",
        "%m/%d/%y %H:%M:%S", "%m/%d/%y %H:%M",
        "%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d",
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


def normalize_uom(raw: str) -> str | None:
    if not raw:
        return None
    key = str(raw).strip().lower()
    return UOM_MAP.get(key)


def normalize_recipe_name(raw: str) -> str:
    """Apply typo corrections to a sheet RecipeName."""
    s = str(raw).strip()
    return RECIPE_NAME_NORMALIZATIONS.get(s, s)


def resolve_farm(raw: str) -> str | None:
    """'Lettuce' -> 'lettuce', 'Cuke' -> 'cuke'. Return None if unrecognized."""
    s = str(raw).strip().lower()
    if s in ("lettuce", "cuke"):
        return s
    return None


def resolve_user(raw: str) -> str:
    s = str(raw).strip().lower()
    return s if "@" in s else AUDIT_USER


def split_sites(site_name: str) -> list[str]:
    """'P2+P3+P4' -> ['p2', 'p3', 'p4']. Single 'P1' -> ['p1']."""
    if not site_name:
        return []
    parts = [p.strip().lower() for p in str(site_name).split("+")]
    return [p for p in parts if p]


def tank_equipment_id(farm: str, tank_letter: str) -> str | None:
    """'lettuce' + 'A' -> 'lettuce_tank_a'. Returns None for blank tank."""
    letter = str(tank_letter).strip().lower()
    if not letter:
        return None
    return f"{farm}_tank_{letter}"


# ---------------------------------------------------------------------------
# Setup: tanks, items, recipes, recipe_items, recipe_sites
# ---------------------------------------------------------------------------

def ensure_tanks(supabase):
    """Upsert 8 tank rows in org_equipment: lettuce_tank_{a,b,c,d} + cuke_tank_{a,b,c,d}."""
    print("\n--- org_equipment (tanks) ---")
    rows = []
    for farm in ("lettuce", "cuke"):
        for letter in ("a", "b", "c", "d"):
            rows.append({
                "id": f"{farm}_tank_{letter}",
                "org_id": ORG_ID,
                "farm_id": farm,
                "name": f"{farm.title()} Tank {letter.upper()}",
                "type": "tank",
                "created_by": AUDIT_USER,
                "updated_by": AUDIT_USER,
            })
    supabase.table("org_equipment").upsert(rows).execute()
    print(f"  Upserted {len(rows)} tanks: {[r['id'] for r in rows]}")


def ensure_items(supabase, recipe_mix_records):
    """Auto-create missing invnt_item for every unique FertilizerName.

    Returns dict: name_lower -> invnt_item.id
    """
    # Load ALL existing items (not just fertilizers — fertilizers may have been
    # categorized as chemicals_pesticides or other categories).
    existing = paginate_select(supabase, "invnt_item", "id,name,farm_id,invnt_category_id")
    by_name_lower = {}
    for it in existing:
        key = it["name"].lower()
        # Prefer fertilizer items when there's a duplicate name across categories
        if key in by_name_lower:
            if it.get("invnt_category_id") == FERTILIZER_CATEGORY_ID:
                by_name_lower[key] = it["id"]
        else:
            by_name_lower[key] = it["id"]

    # Find fertilizer names we need to create
    unique_names = set()
    for r in recipe_mix_records:
        name = str(r.get("FertilizerName", "")).strip()
        if name and name.lower() != "water":  # water is handled separately
            unique_names.add(name)

    to_create = {}
    for name in unique_names:
        if name.lower() not in by_name_lower:
            to_create[name] = to_id(name)

    # Resolve collisions in generated IDs (two names might slug to the same id)
    used_ids = set(by_name_lower.values())
    rows = []
    for name, base_id in list(to_create.items()):
        final_id = base_id
        n = 2
        while final_id in used_ids:
            final_id = f"{base_id}_{n}"
            n += 1
        used_ids.add(final_id)
        by_name_lower[name.lower()] = final_id
        # Without a known farm, default to 'lettuce' since most fertigation is lettuce.
        # (Will be refined via recipe_item farm when inserted.)
        rows.append({
            "id": final_id,
            "org_id": ORG_ID,
            "farm_id": "lettuce",
            "invnt_category_id": FERTILIZER_CATEGORY_ID,
            "name": name,
            "qb_account": "1. Growing:Fertilizers",
            "description": None,
            "burn_uom": "pound",
            "onhand_uom": "pound",
            "order_uom": "pound",
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

    if rows:
        print(f"\n--- invnt_item (auto-create fertilizers) ---")
        # Insert in PostgREST batches of 100 via supabase-py upsert
        for i in range(0, len(rows), 100):
            supabase.table("invnt_item").upsert(rows[i:i + 100]).execute()
        print(f"  Upserted {len(rows)} rows")
    else:
        print(f"\n  All fertilizer names already in invnt_item")

    return by_name_lower


def build_recipe_farm_map(sched_records, recipe_mix_names):
    """Determine each recipe's farm from sched sheet usage.

    Returns dict: recipe_name -> farm_id (lowercase 'lettuce' or 'cuke').
    Falls back to 'lettuce' for recipes never in sched.
    """
    from collections import Counter
    recipe_farm_counts = {}
    for r in sched_records:
        name = normalize_recipe_name(r.get("RecipeName", ""))
        farm = resolve_farm(r.get("Farm", ""))
        if not name or not farm:
            continue
        recipe_farm_counts.setdefault(name, Counter())[farm] += 1

    # Pick the most common farm per recipe
    recipe_farm = {}
    for name, counts in recipe_farm_counts.items():
        recipe_farm[name] = counts.most_common(1)[0][0]

    # Recipes in recipe_mix but never in sched -> default to lettuce
    for name in recipe_mix_names:
        if name not in recipe_farm:
            recipe_farm[name] = "lettuce"

    return recipe_farm


def ensure_recipes(supabase, recipe_mix_records, sched_records):
    """Create grow_fertigation_recipe rows. Union of recipe_mix + sched RecipeNames.

    Returns: (recipe_id_by_name dict, recipe_farm dict)
    """
    # Union of all recipe names
    recipe_names = set()
    for r in recipe_mix_records:
        name = str(r.get("RecipeName", "")).strip()
        if name:
            recipe_names.add(name)
    for r in sched_records:
        name = normalize_recipe_name(r.get("RecipeName", ""))
        if name:
            recipe_names.add(name)

    recipe_farm = build_recipe_farm_map(sched_records, recipe_names)

    # Build recipe rows; ID is a slug of the name
    recipe_id_by_name = {}
    used_ids = set()
    rows = []
    for name in sorted(recipe_names):
        base_id = to_id(name)
        if not base_id:
            continue
        final_id = base_id
        n = 2
        while final_id in used_ids:
            final_id = f"{base_id}_{n}"
            n += 1
        used_ids.add(final_id)
        recipe_id_by_name[name] = final_id
        rows.append({
            "id": final_id,
            "org_id": ORG_ID,
            "farm_id": recipe_farm[name],
            "name": name,
            "description": NOTES_MARKER,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    print(f"\n--- grow_fertigation_recipe ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_fertigation_recipe", rows)
        conn.commit()
    print(f"  Inserted {len(rows)} recipes")
    return recipe_id_by_name, recipe_farm


def build_recipe_items(recipe_mix_records, recipe_id_by_name, recipe_farm, item_by_name_lower):
    """Return list of grow_fertigation_recipe_item dicts to bulk-insert."""
    rows = []
    skipped = {"no_recipe": 0, "no_name": 0, "bad_uom": 0, "no_quantity": 0}
    for r in recipe_mix_records:
        recipe_name = str(r.get("RecipeName", "")).strip()
        if not recipe_name or recipe_name not in recipe_id_by_name:
            skipped["no_recipe"] += 1
            continue
        fert_name = str(r.get("FertilizerName", "")).strip()
        if not fert_name:
            skipped["no_name"] += 1
            continue
        uom = normalize_uom(r.get("Units"))
        if not uom:
            skipped["bad_uom"] += 1
            continue
        qty = parse_numeric(r.get("Quantity"))
        if qty is None:
            skipped["no_quantity"] += 1
            continue

        tank_letter = str(r.get("Tank", "")).strip()
        farm = recipe_farm[recipe_name]
        equipment_id = tank_equipment_id(farm, tank_letter)
        invnt_item_id = item_by_name_lower.get(fert_name.lower())
        notes = str(r.get("Notes", "")).strip() or None

        rows.append({
            "org_id": ORG_ID,
            "farm_id": farm,
            "grow_fertigation_recipe_id": recipe_id_by_name[recipe_name],
            "equipment_id": equipment_id,
            "invnt_item_id": invnt_item_id,
            "item_name": fert_name,
            "application_uom": uom,
            "application_quantity": qty,
            "burn_uom": None,
            "application_per_burn": None,
            "notes": notes,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    return rows, skipped


def build_recipe_sites(sched_records, recipe_id_by_name, known_sites):
    """Return list of grow_fertigation_recipe_site dicts (unique recipe, site)."""
    from collections import OrderedDict
    seen = OrderedDict()  # (recipe_id, site_id) -> row
    for r in sched_records:
        name = normalize_recipe_name(r.get("RecipeName", ""))
        if not name or name not in recipe_id_by_name:
            continue
        farm = resolve_farm(r.get("Farm", ""))
        if not farm:
            continue
        recipe_id = recipe_id_by_name[name]
        for site_id in split_sites(r.get("SiteName", "")):
            if site_id not in known_sites:
                continue
            key = (recipe_id, site_id)
            if key in seen:
                continue
            seen[key] = {
                "org_id": ORG_ID,
                "farm_id": farm,
                "grow_fertigation_recipe_id": recipe_id,
                "site_id": site_id,
                "created_by": AUDIT_USER,
                "updated_by": AUDIT_USER,
            }
    return list(seen.values())


# ---------------------------------------------------------------------------
# Events: trackers + grow_fertigation
# ---------------------------------------------------------------------------

def build_events(sched_records, recipe_id_by_name, known_sites):
    """Fan out sched rows into ops_task_tracker + grow_fertigation records.

    Returns: (trackers, fertigations, skip_counts)
    """
    trackers = []
    fertigations = []
    skip_counts = {}

    top_up_recipe_id = recipe_id_by_name.get(TOP_UP_WATER_RECIPE)
    flush_recipe_id = recipe_id_by_name.get(FLUSH_WATER_RECIPE)

    for r in sched_records:
        recipe_name = normalize_recipe_name(r.get("RecipeName", ""))
        if not recipe_name or recipe_name not in recipe_id_by_name:
            skip_counts["no_recipe"] = skip_counts.get("no_recipe", 0) + 1
            continue

        farm = resolve_farm(r.get("Farm", ""))
        if not farm:
            skip_counts["no_farm"] = skip_counts.get("no_farm", 0) + 1
            continue

        sites = split_sites(r.get("SiteName", ""))
        sites = [s for s in sites if s in known_sites]
        if not sites:
            skip_counts["no_site"] = skip_counts.get("no_site", 0) + 1
            continue

        start_time = parse_datetime(r.get("ScheduledDateTime"))
        stop_time = parse_datetime(r.get("CompletedDateTime"))
        mix_date = parse_datetime(r.get("MixDate"))

        # start_time is NOT NULL — fall back to MixDate, then CompletedDateTime
        effective_start = start_time or mix_date or stop_time
        if not effective_start:
            skip_counts["no_datetime"] = skip_counts.get("no_datetime", 0) + 1
            continue

        is_completed = stop_time is not None
        scheduled_by = resolve_user(r.get("ScheduledBy", ""))
        completed_by = resolve_user(r.get("CompletedBy", ""))
        reporter = completed_by if is_completed and completed_by != AUDIT_USER else scheduled_by

        recipe_id = recipe_id_by_name[recipe_name]

        # Parse the 4 tank gallons + water values
        tank_values = {}
        for letter in ("a", "b", "c", "d"):
            v = parse_numeric(r.get(f"GallonsTank{letter.upper()}"))
            if v and v > 0:
                tank_values[letter] = v
        top_up_hours = parse_numeric(r.get("TopUpWaterHours"))
        flush_gallons = parse_numeric(r.get("FlushWaterGallons"))

        # Fan out over sites — one tracker + its fertigation rows per site
        for site_id in sites:
            tracker_id = str(uuid.uuid4())
            trackers.append({
                "id": tracker_id,
                "org_id": ORG_ID,
                "farm_id": farm,
                "site_id": site_id,
                "ops_task_id": OPS_TASK_ID,
                "start_time": effective_start.isoformat(),
                "stop_time": stop_time.isoformat() if stop_time else None,
                "is_completed": is_completed,
                "notes": NOTES_MARKER,
                "created_by": reporter,
                "updated_by": reporter,
            })

            # One grow_fertigation per tank used
            for letter, gallons in tank_values.items():
                fertigations.append({
                    "org_id": ORG_ID,
                    "farm_id": farm,
                    "ops_task_tracker_id": tracker_id,
                    "grow_fertigation_recipe_id": recipe_id,
                    "equipment_id": tank_equipment_id(farm, letter),
                    "volume_uom": "gallon",
                    "volume_applied": gallons,
                    "created_by": reporter,
                    "updated_by": reporter,
                })

            # Water add-ons (always equipment_id = NULL, separate recipes)
            if top_up_hours and top_up_hours > 0 and top_up_recipe_id:
                fertigations.append({
                    "org_id": ORG_ID,
                    "farm_id": farm,
                    "ops_task_tracker_id": tracker_id,
                    "grow_fertigation_recipe_id": top_up_recipe_id,
                    "equipment_id": None,
                    "volume_uom": "hour",
                    "volume_applied": top_up_hours,
                    "created_by": reporter,
                    "updated_by": reporter,
                })
            if flush_gallons and flush_gallons > 0 and flush_recipe_id:
                fertigations.append({
                    "org_id": ORG_ID,
                    "farm_id": farm,
                    "ops_task_tracker_id": tracker_id,
                    "grow_fertigation_recipe_id": flush_recipe_id,
                    "equipment_id": None,
                    "volume_uom": "gallon",
                    "volume_applied": flush_gallons,
                    "created_by": reporter,
                    "updated_by": reporter,
                })

    return trackers, fertigations, skip_counts


# ---------------------------------------------------------------------------
# Clear existing rows for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    """Delete our previously-migrated fertigation rows (via notes/description marker)."""
    print("\nClearing existing legacy fertigation rows...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            # 1. Delete grow_fertigation rows linked to our trackers
            cur.execute(
                """
                DELETE FROM grow_fertigation
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_id = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d1 = cur.rowcount
            # 2. Delete our trackers
            cur.execute(
                """
                DELETE FROM ops_task_tracker
                WHERE ops_task_id = %s AND notes LIKE %s
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d2 = cur.rowcount
            # 3. Delete recipe_site rows for our recipes
            cur.execute(
                """
                DELETE FROM grow_fertigation_recipe_site
                WHERE grow_fertigation_recipe_id IN (
                    SELECT id FROM grow_fertigation_recipe
                    WHERE description = %s
                )
                """,
                (NOTES_MARKER,),
            )
            d3 = cur.rowcount
            # 4. Delete recipe_item rows for our recipes
            cur.execute(
                """
                DELETE FROM grow_fertigation_recipe_item
                WHERE grow_fertigation_recipe_id IN (
                    SELECT id FROM grow_fertigation_recipe
                    WHERE description = %s
                )
                """,
                (NOTES_MARKER,),
            )
            d4 = cur.rowcount
            # 5. Delete our recipes
            cur.execute(
                "DELETE FROM grow_fertigation_recipe WHERE description = %s",
                (NOTES_MARKER,),
            )
            d5 = cur.rowcount
        conn.commit()
    print(f"  Deleted: {d1} grow_fertigation, {d2} ops_task_tracker, "
          f"{d3} recipe_site, {d4} recipe_item, {d5} grow_fertigation_recipe")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW FERTIGATION MIGRATION")
    print("=" * 60)

    clear_existing()

    # Load known pond sites (both farms)
    sites = paginate_select(
        supabase, "org_site", "id,farm_id",
        eq_filters={"org_site_subcategory_id": "pond"},
    )
    known_sites = {s["id"]: s["farm_id"] for s in sites}
    # Also include cuke greenhouse sites for cuke fertigation events
    cuke_gh = paginate_select(
        supabase, "org_site", "id,farm_id",
        eq_filters={"farm_id": "cuke", "org_site_subcategory_id": "greenhouse"},
    )
    for s in cuke_gh:
        known_sites[s["id"]] = s["farm_id"]
    print(f"\n  Known sites: {len(known_sites)} (ponds + cuke greenhouses)")

    wb = gc.open_by_key(GROW_SHEET_ID)
    print("\nReading grow_fert_recipe_mix...")
    recipe_mix = wb.worksheet("grow_fert_recipe_mix").get_all_records()
    print(f"  {len(recipe_mix)} rows")

    print("Reading grow_fert_sched...")
    sched = wb.worksheet("grow_fert_sched").get_all_records()
    print(f"  {len(sched)} rows")

    ensure_tanks(supabase)
    item_by_name_lower = ensure_items(supabase, recipe_mix)
    recipe_id_by_name, recipe_farm = ensure_recipes(supabase, recipe_mix, sched)

    # Build and insert recipe_items
    recipe_items, item_skips = build_recipe_items(
        recipe_mix, recipe_id_by_name, recipe_farm, item_by_name_lower,
    )
    print(f"\n--- grow_fertigation_recipe_item ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_fertigation_recipe_item", recipe_items)
        conn.commit()
    print(f"  Inserted {len(recipe_items)} items")
    for reason, n in item_skips.items():
        if n:
            print(f"  Skipped {n}: {reason}")

    # Build and insert recipe_site links
    recipe_sites = build_recipe_sites(sched, recipe_id_by_name, known_sites)
    print(f"\n--- grow_fertigation_recipe_site ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_fertigation_recipe_site", recipe_sites)
        conn.commit()
    print(f"  Inserted {len(recipe_sites)} site links")

    # Build and insert events (trackers + grow_fertigation)
    trackers, fertigations, skip_counts = build_events(sched, recipe_id_by_name, known_sites)
    print(f"\n  Built {len(trackers)} trackers, {len(fertigations)} fertigation rows")
    for reason, n in sorted(skip_counts.items()):
        print(f"  Skipped {n} sched rows: {reason}")

    print(f"\n--- ops_task_tracker ---")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "ops_task_tracker", trackers)
        print(f"  Inserted {len(trackers)} rows")
        print(f"\n--- grow_fertigation ---")
        pg_bulk_insert(conn, "grow_fertigation", fertigations)
        print(f"  Inserted {len(fertigations)} rows")
        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
