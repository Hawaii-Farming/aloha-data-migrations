"""
Seed Cuke Plant-Map Static Tables (ONE-TIME)
============================================
Populates the five new cuke layout tables and migrates the 660 cuke rows
from grow_lettuce_seed_batch (formerly grow_seed_batch) into the new
grow_cuke_seed_batch. After this script runs, the cuke seeding sync from
the grow_C_seeding Google Sheet (`20260401000024_grow_cuke_seeding.py`)
is retired — cuke seed batches become static with no ongoing nightly
rebuild.

Tables populated:
  - org_site_cuke_gh               (~12 rows, from GH_CONFIG mirror below)
  - org_site_cuke_gh_block         (~25 rows, derived from plant-map sheet
                               Greenhouse + Side groupings)
  - org_site_cuke_gh_row           (~660 rows, one per physical GH row)
  - grow_cuke_gh_row_planting (~1320 rows, current + planned per row)
  - grow_cuke_seed_batch      (660 rows, copied from grow_lettuce_seed_batch
                               with preserved UUIDs)

Sources:
  - GH_CONFIG constant mirrored from dash/plant-map/index.html
  - Plant-map Google Sheet
    https://docs.google.com/spreadsheets/d/1ewWyvaXGkRCvZxjUxBOHGY4PKdMHwKeTA5jTIod48LE
    gid=1615707612

Expected order of operations (see sql/schema/):
  1. Apply 20260417000001..006 via SQL Editor (creates new tables; renames
     grow_seed_batch to grow_lettuce_seed_batch).
  2. Run this script. It populates the layout tables and copies cuke rows
     to grow_cuke_seed_batch (preserving UUIDs).
  3. Apply 20260417000007 and ...008 (splits grow_harvest_weight and
     grow_task_seed_batch FKs, moves cuke UUIDs onto new columns).
  4. Apply 20260417000009 (deletes cuke rows from grow_lettuce_seed_batch).

Retiring the cuke sheet sync:
  - `_run_nightly.py` drops `"024"` from DEFAULT_SET.
  - `20260401000024_grow_cuke_seeding.py` is left in place for reference
    but no longer runs on a schedule.

Usage:
    python migrations/20260417000001_cuke_plantmap.py

Rerunnable: clears rows from the four new layout tables before inserting,
and uses UPSERT into grow_cuke_seed_batch so re-running is safe as long
as step 3 above has not yet been applied.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

from _config import (
    AUDIT_USER,
    ORG_ID,
    SUPABASE_URL,
    require_supabase_key,
)
from _pg import get_pg_conn, pg_bulk_insert, pg_select_all


PLANT_MAP_SHEET_ID = "1ewWyvaXGkRCvZxjUxBOHGY4PKdMHwKeTA5jTIod48LE"
PLANT_MAP_TAB = "Sheet1"
FARM_ID = "Cuke"


# ---------------------------------------------------------------------------
# GH_CONFIG mirror of dash/plant-map/index.html
# ---------------------------------------------------------------------------
# Keys are the display names as they appear in the plant-map sheet's
# Greenhouse column. Each maps to the org_site.id used by Supabase.

GH_NAME_TO_SITE_ID = {
    "GH1": "01", "GH2": "02", "GH3": "03", "GH4": "04",
    "GH5": "05", "GH6": "06", "GH7": "07", "GH8": "08",
    "Kona":    "ko",
    "Hamakua": "hk",
    "Kohala":  "hk",   # shares 'hk' with Hamakua; distinguished via block name
    "Waimea":  "wa",
    "Hilo":    "hi",
}

# HK is one org_site with two physical structures (Hamakua + Kohala). To
# store both under site_id='hk' without row_number collisions, Kohala's sheet
# row_numbers are offset by this many when written to org_site_cuke_gh_row. The
# plant-map UI reads org_site_cuke_gh_block.name to render each structure as a
# separate section and subtracts the offset for display.
KOHALA_ROW_OFFSET = 100

GH_CONFIG = {
    # name: (vert, sidewalk, farm_section, blocks_vertical, align_top, merge,
    #        side_order, layout_row, layout_col, layout_stack_pos)
    "GH1":     (True,  "Middle", "JTL", False, False, False, None,                          1, 2, None),
    "GH2":     (True,  "Middle", "JTL", False, False, False, None,                          1, 1, None),
    "GH3":     (True,  "Middle", "JTL", False, False, False, None,                          1, 0, None),
    "GH4":     (False, "Middle", "JTL", False, False, False, ["East", "West"],              0, 0, None),
    "GH5":     (True,  "Middle", "JTL", False, False, False, ["North", "Middle", "South"],  2, 0, None),
    "GH6":     (True,  "Middle", "JTL", False, False, False, ["North", "Middle", "South"],  2, 1, None),
    "GH7":     (True,  "Bottom", "JTL", False, False, True,  None,                          2, 2, 0),
    "GH8":     (True,  "Top",    "JTL", False, True,  True,  None,                          2, 2, 1),
    "Kona":    (True,  "Middle", "BIP", False, False, False, None,                          0, 0, None),
    "Kohala":  (False, "Left",   "BIP", False, False, False, None,                          0, 1, None),
    "Hamakua": (True,  "Top",    "BIP", False, True,  False, None,                          1, 0, None),
    "Waimea":  (False, "Left",   "BIP", True,  False, False, None,                          1, 1, None),
    "Hilo":    (False, "Left",   "BIP", False, False, False, None,                          2, 1, None),
}


# ---------------------------------------------------------------------------
# Variety mapping — plant-map sheet writes display names; the schema uses k/j/e
# ---------------------------------------------------------------------------

VARIETY_NAME_TO_ID = {
    "Keiki":    "K",
    "Japanese": "J",
    "English":  "E",
}

# User instruction: treat every "Mixed" cell in the Variety (current) column
# as a 50/50 Keiki + Japanese split. Sheet had only 3 Mixed rows at migration
# time: GH3 South row 40, GH3 South row 49, Kona West row 55.
MIXED_SPLIT = ("K", "J")


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, upsert=False, on_conflict=None):
    print(f"\n--- {table} ---")
    all_data = []
    if not rows:
        print("  (no rows)")
        return all_data

    total_batches = (len(rows) + 99) // 100
    for i in range(0, len(rows), 100):
        batch = rows[i:i + 100]
        batch_num = (i // 100) + 1
        try:
            if upsert:
                q = supabase.table(table).upsert(batch)
                if on_conflict:
                    q = q.on_conflict(on_conflict) if hasattr(q, "on_conflict") else q
                result = q.execute()
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


# ---------------------------------------------------------------------------
# Clear step (idempotency)
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    """Remove rows from layout tables so the script is rerunnable.

    org_site_cuke_gh is NOT cleared — it is upserted in place (Step 1) because
    grow_cuke_seed_batch.site_id and grow_cuke_rotation.site_id keep inbound
    FK references to its TEXT ids ('01'..'08', 'hk', 'wa', 'ko', 'hi'). Those
    ids are stable, so an upsert refreshes the row content without breaking
    FKs. grow_cuke_seed_batch itself is handled by the upsert path in Step 5.
    """
    print("\nClearing layout tables for rerun...")
    for table in (
        "grow_cuke_gh_row_planting",
        "org_site_cuke_gh_block",
        "org_site_cuke_gh_row",
    ):
        supabase.table(table).delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
        print(f"  Cleared {table}")


# ---------------------------------------------------------------------------
# Step 1: org_site_cuke_gh from GH_CONFIG
# ---------------------------------------------------------------------------

def seed_org_site_cuke_gh(supabase):
    """One row per distinct site_id in GH_CONFIG. Hamakua and Kohala both map
    to 'hk'; the first encountered wins (Hamakua — it comes first alpha).
    """
    print("\n=== Step 1: org_site_cuke_gh ===")
    rows = []
    seen_sites = set()
    for gh_name, cfg in GH_CONFIG.items():
        site_id = GH_NAME_TO_SITE_ID.get(gh_name)
        if not site_id or site_id in seen_sites:
            if site_id:
                print(f"  Skipping {gh_name}: site_id '{site_id}' already seeded")
            continue
        seen_sites.add(site_id)

        (vert, sidewalk, farm_section, blocks_vertical, _align_top,
         _merge, _side_order, layout_row, layout_col, layout_stack_pos) = cfg

        rows.append(audit({
            "id":                site_id,
            "org_id":            ORG_ID,
            "farm_id":           FARM_ID,
            "farm_section":      farm_section,
            "rows_orientation":  "Vertical" if vert else "Horizontal",
            "sidewalk_position": sidewalk,
            "blocks_vertical":   blocks_vertical,
            "layout_grid_row":   layout_row,
            "layout_grid_col":   layout_col,
            "layout_stack_pos":  layout_stack_pos,
        }))

    return insert_rows(supabase, "org_site_cuke_gh", rows, upsert=True)


# ---------------------------------------------------------------------------
# Steps 2-4: read plant-map sheet
# ---------------------------------------------------------------------------

def read_plantmap(gc):
    print("\nReading plant-map sheet...")
    ws = gc.open_by_key(PLANT_MAP_SHEET_ID).worksheet(PLANT_MAP_TAB)
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")
    return records


# ---------------------------------------------------------------------------
# Step 2: org_site_cuke_gh_row
# ---------------------------------------------------------------------------

def _effective_row_num(gh, sheet_row_num):
    """Map a sheet row_number to the org_site_cuke_gh_row row_number. Kohala rows are
    offset so they don't collide with Hamakua rows in the shared 'hk' site."""
    if gh == "Kohala":
        return sheet_row_num + KOHALA_ROW_OFFSET
    return sheet_row_num


def seed_org_site_cuke_gh_row(supabase, records):
    """One row per physical GH row. Hamakua and Kohala both write to 'hk'
    but Kohala's row_numbers are offset (+KOHALA_ROW_OFFSET) to avoid
    collisions on the unique (site_id, row_number) constraint."""
    print("\n=== Step 2: org_site_cuke_gh_row ===")
    rows = []
    seen = set()
    for r in records:
        gh = str(r.get("Greenhouse", "")).strip()
        site_id = GH_NAME_TO_SITE_ID.get(gh)
        if not site_id:
            continue
        sheet_row_num = parse_int(r.get("Row"))
        if sheet_row_num is None:
            continue
        row_number = _effective_row_num(gh, sheet_row_num)
        key = (site_id, row_number)
        if key in seen:
            continue
        seen.add(key)

        # Bag counts live on grow_cuke_gh_row_planting per scenario, not on
        # the physical row — this table is pure identity (site_id, row_number).
        rows.append(audit({
            "org_id":            ORG_ID,
            "farm_id":           FARM_ID,
            "site_id":           site_id,
            "row_number":           row_number,
        }))

    return insert_rows(supabase, "org_site_cuke_gh_row", rows)


# ---------------------------------------------------------------------------
# Step 3: org_site_cuke_gh_block
# ---------------------------------------------------------------------------

def seed_org_site_cuke_gh_block(supabase, records, inserted_rows):
    """Group sheet rows by (Greenhouse, Side), then derive block metadata.

    For HK (Hamakua + Kohala), each GH name becomes its own block with
    `name` set to the GH name. For other multi-side GHs (GH4, GH5, GH6),
    block name = the sheet's Side value. Single-block GHs get name 'Main'.

    Block num is assigned by the order of first appearance. Row numbers
    use the effective row_number (Kohala offset applied)."""
    print("\n=== Step 3: org_site_cuke_gh_block ===")

    # Group rows by (site_id, block_label) where block_label is 'Hamakua'/
    # 'Kohala' for the HK pair, otherwise the sheet's Side (or 'Main').
    groups = {}
    for r in records:
        gh = str(r.get("Greenhouse", "")).strip()
        site_id = GH_NAME_TO_SITE_ID.get(gh)
        if not site_id:
            continue
        sheet_row_num = parse_int(r.get("Row"))
        order = parse_int(r.get("Order"))
        if sheet_row_num is None or order is None:
            continue
        row_number = _effective_row_num(gh, sheet_row_num)
        if gh in ("Hamakua", "Kohala"):
            block_label = gh
        else:
            block_label = str(r.get("Side", "")).strip() or "Main"
        groups.setdefault((site_id, block_label), []).append((order, row_number))

    # Assign block_number per site — preserve the block_label order of first
    # appearance seen while iterating the sheet.
    block_nums_per_site = {}
    for (site_id, block_label), _ in groups.items():
        nums = block_nums_per_site.setdefault(site_id, {})
        if block_label not in nums:
            nums[block_label] = len(nums) + 1

    rows = []
    for (site_id, block_label), pairs in groups.items():
        pairs.sort()
        row_numbers = [p[1] for p in pairs]
        row_from, row_to = min(row_numbers), max(row_numbers)

        ascending_diffs = sum(1 for a, b in zip(row_numbers, row_numbers[1:]) if b > a)
        descending_diffs = sum(1 for a, b in zip(row_numbers, row_numbers[1:]) if b < a)
        direction = "Forward" if ascending_diffs >= descending_diffs else "Reverse"

        rows.append(audit({
            "org_id":        ORG_ID,
            "farm_id":       FARM_ID,
            "site_id":       site_id,
            "block_number":     block_nums_per_site[site_id][block_label],
            "name":          block_label,
            "row_number_from":  row_from,
            "row_number_to":    row_to,
            "direction":     direction,
        }))

    return insert_rows(supabase, "org_site_cuke_gh_block", rows)


# ---------------------------------------------------------------------------
# Step 4: grow_cuke_gh_row_planting
# ---------------------------------------------------------------------------

def _parse_variety_cell(val):
    """Return (primary_id, secondary_id) for a cell value.

    'Keiki'             -> ('k', None)
    'Japanese/Keiki'    -> ('j', 'k')
    'Mixed'             -> ('k', 'j')  — per user instruction
    ''                  -> (None, None)
    """
    s = str(val or "").strip()
    if not s:
        return (None, None)
    if s == "Mixed":
        return MIXED_SPLIT
    if "/" in s:
        parts = [p.strip() for p in s.split("/", 1)]
        p1 = VARIETY_NAME_TO_ID.get(parts[0])
        p2 = VARIETY_NAME_TO_ID.get(parts[1]) if len(parts) > 1 else None
        return (p1, p2)
    return (VARIETY_NAME_TO_ID.get(s), None)


def seed_grow_cuke_gh_row_planting(supabase, records):
    """One planting row per (physical row, scenario). Skips Kohala.

    Before inserting we fetch the UUIDs for every inserted org_site_cuke_gh_row
    so the planting FK can resolve.
    """
    print("\n=== Step 4: grow_cuke_gh_row_planting ===")

    row_id_by_site_row = {}
    for r in supabase.table("org_site_cuke_gh_row").select("id,site_id,row_number").execute().data:
        row_id_by_site_row[(r["site_id"], r["row_number"])] = r["id"]

    rows = []
    skipped_unmatched = 0
    for rec in records:
        gh = str(rec.get("Greenhouse", "")).strip()
        site_id = GH_NAME_TO_SITE_ID.get(gh)
        if not site_id:
            continue
        sheet_row_num = parse_int(rec.get("Row"))
        if sheet_row_num is None:
            continue
        row_number = _effective_row_num(gh, sheet_row_num)
        row_id = row_id_by_site_row.get((site_id, row_number))
        if not row_id:
            skipped_unmatched += 1
            continue

        bags1 = parse_int(rec.get("Bags_per_row"), 0)
        bags2 = parse_int(rec.get("Bags_per_row2"), 0) or bags1

        # Current scenario
        v1_primary, v1_secondary = _parse_variety_cell(rec.get("Variety"))
        ppb1 = parse_int(rec.get("Plants_per_Bag"))
        if v1_primary and ppb1 in (4, 5):
            rows.append(audit({
                "org_id":             ORG_ID,
                "farm_id":            FARM_ID,
                "org_site_cuke_gh_row_id": row_id,
                "scenario":           "Current",
                "grow_variety_id":    v1_primary,
                "grow_variety_id_2":  v1_secondary,
                "plants_per_bag":     ppb1,
                "num_bags":           bags1,
            }))

        # Planned scenario — only insert if different from current
        v2_primary, v2_secondary = _parse_variety_cell(rec.get("Variety2"))
        ppb2 = parse_int(rec.get("Plants_per_Bag2"))
        if v2_primary and ppb2 in (4, 5):
            rows.append(audit({
                "org_id":             ORG_ID,
                "farm_id":            FARM_ID,
                "org_site_cuke_gh_row_id": row_id,
                "scenario":           "Planned",
                "grow_variety_id":    v2_primary,
                "grow_variety_id_2":  v2_secondary,
                "plants_per_bag":     ppb2,
                "num_bags":           bags2,
            }))

    if skipped_unmatched:
        print(f"  WARNING: skipped {skipped_unmatched} rows — no matching org_site_cuke_gh_row")

    return insert_rows(supabase, "grow_cuke_gh_row_planting", rows)


# ---------------------------------------------------------------------------
# Step 5: copy 660 cuke rows from grow_lettuce_seed_batch -> grow_cuke_seed_batch
# ---------------------------------------------------------------------------

def migrate_cuke_seed_batches(supabase):
    """Copy cuke rows from grow_lettuce_seed_batch into grow_cuke_seed_batch,
    preserving UUIDs so the FK splits in 007/008 can match.

    Mapping (grow_lettuce_seed_batch -> grow_cuke_seed_batch):
      id, org_id, site_id, ops_task_tracker_id, grow_trial_type_id,
      invnt_item_id, invnt_lot_id, seeding_date, transplant_date,
      status, notes, created_at/by, updated_at/by, is_deleted -> copied verbatim
      farm_id                 -> forced to 'Cuke' (guard)
      seeds                   -> number_of_units * seeds_per_unit
      rows_4_per_bag          -> -1 (historical sentinel)
      rows_5_per_bag          -> -1 (historical sentinel)
      next_bag_change_date    -> null
      batch_code              -> dropped (not kept in the new table)
      grow_cycle_pattern_id   -> dropped (always null for cuke)
      grow_lettuce_seed_mix_id -> dropped (cuke never uses seed mixes)
      seeding_uom             -> dropped (always 'Bag' for cuke)
      number_of_units         -> dropped (rolled into seeds)
      seeds_per_unit          -> dropped (rolled into seeds)
      number_of_rows          -> dropped (always -1 sentinel today)
      estimated_harvest_date  -> dropped (lettuce concept)
    """
    print("\n=== Step 5: migrate grow_cuke_seed_batch (660 rows) ===")
    with get_pg_conn() as conn:
        src_rows = pg_select_all(
            conn,
            """
            SELECT id, org_id, site_id, ops_task_tracker_id, grow_trial_type_id,
                   invnt_item_id, invnt_lot_id, seeding_date, transplant_date,
                   COALESCE(number_of_units, 0) * COALESCE(seeds_per_unit, 0) AS seeds,
                   status, notes,
                   created_at, created_by, updated_at, updated_by, is_deleted
            FROM grow_lettuce_seed_batch
            WHERE farm_id = 'Cuke' AND is_deleted = false
            """,
        )

    print(f"  {len(src_rows)} source rows to migrate")

    dest_rows = []
    for r in src_rows:
        dest_rows.append({
            "id":                   r["id"],
            "org_id":               r["org_id"],
            "farm_id":              FARM_ID,
            "site_id":              r["site_id"],
            "ops_task_tracker_id":  r["ops_task_tracker_id"],
            "grow_trial_type_id":   r["grow_trial_type_id"],
            "invnt_item_id":        r["invnt_item_id"],
            "invnt_lot_id":         r["invnt_lot_id"],
            "seeding_date":         r["seeding_date"],
            "transplant_date":      r["transplant_date"],
            "next_bag_change_date": None,
            "rows_4_per_bag":       -1,
            "rows_5_per_bag":       -1,
            "seeds":                int(r["seeds"] or 0),
            "status":               r["status"],
            "notes":                r["notes"],
            "created_at":           r["created_at"],
            "created_by":           r["created_by"],
            "updated_at":           r["updated_at"],
            "updated_by":           r["updated_by"],
            "is_deleted":           r["is_deleted"],
        })

    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "grow_cuke_seed_batch", dest_rows)
        conn.commit()
    print(f"  Inserted {len(dest_rows)} rows into grow_cuke_seed_batch")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("CUKE PLANT-MAP MIGRATION (ONE-TIME)")
    print("=" * 60)

    clear_existing(supabase)

    seed_org_site_cuke_gh(supabase)

    records = read_plantmap(gc)
    inserted_rows = seed_org_site_cuke_gh_row(supabase, records)
    seed_org_site_cuke_gh_block(supabase, records, inserted_rows)
    seed_grow_cuke_gh_row_planting(supabase, records)

    migrate_cuke_seed_batches(supabase)

    print("\n" + "=" * 60)
    print("DONE")
    print("Next steps:")
    print("  1. Apply sql/schema/20260417000007_split_grow_harvest_weight_batch_fk.sql")
    print("  2. Apply sql/schema/20260417000008_split_grow_task_seed_batch_fk.sql")
    print("  3. Apply sql/schema/20260417000009_delete_cuke_from_grow_lettuce_seed_batch.sql")
    print("=" * 60)


if __name__ == "__main__":
    main()
