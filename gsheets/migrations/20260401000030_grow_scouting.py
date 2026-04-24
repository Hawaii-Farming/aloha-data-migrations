"""
Migrate Scouting Events + Observations
========================================
Two sheets into three tables:
  - grow_scouting (500 rows) -> ops_task_tracker (ops_task_name=scouting)
  - grow_scouting_observations (500 rows) -> grow_scout_result
    Photos from observation rows -> grow_task_photo (per tracker)

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_scouting: one row per scouting event (farm, site, row, bag, etc.)
  - grow_scouting_observations: one row per pest/disease observed, with
    up to 3 photos

Pest/disease classification (sheet pest_type -> DB):
  pests:   Leaf miner adult -> leafminer
           Thrip            -> thrips
           Shore fly        -> shore_fly
           Fungus gnats     -> fungus_gnat
           Whitefly         -> whitefly
           Aphid            -> aphid
           Moth             -> moth (auto-created)
           Drosophila sp.   -> drosophila (auto-created)
  diseases: Mildew          -> powdery_mildew
            Roots           -> root_rot

Severity: Low->low, Medium/Moderate->moderate, High->high, Critical->severe

Extra context stored in ops_task_tracker.notes:
  - site_side, site_row_number, bag_number (cuke-specific)
  - seed_name, seeding_cycle, variety
  - sheet comments, corrective_actions_taken
  - scouting_id (hex) for cross-reference
  - part_of_plant + adults_in_quadrant (from each observation row)

Photos: up to 3 per observation -> grow_task_photo rows with caption
  "Obs {observation_id}: {part_of_plant} - {pest_type}"

Rerunnable: identifies our trackers via "Legacy scouting migration" marker.

Usage:
    python migrations/20260401000031_grow_scouting.py
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
NOTES_MARKER = "Legacy scouting migration"
OPS_TASK_ID = "scouting"

# Pest type (sheet lowercase) -> (kind, grow_pest/disease id)
PEST_TYPE_MAP = {
    "leaf miner adult": ("pest", "leafminer"),
    "thrip":            ("pest", "thrips"),
    "mildew":           ("disease", "powdery_mildew"),
    "shore fly":        ("pest", "shore_fly"),
    "fungus gnats":     ("pest", "fungus_gnat"),
    "whitefly":         ("pest", "whitefly"),
    "moth":             ("pest", "moth"),
    "roots":            ("disease", "root_rot"),
    "aphid":            ("pest", "aphid"),
    "drosophila sp.":   ("pest", "drosophila"),
}

# These pest/disease IDs are auto-created if missing
AUTO_CREATE_PESTS = [
    ("moth", "Moth"),
    ("drosophila", "Drosophila"),
]

SEVERITY_MAP = {
    "low": "low",
    "medium": "moderate",
    "moderate": "moderate",
    "high": "high",
    "critical": "severe",
    "severe": "severe",
}


# ---------------------------------------------------------------------------
# Helpers
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


def normalize_site(farm: str, site: str) -> str:
    """Normalize site name to org_site.id.

    Cuke uses '05' (zero-padded), 'HI' lowercase.
    Lettuce uses 'P4' -> 'p4'. 'GH' -> 'gh'.
    """
    s = str(site).strip().lower()
    if not s:
        return ""
    if s.isdigit() and len(s) == 1:
        s = s.zfill(2)
    return s


def resolve_farm(raw: str) -> str | None:
    s = str(raw).strip().lower()
    return s if s in ("cuke", "lettuce") else None


def resolve_user(raw: str) -> str:
    s = str(raw).strip().lower()
    return s if "@" in s else AUDIT_USER


# ---------------------------------------------------------------------------
# Setup: auto-create missing pests
# ---------------------------------------------------------------------------

def ensure_pests_and_diseases(supabase):
    """Auto-create any missing pest/disease rows referenced by PEST_TYPE_MAP."""
    existing_pests = {p["id"] for p in supabase.table("grow_pest").select("name").execute().data}
    existing_diseases = {d["id"] for d in supabase.table("grow_disease").select("name").execute().data}

    # Check PEST_TYPE_MAP for any missing
    pest_rows = []
    disease_rows = []
    for kind, target_id in PEST_TYPE_MAP.values():
        if kind == "pest" and target_id not in existing_pests:
            # Look up auto-create spec
            for pid, pname in AUTO_CREATE_PESTS:
                if pid == target_id:
                    pest_rows.append({
                        "id": pid,
                        "name": pname,
                        "description": None,
                        "created_by": AUDIT_USER,
                        "updated_by": AUDIT_USER,
                    })
                    existing_pests.add(pid)
                    break
        elif kind == "disease" and target_id not in existing_diseases:
            # No auto-create specs for diseases currently — log
            print(f"  WARNING: disease '{target_id}' not in grow_disease and no auto-create spec")

    if pest_rows:
        print(f"\n--- grow_pest (auto-create missing) ---")
        supabase.table("grow_pest").upsert(pest_rows).execute()
        print(f"  Upserted {len(pest_rows)} rows: {[r['id'] for r in pest_rows]}")

    if disease_rows:
        print(f"\n--- grow_disease (auto-create missing) ---")
        supabase.table("grow_disease").upsert(disease_rows).execute()
        print(f"  Upserted {len(disease_rows)} rows")


# ---------------------------------------------------------------------------
# Clear existing legacy rows for rerun
# ---------------------------------------------------------------------------

def clear_existing():
    """Delete previously-migrated scouting rows (identified by notes marker)."""
    print("\nClearing existing legacy scouting rows...")
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            # 1. grow_scout_result linked to our trackers
            cur.execute(
                """
                DELETE FROM grow_scout_result
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_name = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d1 = cur.rowcount
            # 2. grow_task_photo linked to our trackers
            cur.execute(
                """
                DELETE FROM grow_task_photo
                WHERE ops_task_tracker_id IN (
                    SELECT id FROM ops_task_tracker
                    WHERE ops_task_name = %s AND notes LIKE %s
                )
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d2 = cur.rowcount
            # 3. Our trackers
            cur.execute(
                """
                DELETE FROM ops_task_tracker
                WHERE ops_task_name = %s AND notes LIKE %s
                """,
                (OPS_TASK_ID, f"%{NOTES_MARKER}%"),
            )
            d3 = cur.rowcount
        conn.commit()
    print(f"  Deleted: {d1} grow_scout_result, {d2} grow_task_photo, {d3} ops_task_tracker")


# ---------------------------------------------------------------------------
# Tracker builder (from grow_scouting rows)
# ---------------------------------------------------------------------------

def build_trackers(scouting_records, known_sites):
    """Return (trackers_by_scouting_id, skip_counts, unknown_sites).

    trackers_by_scouting_id: {scouting_id (hex) -> tracker dict}
    """
    trackers_by_id = {}
    skip_counts = {}
    unknown_sites = set()

    for r in scouting_records:
        scouting_id = str(r.get("scouting_id", "")).strip()
        if not scouting_id:
            skip_counts["no_scouting_id"] = skip_counts.get("no_scouting_id", 0) + 1
            continue

        farm = resolve_farm(r.get("farm", ""))
        if not farm:
            skip_counts["no_farm"] = skip_counts.get("no_farm", 0) + 1
            continue

        site_id = normalize_site(farm, r.get("site", ""))
        if not site_id or site_id not in known_sites:
            skip_counts["unknown_site"] = skip_counts.get("unknown_site", 0) + 1
            unknown_sites.add(site_id)
            continue

        created_at = parse_datetime(r.get("created_at"))
        scouting_date = parse_datetime(r.get("scouting_date"))
        # Prefer created_at; fall back to scouting_date
        start_dt = created_at or scouting_date
        if not start_dt:
            skip_counts["no_date"] = skip_counts.get("no_date", 0) + 1
            continue

        reporter = resolve_user(r.get("created_by", ""))

        # Build notes with all the extra sheet context
        note_parts = [f"ScoutingID: {scouting_id}"]
        for key_sheet, key_label in [
            ("site_side", "Side"),
            ("site_row_number", "Row"),
            ("bag_number", "Bag"),
            ("seed_name", "Seed"),
            ("seeding_cycle", "Cycle"),
            ("variety", "Variety"),
            ("comments", "Comments"),
            ("corrective_actions_taken", "Corrective"),
        ]:
            val = str(r.get(key_sheet, "")).strip()
            if val:
                note_parts.append(f"{key_label}: {val}")
        note_parts.append(NOTES_MARKER)
        notes = " | ".join(note_parts)

        tracker_uuid = str(uuid.uuid4())
        trackers_by_id[scouting_id] = {
            "id": tracker_uuid,
            "org_id": ORG_ID,
            "farm_name": farm,
            "site_id": site_id,
            "ops_task_name": OPS_TASK_ID,
            "start_time": start_dt.isoformat(),
            "stop_time": start_dt.isoformat(),
            "is_completed": True,
            "notes": notes,
            "created_by": reporter,
            "updated_by": reporter,
        }

    return trackers_by_id, skip_counts, unknown_sites


# ---------------------------------------------------------------------------
# Scout result + photo builders (from grow_scouting_observations rows)
# ---------------------------------------------------------------------------

def build_results_and_photos(observation_records, trackers_by_id, existing_pest_ids, existing_disease_ids):
    """Return (scout_results, photos, skip_counts, unknown_pests).

    scout_results: list of grow_scout_result row dicts.
    photos: list of grow_task_photo row dicts.
    """
    scout_results = []
    photos = []
    skip_counts = {}
    unknown_pests = set()

    for r in observation_records:
        observation_id = str(r.get("observation_id", "")).strip()
        scouting_id = str(r.get("scouting_id", "")).strip()

        tracker = trackers_by_id.get(scouting_id)
        if not tracker:
            skip_counts["orphan_observation"] = skip_counts.get("orphan_observation", 0) + 1
            continue

        pest_type_raw = str(r.get("pest_type", "")).strip()
        pest_key = pest_type_raw.lower()
        mapped = PEST_TYPE_MAP.get(pest_key)
        if not mapped:
            skip_counts["unknown_pest_type"] = skip_counts.get("unknown_pest_type", 0) + 1
            unknown_pests.add(pest_type_raw)
            continue
        kind, target_id = mapped
        if kind == "pest" and target_id not in existing_pest_ids:
            skip_counts["missing_pest_row"] = skip_counts.get("missing_pest_row", 0) + 1
            continue
        if kind == "disease" and target_id not in existing_disease_ids:
            skip_counts["missing_disease_row"] = skip_counts.get("missing_disease_row", 0) + 1
            continue

        sev_raw = str(r.get("severity_level", "")).strip().lower()
        severity = SEVERITY_MAP.get(sev_raw)
        if not severity:
            skip_counts["no_severity"] = skip_counts.get("no_severity", 0) + 1
            continue

        # Build notes with context specific to this observation
        part_of_plant = str(r.get("part_of_plant", "")).strip()
        adults = str(r.get("adults_in_quadrant", "")).strip()
        comments = str(r.get("comments", "")).strip()

        obs_note_parts = []
        if observation_id:
            obs_note_parts.append(f"ObsID: {observation_id}")
        if part_of_plant:
            obs_note_parts.append(f"Part: {part_of_plant}")
        if adults:
            obs_note_parts.append(f"Adults: {adults}")
        if comments:
            obs_note_parts.append(f"Comments: {comments}")
        obs_notes = " | ".join(obs_note_parts) if obs_note_parts else None

        reporter = resolve_user(r.get("created_by", ""))

        result = {
            "org_id": ORG_ID,
            "farm_name": tracker["farm_name"],
            "ops_task_tracker_id": tracker["id"],
            "site_id": None,  # row-level sites not modeled; greenhouse on tracker
            "observation_type": kind,
            "grow_pest_name": target_id if kind == "pest" else None,
            "grow_disease_name": target_id if kind == "disease" else None,
            # disease_infection_stage not in source data; leave NULL (allowed)
            "disease_infection_stage": None,
            "severity_level": severity,
            "notes": obs_notes,
            "created_by": reporter,
            "updated_by": reporter,
        }
        scout_results.append(result)

        # Photos (up to 3 per observation, captioned with observation context)
        caption_base = f"Obs {observation_id}: {part_of_plant or '?'} - {pest_type_raw}"
        for i in (1, 2, 3):
            url = str(r.get(f"photo_0{i}", "")).strip()
            if not url:
                continue
            # Normalize legacy sheet path to the unified 'images/' bucket layout
            url = url.replace("grow_scouting_observations_Images/", "images/grow_task/scouting/")
            photos.append({
                "org_id": ORG_ID,
                "farm_name": tracker["farm_name"],
                "ops_task_tracker_id": tracker["id"],
                "photo_url": url,
                "caption": caption_base,
                "created_by": reporter,
                "updated_by": reporter,
            })

    return scout_results, photos, skip_counts, unknown_pests


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW SCOUTING MIGRATION")
    print("=" * 60)

    clear_existing()
    ensure_pests_and_diseases(supabase)

    # Load known sites for cuke/lettuce
    sites = paginate_select(supabase, "org_site", "id,farm_name,org_site_subcategory_id")
    known_sites = {
        s["id"] for s in sites
        if s.get("farm_name") in ("cuke", "lettuce")
        and s.get("org_site_subcategory_id") in ("greenhouse", "pond", None)
    }
    print(f"\n  Known cuke/lettuce sites: {len(known_sites)}")

    # Load pest/disease IDs for validation
    existing_pest_ids = {p["id"] for p in supabase.table("grow_pest").select("name").execute().data}
    existing_disease_ids = {d["id"] for d in supabase.table("grow_disease").select("name").execute().data}

    wb = gc.open_by_key(GROW_SHEET_ID)
    print("\nReading grow_scouting...")
    scouting = wb.worksheet("grow_scouting").get_all_records()
    print(f"  {len(scouting)} rows")

    print("Reading grow_scouting_observations...")
    observations = wb.worksheet("grow_scouting_observations").get_all_records()
    print(f"  {len(observations)} rows")

    # Build trackers from scouting rows
    trackers_by_id, scout_skip, unknown_sites = build_trackers(scouting, known_sites)
    print(f"\n  Built {len(trackers_by_id)} trackers")
    for reason, cnt in sorted(scout_skip.items()):
        print(f"  Skipped {cnt} scouting rows: {reason}")
    if unknown_sites:
        print(f"  Unknown sites: {sorted(unknown_sites)}")

    # Build scout_result + photos from observation rows
    scout_results, photos, obs_skip, unknown_pests = build_results_and_photos(
        observations, trackers_by_id, existing_pest_ids, existing_disease_ids,
    )
    print(f"\n  Built {len(scout_results)} scout_result rows, {len(photos)} photo rows")
    for reason, cnt in sorted(obs_skip.items()):
        print(f"  Skipped {cnt} observation rows: {reason}")
    if unknown_pests:
        print(f"  Unknown pest types: {sorted(unknown_pests)}")

    # Bulk insert via psycopg2
    trackers = list(trackers_by_id.values())
    with get_pg_conn() as conn:
        print(f"\n--- ops_task_tracker ---")
        pg_bulk_insert(conn, "ops_task_tracker", trackers)
        print(f"  Inserted {len(trackers)} rows")
        print(f"\n--- grow_scout_result ---")
        pg_bulk_insert(conn, "grow_scout_result", scout_results)
        print(f"  Inserted {len(scout_results)} rows")
        print(f"\n--- grow_task_photo ---")
        pg_bulk_insert(conn, "grow_task_photo", photos)
        print(f"  Inserted {len(photos)} rows")
        conn.commit()

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
