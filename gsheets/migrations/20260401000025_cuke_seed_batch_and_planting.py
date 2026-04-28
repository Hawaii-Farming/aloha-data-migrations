"""
Rebuild Cuke Seed Batch + Planting + Rotation (DISASTER RECOVERY)
================================================================
One-shot rebuilder for the three "static" cuke tables that have no
nightly repopulator:

  - grow_cuke_gh_row_planting  (~1320 rows, current + planned per physical row)
  - grow_cuke_seed_batch       (~540 historical + ~156 forward = ~700 rows)
  - grow_cuke_rotation         (12 slots + anchor) — created here if missing

When to run:
  - After any accident that leaves the above tables empty (e.g. someone
    adds them back to `_clear_transactional.py` and the nightly truncates
    them)
  - After pushing a fresh Supabase project from scratch
  - NOT on a schedule — this script is NOT in `_run_nightly.py` DEFAULT_SET

Sources (no DB dependencies beyond the table schemas):
  - Plant-Map sheet   `1ewWyvaXGkRCvZxjUxBOHGY4PKdMHwKeTA5jTIod48LE`
    tab `Plant-Map`   — greenhouse layout + current/planned plantings
    tab `bag_changes` — future bag-change dates per GH
  - Grow sheet        `1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM`
    tab `grow_C_seeding` — historical cuke seed batches (2019-present)

Rotation logic (forward 52-week planner):
  - Reads `grow_cuke_rotation` for 12 slot_num → site_id and the anchor row
  - For each slot, computes seeding_date = anchor_week_start +
    7 * ((slot_num - anchor_slot_num) mod 12) days, then steps forward every
    12 weeks up to a 52-week horizon
  - Per-variety seeds/rows are derived from planting rows where scenario='Planned'

Usage:
    python migrations/20260418000001_rebuild_cuke_seed_batch_and_planting.py

Requires:
    SUPABASE_SERVICE_KEY set in .env (no DB URL needed — pure REST)
    credentials.json in cwd (for gspread)
"""

import json
import re
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

from gsheets.migrations._config import AUDIT_USER, ORG_ID, SUPABASE_URL, require_supabase_key


FARM_ID = "Cuke"

PLANT_MAP_SHEET_ID = "1ewWyvaXGkRCvZxjUxBOHGY4PKdMHwKeTA5jTIod48LE"
PLANT_MAP_TAB = "Sheet1"
BAG_CHANGES_TAB = "bag_changes"

GROW_SHEET_ID = "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
SEEDING_TAB = "grow_C_seeding"
HARVEST_TAB = "grow_C_harvest"

# GH name → site_id (plant-map sheet's "Greenhouse" column)
GH_NAME_TO_SITE_ID = {
    "GH1": "01", "GH2": "02", "GH3": "03", "GH4": "04",
    "GH5": "05", "GH6": "06", "GH7": "07", "GH8": "08",
    "Kona":    "ko",
    "Hamakua": "hk",
    "Kohala":  "hk",
    "Waimea":  "wa",
    "Hilo":    "hi",
}
KOHALA_ROW_OFFSET = 100

# Greenhouse column in grow_C_seeding uses short codes
GROW_GH_MAP = {
    "01": "01", "02": "02", "03": "03", "04": "04",
    "05": "05", "06": "06", "07": "07", "08": "08",
    # Single-digit form found in grow_C_seeding (e.g. '1' for GH1)
    "1":  "01", "2":  "02", "3":  "03", "4":  "04",
    "5":  "05", "6":  "06", "7":  "07", "8":  "08",
    "KO": "ko", "HK": "hk", "WA": "wa", "HI": "hi",
}

VARIETY_NAME_TO_ID = {"Keiki": "K", "Japanese": "J", "English": "E"}
MIXED_SPLIT = ("K", "J")

DEFAULT_VARIETY_ITEM = {
    "K": "Delta Star Minis(Rz)",
    "J": "F1 Tsx-Cu235Jp(Tokita)",
    "E": "Cumlaude Rz",
}
ITEM_MAP = {
    "delta star": "Delta Star Minis(Rz)",
    "tokita":     "F1 Tsx-Cu235Jp(Tokita)",
    "english":    "Cumlaude Rz",
    "cumlaude":   "Cumlaude Rz",
    "cumlade":    "Cumlaude Rz",
    "tasty jade": "Tasty Jade F1",
    "sashimi":    "Sashimi F1",
    "unagi":      "Unagi F1",
}

STATUS_MAP = {
    "complete":       "Harvested",
    "harvesting":     "Harvesting",
    "pre-harvesting": "Transplanted",
}

TRIAL_TYPE_ID = "Legacy Trial"

# SIM_ORDER mirror (used only if grow_cuke_rotation is empty and we need to
# populate it). Keep in sync with dash/plant-map/index.html:1398 and the DB.
SIM_ORDER = [
    "ko", "08", "01", "hk", "07", "wa", "04", "02", "05", "hi", "06", "03"
]
ANCHOR_SLOT_NUM = 8  # GH2 = '02' is slot 8
ANCHOR_DATE = date(2026, 3, 15)

HORIZON_WEEKS = 52


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def audit(row):
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def pint(v, d=None):
    if v is None:
        return d
    s = str(v).strip().replace(",", "")
    if not s:
        return d
    try:
        return int(float(s))
    except ValueError:
        return d


def parse_variety_cell(val):
    s = str(val or "").strip()
    if not s:
        return (None, None)
    if s == "Mixed":
        return MIXED_SPLIT
    if "/" in s:
        a, b = [p.strip() for p in s.split("/", 1)]
        return (VARIETY_NAME_TO_ID.get(a), VARIETY_NAME_TO_ID.get(b))
    return (VARIETY_NAME_TO_ID.get(s), None)


def effective_row_num(gh, sheet_row_num):
    return sheet_row_num + KOHALA_ROW_OFFSET if gh == "Kohala" else sheet_row_num


def parse_date_cell(val):
    if val is None:
        return None
    if isinstance(val, (date, datetime)):
        return val.date() if isinstance(val, datetime) else val
    s = str(val).strip()
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def lookup_item(name):
    s = str(name or "").strip().lower()
    for key, iid in ITEM_MAP.items():
        if key in s:
            return iid
    return None


def batched_insert(supabase, table, rows, label, size=100):
    if not rows:
        print(f"  ({label}) 0 rows — skipping")
        return
    total = len(rows)
    for i in range(0, total, size):
        chunk = rows[i:i + size]
        supabase.table(table).insert(chunk).execute()
        print(f"  ({label}) inserted {min(i + size, total)}/{total}")


# ---------------------------------------------------------------------------
# Sheets fetch
# ---------------------------------------------------------------------------

def get_sheets_client():
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def load_sheet_tab(gc, sheet_id, tab):
    ws = gc.open_by_key(sheet_id).worksheet(tab)
    return ws.get_all_records()


# ---------------------------------------------------------------------------
# Rotation table (create + seed if empty)
# ---------------------------------------------------------------------------

def ensure_rotation(supabase):
    existing = supabase.table("grow_cuke_rotation").select("slot_num").execute().data
    if existing:
        print(f"\n--- grow_cuke_rotation: {len(existing)} rows present, skipping seed ---")
        return
    print("\n--- grow_cuke_rotation: empty, seeding 12 slots ---")
    rows = []
    for i, site_id in enumerate(SIM_ORDER):
        slot_num = i + 1
        is_anchor = (slot_num == ANCHOR_SLOT_NUM)
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "slot_num": slot_num,
            "site_id": site_id,
            "is_anchor": is_anchor,
            "anchor_week_start": ANCHOR_DATE.isoformat() if is_anchor else None,
        }))
    supabase.table("grow_cuke_rotation").insert(rows).execute()
    print(f"  Seeded {len(rows)} rotation slots")


def load_rotation(supabase):
    data = supabase.table("grow_cuke_rotation").select(
        "slot_num,site_id,is_anchor,anchor_week_start"
    ).order("slot_num").execute().data
    if not data:
        raise SystemExit("grow_cuke_rotation is empty even after ensure_rotation()")
    anchor = next((r for r in data if r["is_anchor"]), None)
    if not anchor:
        raise SystemExit("grow_cuke_rotation has no anchor row")
    anchor_date = parse_date_cell(anchor["anchor_week_start"])
    if not anchor_date:
        raise SystemExit(f"Cannot parse anchor_week_start: {anchor['anchor_week_start']}")
    return data, anchor["slot_num"], anchor_date


# ---------------------------------------------------------------------------
# grow_cuke_gh_row_planting (from Plant-Map sheet)
# ---------------------------------------------------------------------------

def rebuild_plantings(supabase, plant_map_records):
    print("\n=== grow_cuke_gh_row_planting ===")

    # Load row id lookup
    row_id_by_site_row = {}
    page = 0
    while True:
        page_rows = (
            supabase.table("org_site_cuke_gh_row")
            .select("id,site_id,row_number")
            .range(page * 1000, (page + 1) * 1000 - 1)
            .execute().data
        )
        if not page_rows:
            break
        for r in page_rows:
            row_id_by_site_row[(r["site_id"], r["row_number"])] = r["id"]
        if len(page_rows) < 1000:
            break
        page += 1

    supabase.table("grow_cuke_gh_row_planting").delete().neq(
        "id", "00000000-0000-0000-0000-000000000000"
    ).execute()
    print(f"  Cleared existing plantings. {len(row_id_by_site_row)} physical rows available.")

    seen = set()
    rows_out = []
    skipped = 0

    for rec in plant_map_records:
        gh = str(rec.get("Greenhouse", "")).strip()
        site_id = GH_NAME_TO_SITE_ID.get(gh)
        if not site_id:
            continue
        sheet_row_num = pint(rec.get("Row"))
        if sheet_row_num is None:
            continue
        rn = effective_row_num(gh, sheet_row_num)

        key = (site_id, rn)
        if key in seen:
            continue  # sheet dupe (e.g. GH5 row 43 in two sides); first wins
        seen.add(key)

        row_id = row_id_by_site_row.get(key)
        if not row_id:
            skipped += 1
            continue

        bags1 = pint(rec.get("Bags_per_row"), 0)
        bags2 = pint(rec.get("Bags_per_row2"), 0) or bags1

        v1a, v1b = parse_variety_cell(rec.get("Variety"))
        ppb1 = pint(rec.get("Plants_per_Bag"))
        if v1a and ppb1 in (4, 5):
            rows_out.append(audit({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "org_site_cuke_gh_row_id": row_id,
                "scenario": "Current",
                "grow_variety_id": v1a,
                "grow_variety_id_2": v1b,
                "plants_per_bag": ppb1,
                "num_bags": bags1,
            }))

        v2a, v2b = parse_variety_cell(rec.get("Variety2"))
        ppb2 = pint(rec.get("Plants_per_Bag2"))
        if v2a and ppb2 in (4, 5):
            rows_out.append(audit({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "org_site_cuke_gh_row_id": row_id,
                "scenario": "Planned",
                "grow_variety_id": v2a,
                "grow_variety_id_2": v2b,
                "plants_per_bag": ppb2,
                "num_bags": bags2,
            }))

    if skipped:
        print(f"  WARNING: skipped {skipped} sheet rows with no matching org_site_cuke_gh_row")

    batched_insert(supabase, "grow_cuke_gh_row_planting", rows_out, "plantings")
    print(f"  Done: {len(rows_out)} rows inserted")


# ---------------------------------------------------------------------------
# grow_cuke_seed_batch historical (from grow_C_seeding sheet)
# ---------------------------------------------------------------------------

def build_historical_batches(seeding_records):
    rows = []
    for rec in seeding_records:
        seeding_date = parse_date_cell(rec.get("SeedingDate"))
        if not seeding_date:
            continue
        transplant_date = seeding_date + timedelta(days=14)

        gh = str(rec.get("Greenhouse", "")).strip()
        site_id = GROW_GH_MAP.get(gh)
        if not site_id:
            continue

        status = STATUS_MAP.get(
            str(rec.get("CycleStatus", "")).strip().lower(), "transplanted"
        )
        reported_by = str(rec.get("ReportedBy", "")).strip().lower()
        if "@" not in reported_by:
            reported_by = AUDIT_USER
        notes = str(rec.get("Notes", "")).strip() or None

        # Main K/J/E blocks
        for letter, variety_id in (("K", "K"), ("J", "J"), ("E", "E")):
            ppb = pint(rec.get(f"{letter}PlantsPerBag"))
            seeds = pint(rec.get(f"{letter}NumberOfSeeds"))
            name = str(rec.get(f"{letter}Name", "")).strip()
            if (not name and not seeds) or not ppb or not seeds:
                continue
            item_id = lookup_item(name) or DEFAULT_VARIETY_ITEM[variety_id]
            rows.append({
                "org_id":          ORG_ID,
                "farm_id":         FARM_ID,
                "site_id":         site_id,
                "invnt_item_id":   item_id,
                "seeding_date":    seeding_date.isoformat(),
                "transplant_date": transplant_date.isoformat(),
                "seeds":           seeds,
                "rows_4_per_bag":  -1,
                "rows_5_per_bag":  -1,
                "status":          status,
                "notes":           notes,
                "created_by":      reported_by,
                "updated_by":      reported_by,
            })

        # Trial seeds (1..3)
        for slot in (1, 2, 3):
            t_var = str(rec.get(f"trial_seed_{slot}_variety", "")).strip().upper()
            t_count = pint(rec.get(f"trial_seed_{slot}_count"))
            t_name = str(rec.get(f"trial_seed_{slot}_name_lot", "")).strip()
            if t_var not in ("K", "J", "E") or not t_count or t_count <= 0:
                continue
            variety_id = t_var
            item_id = lookup_item(t_name) or DEFAULT_VARIETY_ITEM[variety_id]
            rows.append({
                "org_id":              ORG_ID,
                "farm_id":             FARM_ID,
                "site_id":             site_id,
                "invnt_item_id":       item_id,
                "grow_trial_type_id":  TRIAL_TYPE_ID,
                "seeding_date":        seeding_date.isoformat(),
                "transplant_date":     transplant_date.isoformat(),
                "seeds":               t_count,
                "rows_4_per_bag":      -1,
                "rows_5_per_bag":      -1,
                "status":              status,
                "notes":               notes,
                "created_by":          reported_by,
                "updated_by":          reported_by,
            })
    return rows


def ensure_legacy_trial_type(supabase):
    """Upsert grow_trial_type.legacy_trial so the historical trial rows have
    a valid FK. Nightly truncates this table; every rebuild re-seeds it."""
    supabase.table("grow_trial_type").upsert(audit({
        "id": TRIAL_TYPE_ID,
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "id": "Legacy Trial",
        "description": "Historical trial seedings migrated from grow_C_seeding sheet",
    })).execute()


# ---------------------------------------------------------------------------
# grow_cuke_seed_batch forward (rotation + plant-map derived)
# ---------------------------------------------------------------------------

def build_forward_batches(plant_map_records, bag_changes_records, rotation):
    rotation_rows, anchor_slot, anchor_date = rotation

    # Aggregate planted-scenario per (site_id, variety) from Plant-Map sheet
    agg = {}
    seen_rows = set()
    for rec in plant_map_records:
        gh = str(rec.get("Greenhouse", "")).strip()
        site_id = GH_NAME_TO_SITE_ID.get(gh)
        if not site_id:
            continue
        sheet_row_num = pint(rec.get("Row"))
        if sheet_row_num is None:
            continue
        rn = effective_row_num(gh, sheet_row_num)
        key = (site_id, rn)
        if key in seen_rows:
            continue
        seen_rows.add(key)

        v2 = str(rec.get("Variety2", "")).strip()
        ppb2 = pint(rec.get("Plants_per_Bag2"))
        bags2 = pint(rec.get("Bags_per_row2"), 0)
        if not v2 or ppb2 not in (4, 5) or not bags2:
            continue

        # Parse variety (single, pair, or Mixed=50/50 k/j)
        if v2 == "Mixed":
            pairs = [("K", 0.5), ("J", 0.5)]
        elif "/" in v2:
            parts = [p.strip() for p in v2.split("/", 1)]
            v1 = VARIETY_NAME_TO_ID.get(parts[0])
            v2x = VARIETY_NAME_TO_ID.get(parts[1]) if len(parts) > 1 else None
            pairs = [(v1, 0.5), (v2x, 0.5)] if (v1 and v2x) else ([(v1, 1.0)] if v1 else [])
        else:
            v1 = VARIETY_NAME_TO_ID.get(v2)
            pairs = [(v1, 1.0)] if v1 else []

        for variety_id, share in pairs:
            d = agg.setdefault(site_id, {}).setdefault(variety_id, {"seeds": 0, "r4": 0, "r5": 0})
            row_bags = bags2 * share
            d["seeds"] += int(row_bags * ppb2)
            if ppb2 == 4:
                d["r4"] += round(row_bags)
            elif ppb2 == 5:
                d["r5"] += round(row_bags)

    # bag_changes lookup: site_id → sorted list of dates
    bag_changes = {}
    for rec in bag_changes_records:
        gh = str(rec.get("GH", "")).strip()
        site_id = GH_NAME_TO_SITE_ID.get(gh)
        if not site_id:
            continue
        bd = parse_date_cell(rec.get("bag_change"))
        if not bd:
            continue
        bag_changes.setdefault(site_id, []).append(bd)
    for s in bag_changes:
        bag_changes[s].sort()

    def next_bag_change(site_id, sd):
        for bd in bag_changes.get(site_id, []):
            if bd >= sd:
                return bd
        return None

    today = date.today()
    horizon = today + timedelta(weeks=HORIZON_WEEKS)
    rows_out = []

    for row in rotation_rows:
        slot_num = row["slot_num"]
        site_id = row["site_id"]
        offset_weeks = (slot_num - anchor_slot) % 12
        first = anchor_date + timedelta(weeks=offset_weeks)

        # fast-forward to the most recent cycle at or before today, then iterate
        sd = first
        while sd < today - timedelta(weeks=12):
            sd += timedelta(weeks=12)

        while sd <= horizon:
            if sd > today:  # only future 'planned' rows
                for variety_id, vals in agg.get(site_id, {}).items():
                    if vals["seeds"] <= 0:
                        continue
                    rows_out.append({
                        "org_id":                ORG_ID,
                        "farm_id":               FARM_ID,
                        "site_id":               site_id,
                        "invnt_item_id":         DEFAULT_VARIETY_ITEM[variety_id],
                        "seeding_date":          sd.isoformat(),
                        "transplant_date":       (sd + timedelta(days=14)).isoformat(),
                        "next_bag_change_date":  (next_bag_change(site_id, sd).isoformat()
                                                   if next_bag_change(site_id, sd) else None),
                        "seeds":                 vals["seeds"],
                        "rows_4_per_bag":        vals["r4"],
                        "rows_5_per_bag":        vals["r5"],
                        "status":                "Planned",
                        "created_by":            AUDIT_USER,
                        "updated_by":            AUDIT_USER,
                    })
            sd += timedelta(weeks=12)

    return rows_out


def build_harvest_stub_batches(harvest_records, existing_codes):
    """For every distinct SeedingCycle in grow_C_harvest that has no
    matching seed_batch yet, create a stub seed_batch so the harvest can
    FK-match. Strips an optional 'S-' prefix before parsing — S-prefixed
    cycles share their stripped-form stub. Returns list of dicts.

    Cycle code format: [S-]YYMM{GH}{V} where GH is two chars (digit pair
    like '01' or two-letter code like 'HK') and V is K/J/E.
    """
    GH_TOKENS = {"01","02","03","04","05","06","07","08",
                 "KO","HK","WA","HI"}
    GH_TO_SITE = {"01":"01","02":"02","03":"03","04":"04",
                  "05":"05","06":"06","07":"07","08":"08",
                  "KO":"ko","HK":"hk","WA":"wa","HI":"hi"}
    rows = []
    seen_targets = set(existing_codes)
    seen_local = set()
    skipped_unparseable = []

    for r in harvest_records:
        raw = str(r.get("SeedingCycle", "")).strip().upper()
        if not raw:
            continue
        # Strip S- prefix — it's a label, the underlying batch is the same.
        c = raw[2:] if raw.startswith("S-") else raw
        # Format: YYMM{GH2}{V1} = 7 chars
        if len(c) != 7:
            skipped_unparseable.append(raw)
            continue
        yy_str, mm_str, gh, v = c[0:2], c[2:4], c[4:6], c[6]
        if not (yy_str.isdigit() and mm_str.isdigit() and v in ("K","J","E") and gh in GH_TOKENS):
            skipped_unparseable.append(raw)
            continue
        derived = f"{yy_str}{mm_str}{gh}{v}"  # site is uppercased; matches derive_cycle_code
        if derived in seen_targets or derived in seen_local:
            continue
        seen_local.add(derived)
        yy = int(yy_str)
        year = 2000 + yy if yy < 70 else 1900 + yy
        seeding_date = date(year, int(mm_str), 1).isoformat()
        rows.append({
            "org_id":          ORG_ID,
            "farm_id":         FARM_ID,
            "site_id":         GH_TO_SITE[gh],
            "invnt_item_id":   DEFAULT_VARIETY_ITEM[v],
            "seeding_date":    seeding_date,
            "transplant_date": (date(year, int(mm_str), 15)).isoformat(),
            "seeds":           0,
            "rows_4_per_bag":  -1,
            "rows_5_per_bag":  -1,
            "status":          "Harvested",
            "notes":           f"Stub batch backfilled from grow_C_harvest cycle code {raw}",
            "created_by":      AUDIT_USER,
            "updated_by":      AUDIT_USER,
        })
    if skipped_unparseable:
        from collections import Counter
        c = Counter(skipped_unparseable)
        print(f"  {len(skipped_unparseable)} unparseable cycle codes (most common): {c.most_common(5)}")
    return rows


def derived_codes_for(rows):
    """Return the set of derived cycle codes for a list of seed_batch rows."""
    codes = set()
    GH_TO_SITE_INV = {"01":"01","02":"02","03":"03","04":"04",
                      "05":"05","06":"06","07":"07","08":"08",
                      "ko":"KO","hk":"HK","wa":"WA","hi":"HI"}
    for r in rows:
        sd = r["seeding_date"]
        site = r["site_id"]
        # Lookup invnt_item_id -> variety letter
        inv = r["invnt_item_id"]
        v = next((k for k, vid in DEFAULT_VARIETY_ITEM.items() if vid == inv), None)
        if not v:
            # ITEM_MAP-based items: infer by checking if K/J/E
            for kk, vv in ITEM_MAP.items():
                if vv == inv:
                    if "delta" in kk or "tokita" in kk or kk in ("tasty jade","sashimi","unagi"):
                        # K/J variants — fall back on default mapping
                        for kk2, vv2 in DEFAULT_VARIETY_ITEM.items():
                            if vv2 == inv:
                                v = kk2; break
                    elif "english" in kk or "cumlaude" in kk or "cumlade" in kk:
                        v = "E"
                    break
        if not v:
            continue
        from datetime import datetime as _dt
        if isinstance(sd, str):
            sd = _dt.strptime(sd, "%Y-%m-%d").date()
        gh = GH_TO_SITE_INV.get(site, site.upper())
        codes.add(f"{sd.year%100:02d}{sd.month:02d}{gh}{v}")
    return codes


def rebuild_seed_batches(supabase, seeding_records, plant_map_records, bag_changes_records, rotation, harvest_records=None):
    print("\n=== grow_cuke_seed_batch ===")
    ensure_legacy_trial_type(supabase)

    supabase.table("grow_cuke_seed_batch").delete().eq("farm_id", FARM_ID).execute()
    print("  Cleared existing cuke seed batches")

    hist = build_historical_batches(seeding_records)
    print(f"  Historical rows built: {len(hist)}")
    batched_insert(supabase, "grow_cuke_seed_batch", hist, "historical")

    fwd = build_forward_batches(plant_map_records, bag_changes_records, rotation)
    print(f"  Forward rows built: {len(fwd)}")
    batched_insert(supabase, "grow_cuke_seed_batch", fwd, "forward")

    if harvest_records is not None:
        existing_codes = derived_codes_for(hist) | derived_codes_for(fwd)
        stubs = build_harvest_stub_batches(harvest_records, existing_codes)
        print(f"  Harvest-stub rows built: {len(stubs)}")
        if stubs:
            batched_insert(supabase, "grow_cuke_seed_batch", stubs, "harvest_stubs")
        total = len(hist) + len(fwd) + len(stubs)
    else:
        total = len(hist) + len(fwd)

    print(f"  Done: {total} total rows")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets_client()

    print("=" * 60)
    print("CUKE SEED BATCH + PLANTING + ROTATION REBUILD")
    print("=" * 60)

    ensure_rotation(supabase)
    rotation = load_rotation(supabase)

    print("\nLoading sheets...")
    plant_map_records = load_sheet_tab(gc, PLANT_MAP_SHEET_ID, PLANT_MAP_TAB)
    print(f"  Plant-Map: {len(plant_map_records)} rows")
    bag_changes_records = load_sheet_tab(gc, PLANT_MAP_SHEET_ID, BAG_CHANGES_TAB)
    print(f"  bag_changes: {len(bag_changes_records)} rows")
    seeding_records = load_sheet_tab(gc, GROW_SHEET_ID, SEEDING_TAB)
    print(f"  grow_C_seeding: {len(seeding_records)} rows")
    harvest_records = load_sheet_tab(gc, GROW_SHEET_ID, HARVEST_TAB)
    print(f"  grow_C_harvest: {len(harvest_records)} rows")

    rebuild_plantings(supabase, plant_map_records)
    rebuild_seed_batches(supabase, seeding_records, plant_map_records,
                         bag_changes_records, rotation, harvest_records)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
