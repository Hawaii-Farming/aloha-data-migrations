"""
Migrate Grow Monitoring Readings
=================================
Two sheets into grow_monitoring_metric (reference data), ops_task_tracker,
grow_monitoring_result, and grow_task_photo.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_chem (~31,200 rows): cuke 20,817 + lettuce 10,383
  - grow_chem_flags (10 rows): range thresholds per variable

Setup (upserted):
  - 24 grow_monitoring_metric rows covering cuke greenhouse, cuke nursery,
    and lettuce pond site categories
  - Per-station EC ranges for cuke nursery (Hi/Lo/Water) are split into
    three separate metrics since the schema keeps min/max on the metric

Per sheet row:
  - 1 ops_task_tracker (ops_task_id='monitoring', farm, site_id, station
    details in notes, start_time from ReportedDateTime/CheckedDate)
  - 1 grow_monitoring_result per non-blank measurement column
    (station, reading, is_out_of_range computed from metric range)
  - 1 grow_task_photo per non-blank Photo01/02

Site mapping:
  1-8 -> 01-08, HI -> hi, HK -> hk, KO -> ko, WA -> wa
  Nursery (E) -> ne, Nursery (W) -> nw, Nursery -> ne (legacy default)
  P1-P7 -> p1-p7

Station normalization:
  A, B, East, West: as-is
  H(A) -> HA, H(B) -> HB, K(A) -> KA, K(B) -> KB (HK greenhouse)
  Hi-EC -> High, Lo-EC -> Low, Water-EC/Water -> Water (nursery)
  Kohala (A/B) -> A/B (KO typo)
  blank -> NULL (backfill later)

Rerunnable: identifies our trackers via notes marker
"Legacy monitoring migration".

Usage:
    python migrations/20260401000033_grow_monitoring.py
"""

import json
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
NOTES_MARKER = "Legacy monitoring migration"
OPS_TASK_ID = "monitoring"


# ---------------------------------------------------------------------------
# Metric definitions
# ---------------------------------------------------------------------------
#
# Schema: grow_monitoring_metric is unique on (org_id, farm_id, site_category, name).
# For cuke nursery, EC is split into 3 metrics (Hi/Lo/Water) because each
# station has a different valid range and the schema stores range on metric.
#
# Ranges come from grow_chem_flags sheet values.
#
# Each dict here is used both to upsert the metric row and to map
# (site_category, sheet_column, station) -> metric id during row processing.

METRICS = [
    # ----- cuke greenhouse (sites 01-08, HI, HK, KO, WA) -----
    dict(id="cuke_gh_drip_ml",          farm="cuke", site_cat="greenhouse",
         name="Drip Milliliters",       sheet_col="DripMilliliters",
         uom="milliliter"),
    dict(id="cuke_gh_drain_ml",         farm="cuke", site_cat="greenhouse",
         name="Drain Milliliters",      sheet_col="DrainMilliliters",
         uom="milliliter"),
    dict(id="cuke_gh_drain_percent",    farm="cuke", site_cat="greenhouse",
         name="Drain Percentage",       sheet_col="DrainPercentage",
         uom="percent", min=15, max=35,
         is_calculated=True,
         formula="(drain_ml / (drip_ml * drippers)) * 100",
         input_point_ids=["cuke_gh_drain_ml", "cuke_gh_drip_ml", "cuke_gh_drippers"]),
    dict(id="cuke_gh_drip_ec",          farm="cuke", site_cat="greenhouse",
         name="Drip EC",                sheet_col="DripEC",
         uom="millisiemens"),
    dict(id="cuke_gh_drain_ec",         farm="cuke", site_cat="greenhouse",
         name="Drain EC",               sheet_col="DrainEC",
         uom="millisiemens", min=1.7, max=2.7),
    dict(id="cuke_gh_drip_ph",          farm="cuke", site_cat="greenhouse",
         name="Drip pH",                sheet_col="DrippH",
         uom="ph"),
    dict(id="cuke_gh_drain_ph",         farm="cuke", site_cat="greenhouse",
         name="Drain pH",               sheet_col="DrainpH",
         uom="ph", min=5.9, max=6.2),
    dict(id="cuke_gh_drippers",         farm="cuke", site_cat="greenhouse",
         name="Drippers",               sheet_col="Drippers"),
    dict(id="cuke_gh_injection",        farm="cuke", site_cat="greenhouse",
         name="Injection",              sheet_col="Injection"),
    dict(id="cuke_gh_crop_height_in",   farm="cuke", site_cat="greenhouse",
         name="Crop Height",            sheet_col="CropHeightInInches",
         uom="inch"),

    # ----- cuke nursery (sites ne, nw) — DripEC splits by station -----
    dict(id="cuke_nursery_hi_ec",       farm="cuke", site_cat="nursery",
         name="Hi-EC",                  sheet_col="DripEC",
         uom="millisiemens", min=2.5, max=3.0,
         nursery_station_gate="High"),
    dict(id="cuke_nursery_lo_ec",       farm="cuke", site_cat="nursery",
         name="Lo-EC",                  sheet_col="DripEC",
         uom="millisiemens", min=2.0, max=2.3,
         nursery_station_gate="Low"),
    dict(id="cuke_nursery_water_ec",    farm="cuke", site_cat="nursery",
         name="Water EC",               sheet_col="DripEC",
         uom="millisiemens", min=0.0, max=0.2,
         nursery_station_gate="Water"),
    dict(id="cuke_nursery_drip_ph",     farm="cuke", site_cat="nursery",
         name="Drip pH",                sheet_col="DrippH",
         uom="ph"),
    dict(id="cuke_nursery_drain_percent", farm="cuke", site_cat="nursery",
         name="Drain Percentage",       sheet_col="DrainPercentage",
         uom="percent", min=15, max=35),
    dict(id="cuke_nursery_drippers",    farm="cuke", site_cat="nursery",
         name="Drippers",               sheet_col="Drippers"),

    # ----- lettuce pond (sites p1-p7) -----
    dict(id="lettuce_pond_ec",          farm="lettuce", site_cat="pond",
         name="Pond EC",                sheet_col="DripEC",
         uom="millisiemens", min=2.0, max=2.4),
    dict(id="lettuce_pond_ph",          farm="lettuce", site_cat="pond",
         name="Pond pH",                sheet_col="DrippH",
         uom="ph", min=5.3, max=6.3),
    dict(id="lettuce_water_ec",         farm="lettuce", site_cat="pond",
         name="Water EC",               sheet_col="DrainEC",
         uom="millisiemens", min=0.0, max=0.2),
    dict(id="lettuce_dissolved_oxygen", farm="lettuce", site_cat="pond",
         name="Dissolved Oxygen",       sheet_col="DirectOxygen",
         uom="ppm", min=12, max=20),
    dict(id="lettuce_temperature",      farm="lettuce", site_cat="pond",
         name="Water Temperature",      sheet_col="Temperature",
         uom="fahrenheit", min=65, max=75),
    dict(id="lettuce_water_level_cm",   farm="lettuce", site_cat="pond",
         name="Water Level",            sheet_col="WaterLevelInCentiMeters",
         uom="centimeter"),
    dict(id="lettuce_aerators",         farm="lettuce", site_cat="pond",
         name="Aerators",               sheet_col="Drippers"),
    dict(id="lettuce_drain_percent",    farm="lettuce", site_cat="pond",
         name="Drain Percentage",       sheet_col="DrainPercentage",
         uom="percent", min=15, max=35),
]

# Build fast lookup: (farm, site_cat, sheet_col, station_gate or None) -> metric_id
METRIC_RESOLVER = {}
METRICS_BY_ID = {}
for m in METRICS:
    METRICS_BY_ID[m["id"]] = m
    gate = m.get("nursery_station_gate")
    key = (m["farm"], m["site_cat"], m["sheet_col"], gate)
    METRIC_RESOLVER[key] = m["id"]


# ---------------------------------------------------------------------------
# Site & station normalization
# ---------------------------------------------------------------------------

SITE_NAME_MAP = {
    "nursery (e)": "ne",
    "nursery (w)": "nw",
    "nursery":     "ne",   # legacy, pre-split default
}

STATION_MAP = {
    "hi-ec":        "High",
    "lo-ec":        "Low",
    "water-ec":     "Water",
    "water":        "Water",
    "h(a)":         "HA",
    "h(b)":         "HB",
    "k(a)":         "KA",
    "k(b)":         "KB",
    "kohala (a)":   "A",
    "kohala (b)":   "B",
}


def normalize_site(raw: str) -> str | None:
    if not raw:
        return None
    s = str(raw).strip()
    if not s:
        return None
    low = s.lower()
    if low in SITE_NAME_MAP:
        return SITE_NAME_MAP[low]
    if low.isdigit() and len(low) == 1:
        return low.zfill(2)
    return low


def normalize_station(raw: str) -> str | None:
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    return STATION_MAP.get(s.lower(), s)


def site_category_for(site_id: str) -> str | None:
    if site_id in ("ne", "nw"):
        return "nursery"
    if site_id and site_id.startswith("p") and site_id[1:].isdigit():
        return "pond"
    if site_id in ("01", "02", "03", "04", "05", "06", "07", "08",
                   "hi", "hk", "ko", "wa"):
        return "greenhouse"
    return None


# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------

def get_sheets():
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def parse_datetime(val):
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


def parse_numeric(val):
    if val is None:
        return None
    s = str(val).strip().replace(",", "").replace("%", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def resolve_user(raw: str) -> str:
    s = str(raw).strip().lower()
    return s if "@" in s else AUDIT_USER


def compute_oor(reading: float, mn, mx) -> bool:
    if reading is None:
        return False
    if mn is None and mx is None:
        return False
    if mn is not None and reading < float(mn):
        return True
    if mx is not None and reading > float(mx):
        return True
    return False


# ---------------------------------------------------------------------------
# Setup: upsert the 24 metrics
# ---------------------------------------------------------------------------

def ensure_metrics(supabase):
    print("\n--- grow_monitoring_metric ---")
    rows = []
    for m in METRICS:
        row = {
            "id": m["id"],
            "org_id": ORG_ID,
            "farm_id": m["farm"],
            "site_category": m["site_cat"],
            "name": m["name"],
            "description": NOTES_MARKER,
            "response_type": "numeric",
            "reading_uom": m.get("uom"),
            "minimum_value": m.get("min"),
            "maximum_value": m.get("max"),
            "is_calculated": bool(m.get("is_calculated")),
            "formula": m.get("formula"),
            "input_point_ids": json.dumps(m["input_point_ids"]) if m.get("input_point_ids") else None,
            "is_required": True,
            "corrective_actions": json.dumps([]),
            "display_order": 0,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }
        rows.append(row)
    supabase.table("grow_monitoring_metric").upsert(rows).execute()
    print(f"  Upserted {len(rows)} metric rows")


# ---------------------------------------------------------------------------
# Clear existing legacy rows for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    print("\nClearing existing legacy monitoring rows...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                DELETE FROM grow_monitoring_result
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
                DELETE FROM grow_task_photo
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
                DELETE FROM grow_task_seed_batch
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_id = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d4 = cur.rowcount
            cur.execute(
                "DELETE FROM ops_task_tracker WHERE ops_task_id = %s AND notes LIKE %s",
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d3 = cur.rowcount
        conn.commit()
    print(f"  Deleted: {d1} grow_monitoring_result, {d2} grow_task_photo, "
          f"{d4} grow_task_seed_batch, {d3} ops_task_tracker")


# ---------------------------------------------------------------------------
# Seed batch lookups for SeedingCycle linking
# ---------------------------------------------------------------------------

def build_batch_lookups(supabase):
    """Return (cuke_by_prefix, lettuce_by_code).

    cuke_by_prefix: dict from seeding cycle prefix -> list of batch_ids
      Built by scanning all cuke batch_codes and grouping by leading prefix
      that matches the sheet's SeedingCycle pattern (YYMM + optional GH).
      We handle this by storing the full batch_code list and doing
      startswith matching at link time (with a lookup short-circuit index).

    lettuce_by_code: dict from batch_code (both base and disambiguated with
      _N suffix) -> batch_id.
    """
    from collections import defaultdict

    # grow_cuke_seed_batch has no batch_code. Derive the cycle prefix on
    # the fly from (seeding_date, site_id): {YY}{MM}{GH}. The sheet's
    # SeedingCycle value (e.g. "2603HI", "260406") is a startswith-match
    # against these derived prefixes.
    from gsheets.migrations._pg import get_pg_conn, pg_select_all
    with get_pg_conn() as conn:
        cuke_rows = pg_select_all(conn, """
            SELECT id, seeding_date, site_id
            FROM grow_cuke_seed_batch
            WHERE is_deleted = false
        """)
    cuke_list = []
    for b in cuke_rows:
        sd = b["seeding_date"]
        if not sd:
            continue
        prefix = f"{sd.year % 100:02d}{sd.month:02d}{str(b['site_id'] or '').upper()}"
        cuke_list.append((prefix, b["id"]))

    lettuce_codes = paginate_select(
        supabase, "grow_lettuce_seed_batch", "id,batch_code,farm_id",
    )

    # Lettuce: both the original batch_code and disambiguated variants
    # index to the same row in DB (different id per disambiguated row).
    # Build: base_code -> [id, id2, ...] where base_code strips trailing _N.
    lettuce_by_base = defaultdict(list)
    for b in lettuce_codes:
        code = b["batch_code"]
        base = re.sub(r"_\d+$", "", code)
        lettuce_by_base[base].append(b["id"])
        # Also allow exact match
        if code != base:
            lettuce_by_base[code].append(b["id"])

    print(f"  Loaded {len(cuke_list)} cuke + {len(lettuce_codes)} lettuce batches")
    return cuke_list, lettuce_by_base


def match_cuke_batches(cycle: str, cuke_list) -> list[str]:
    """Return batch IDs whose batch_code starts with the given cycle prefix."""
    if not cycle:
        return []
    matches = []
    for code, bid in cuke_list:
        if code.startswith(cycle):
            matches.append(bid)
    return matches


def match_lettuce_batches(cycle_cell: str, lettuce_by_base) -> list[str]:
    """Split lettuce cycle cell on '+' and find all matching batch IDs.

    Returns deduped list.
    """
    if not cycle_cell:
        return []
    seen = set()
    matches = []
    for part in str(cycle_cell).split("+"):
        code = part.strip()
        if not code:
            continue
        for bid in lettuce_by_base.get(code, []):
            if bid not in seen:
                seen.add(bid)
                matches.append(bid)
    return matches


# ---------------------------------------------------------------------------
# Row builder
# ---------------------------------------------------------------------------

def build_rows(sheet_row, known_sites, cuke_list, lettuce_by_base):
    """Return {tracker, results, photos, seed_batch_links} or {'_skip': reason}."""
    farm_raw = str(sheet_row.get("Farm", "")).strip().lower()
    if farm_raw not in ("cuke", "lettuce"):
        return {"_skip": "no_farm"}

    site_id = normalize_site(sheet_row.get("SiteName"))
    if not site_id or site_id not in known_sites:
        return {"_skip": "unknown_site", "_detail": site_id}

    site_cat = site_category_for(site_id)
    if not site_cat:
        return {"_skip": "no_site_category", "_detail": site_id}

    station = normalize_station(sheet_row.get("Station"))

    reported = parse_datetime(sheet_row.get("ReportedDateTime"))
    checked = parse_datetime(sheet_row.get("CheckedDate"))
    start = reported or checked
    if not start:
        return {"_skip": "no_date"}

    reporter = resolve_user(sheet_row.get("ReportedBy", ""))

    # Notes: Warning, CorrectiveAction, SeedingCycle, Variety, Substrate, Notes + marker
    note_parts = []
    for key_sheet, label in [
        ("SeedingCycle", "Cycle"),
        ("Variety", "Variety"),
        ("Substrate", "Substrate"),
        ("Warning", "Warning"),
        ("CorrectiveAction", "CorrectiveAction"),
        ("Notes", "Notes"),
    ]:
        val = str(sheet_row.get(key_sheet, "")).strip()
        if val:
            note_parts.append(f"{label}: {val}")
    note_parts.append(NOTES_MARKER)
    notes = " | ".join(note_parts)

    tracker_id = str(uuid.uuid4())
    tracker = {
        "id": tracker_id,
        "org_id": ORG_ID,
        "farm_id": farm_raw,
        "site_id": site_id,
        "ops_task_id": OPS_TASK_ID,
        "start_time": start.isoformat(),
        "stop_time": start.isoformat(),
        "is_completed": True,
        "notes": notes,
        "created_by": reporter,
        "updated_by": reporter,
    }

    # Results: one per non-blank measurement column
    results = []
    # Collect candidate metrics for this (farm, site_cat)
    for m in METRICS:
        if m["farm"] != farm_raw or m["site_cat"] != site_cat:
            continue
        gate = m.get("nursery_station_gate")
        if gate is not None and gate != station:
            continue  # nursery EC only applies to matching station
        raw_val = sheet_row.get(m["sheet_col"])
        reading = parse_numeric(raw_val)
        if reading is None:
            continue
        # If this metric has no gate but DripEC for nursery has gates,
        # skip to avoid double-counting the DripEC value.
        if m["site_cat"] == "nursery" and m["sheet_col"] == "DripEC" and gate is None:
            continue
        oor = compute_oor(reading, m.get("min"), m.get("max"))
        results.append({
            "org_id": ORG_ID,
            "farm_id": farm_raw,
            "site_id": site_id,
            "ops_task_tracker_id": tracker_id,
            "grow_monitoring_metric_id": m["id"],
            "monitoring_station": station,
            "reading": reading,
            "reading_boolean": None,
            "reading_enum": None,
            "is_out_of_range": oor,
            "corrective_action": None,
            "notes": None,
            "created_by": reporter,
            "updated_by": reporter,
        })

    # Photos — normalize legacy sheet path to the unified 'images/' bucket layout
    photos = []
    for col in ("Photo01", "Photo02"):
        url = str(sheet_row.get(col, "")).strip()
        if not url:
            continue
        url = url.replace("images/grow_chem/", "images/grow_task/monitoring/")
        photos.append({
            "org_id": ORG_ID,
            "farm_id": farm_raw,
            "ops_task_tracker_id": tracker_id,
            "photo_url": url,
            "caption": None,
            "created_by": reporter,
            "updated_by": reporter,
        })

    # Seed batch links from SeedingCycle column
    cycle_cell = str(sheet_row.get("SeedingCycle", "")).strip()
    if farm_raw == "cuke":
        batch_ids = match_cuke_batches(cycle_cell, cuke_list)
    else:
        batch_ids = match_lettuce_batches(cycle_cell, lettuce_by_base)

    seed_batch_links = []
    for batch_id in batch_ids:
        if batch_id is None:
            continue  # skip unmatched — chk_grow_task_seed_batch_exactly_one requires one id
        # Both FK columns must be present on every row (even as None) because
        # pg_bulk_insert derives its column list from the first row's keys.
        # Omitting one crop's column means the other crop's rows get inserted
        # with that column defaulting to NULL at the DB level.
        row = {
            "org_id": ORG_ID,
            "farm_id": farm_raw,
            "ops_task_tracker_id": tracker_id,
            "grow_cuke_seed_batch_id": batch_id if farm_raw == "cuke" else None,
            "grow_lettuce_seed_batch_id": batch_id if farm_raw == "lettuce" else None,
            "created_by": reporter,
            "updated_by": reporter,
        }
        seed_batch_links.append(row)

    return {
        "tracker": tracker,
        "results": results,
        "photos": photos,
        "seed_batch_links": seed_batch_links,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW MONITORING MIGRATION")
    print("=" * 60)

    clear_existing()
    ensure_metrics(supabase)

    # Load known cuke/lettuce sites
    sites = paginate_select(supabase, "org_site", "id,farm_id")
    known_sites = {s["id"] for s in sites if s.get("farm_id") in ("cuke", "lettuce")}
    print(f"\n  Known cuke/lettuce sites: {len(known_sites)}")

    # Load seed batch lookups for SeedingCycle linking
    print("\nLoading seed batches for SeedingCycle linking...")
    cuke_list, lettuce_by_base = build_batch_lookups(supabase)

    wb = gc.open_by_key(GROW_SHEET_ID)
    print("\nReading grow_chem...")
    records = wb.worksheet("grow_chem").get_all_records()
    print(f"  {len(records)} rows")

    trackers = []
    results = []
    photos = []
    seed_batch_links = []
    skip_counts = {}
    unknown_sites = set()

    for r in records:
        out = build_rows(r, known_sites, cuke_list, lettuce_by_base)
        if "_skip" in out:
            reason = out["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            if "_detail" in out:
                unknown_sites.add(out["_detail"])
            continue
        trackers.append(out["tracker"])
        results.extend(out["results"])
        photos.extend(out["photos"])
        seed_batch_links.extend(out["seed_batch_links"])

    print(f"\n  Built {len(trackers)} trackers, {len(results)} results, "
          f"{len(photos)} photos, {len(seed_batch_links)} seed batch links")
    for reason, cnt in sorted(skip_counts.items()):
        print(f"  Skipped {cnt} rows: {reason}")
    if unknown_sites:
        print(f"  Unknown site values: {sorted(unknown_sites)}")

    with get_pg_conn() as conn:
        print(f"\n--- ops_task_tracker ---")
        pg_bulk_insert(conn, "ops_task_tracker", trackers)
        print(f"  Inserted {len(trackers)} rows")
        print(f"\n--- grow_monitoring_result ---")
        pg_bulk_insert(conn, "grow_monitoring_result", results)
        print(f"  Inserted {len(results)} rows")
        print(f"\n--- grow_task_photo ---")
        pg_bulk_insert(conn, "grow_task_photo", photos)
        print(f"  Inserted {len(photos)} rows")
        print(f"\n--- grow_task_seed_batch ---")
        pg_bulk_insert(conn, "grow_task_seed_batch", seed_batch_links)
        print(f"  Inserted {len(seed_batch_links)} rows")
        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
