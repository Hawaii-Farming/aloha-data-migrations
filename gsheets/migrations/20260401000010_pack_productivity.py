"""
Migrate Pack Productivity Data
================================
Migrates pack_L_prod from legacy Google Sheets into the pack_session
model on Supabase. Replaces the prior ops_task_tracker +
pack_productivity_hour + pack_productivity_hour_fail loader -- those
tables are gone (2026-05-19 pack module rewrite).

Mapping (one Google Sheet row per (pack_date, pack_hour)) →

  pack_session            one per (pack_date, sales_product_id)
                          with harvest_date = pack_date and
                          started_at / stopped_at lifted from notes
                          ("Start LR at 9:44") or defaulted to that
                          product's first/last pack_end_hour.
  pack_session_cases      one per (pack_date, pack_end_hour,
                          sales_product_id, harvest_date) with
                          cases_packed = hourly delta (cumulative
                          → delta still done here).
  pack_session_labor_hour one per (pack_date, pack_end_hour) -- crew
                          counts + fsafe_metal_detected[_at].
  pack_session_fails      one per (pack_date, pack_end_hour,
                          fail_category) when fail_count > 0.
  pack_session_leftover   one per pack_date -- LeftoverPounds →
                          leftover_lettuce, wr_leftover_pounds →
                          leftover_watercress, ar_leftover_pounds →
                          leftover_arugula, summed across all hours.

Source: https://docs.google.com/spreadsheets/d/1XEwjbU_NKNmoUED4w5iuaGV_ilovCJg4f2AkA9lB2cg
  - pack_L_prod (lettuce farm, hourly cadence)

Usage:
    python scripts/migrations/20260401000010_pack_productivity.py

Rerunnable: clears lettuce data from all pack_session_* tables and
the pack_fail_category lookup, then reinserts.
"""

import os
import re
from collections import defaultdict
from datetime import datetime

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://kfwqtaazdankxmdlqdak.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

if not SUPABASE_KEY:
    try:
        with open(".env") as f:
            for line in f:
                if line.startswith("SUPABASE_SERVICE_KEY="):
                    SUPABASE_KEY = line.strip().split("=", 1)[1]
    except FileNotFoundError:
        pass

AUDIT_USER = "data@hawaiifarming.com"
ORG_ID = "hawaii_farming"
FARM_ID = "Lettuce"

PACK_SHEET_ID = "1XEwjbU_NKNmoUED4w5iuaGV_ilovCJg4f2AkA9lB2cg"

# Product case columns → sales_product.id
PRODUCT_COLS = {
    "LRCases": "LR",
    "LFCases": "LF",
    "LWCases": "LW",
    "WRCases": "WR",
    "wf_cases": "WF",
    "ar_cases": "AR",
    "af_cases": "AF",
}

# Leftover columns → pack_session_leftover.<column>
# LeftoverPounds (general) is treated as lettuce per the schema layout.
LEFTOVER_COLS = {
    "LeftoverPounds":      "leftover_lettuce",
    "wr_leftover_pounds":  "leftover_watercress",
    "ar_leftover_pounds":  "leftover_arugula",
}

# Fail columns → pack_fail_category.id
FAIL_COLS = {
    "FilmFails":        "Film",
    "TrayFails":        "Tray",
    "PrinterFails":     "Printer",
    "LeavesFails":      "Leaves",
    "RidgesFails":      "Ridges",
    "UnexplainedFails": "Unexplained",
}

# Hour parsing: "10:00 AM" → 10, "1:00 PM" → 13
HOUR_MAP = {
    "8:00 AM": 8, "9:00 AM": 9, "10:00 AM": 10, "11:00 AM": 11,
    "12:00 PM": 12, "1:00 PM": 13, "2:00 PM": 14, "3:00 PM": 15,
    "4:00 PM": 16, "5:00 PM": 17, "6:00 PM": 18, "7:00 PM": 19,
    "8:00 PM": 20,
}

# Parse metal detection time from notes (e.g. "MD: 10:06", "MD 12:04", "MO: 5:04")
MD_REGEX = re.compile(r"M[DO]:?\s*(\d{1,2}):(\d{2})", re.IGNORECASE)

# Parse product start/finish times from notes.
# Patterns: "Start LR at 9:44", "LR Start at 9:30", "LR start at 10:45"
#           "Finished LR at 11:23", "LR finish at 10:35", "Finished WR at 1:51"
PRODUCT_CODES = {"LR", "LF", "LW", "WR", "WF", "AR", "AF"}
START_REGEX = re.compile(
    r"(?:Start\s+(\w{2})\s+at\s+(\d{1,2}):(\d{2}))|(?:(\w{2})\s+[Ss]tart\s+at\s+(\d{1,2}):(\d{2}))",
    re.IGNORECASE,
)
FINISH_REGEX = re.compile(
    r"(?:Finish(?:ed)?\s+(\w{2})\s+at\s+(\d{1,2}):(\d{2}))|(?:(\w{2})\s+[Ff]inish(?:ed)?\s+at\s+(\d{1,2}):(\d{2}))",
    re.IGNORECASE,
)


def _to_timestamp(pack_date, hour, minute):
    """Convert hour:minute to a timestamp, adjusting for PM if needed."""
    h = int(hour)
    m = int(minute)
    if h < 7:
        h += 12
    return f"{pack_date}T{h:02d}:{m:02d}:00"


def parse_product_times(notes, pack_date):
    """Extract product start/finish times from notes.

    Returns dict: { product_id: { "start": timestamp, "finish": timestamp } }
    """
    if not notes:
        return {}

    times = {}

    for m in START_REGEX.finditer(notes):
        code = (m.group(1) or m.group(4) or "").upper()
        hour = m.group(2) or m.group(5)
        minute = m.group(3) or m.group(6)
        if code in PRODUCT_CODES and hour and minute:
            times.setdefault(code, {})
            times[code]["start"] = _to_timestamp(pack_date, hour, minute)

    for m in FINISH_REGEX.finditer(notes):
        code = (m.group(1) or m.group(4) or "").upper()
        hour = m.group(2) or m.group(5)
        minute = m.group(3) or m.group(6)
        if code in PRODUCT_CODES and hour and minute:
            times.setdefault(code, {})
            times[code]["finish"] = _to_timestamp(pack_date, hour, minute)

    return times


def parse_md_time(notes, pack_date):
    """Extract metal_detected_at timestamp from notes."""
    if not notes:
        return None
    m = MD_REGEX.search(notes)
    if not m:
        return None
    hour = int(m.group(1))
    minute = int(m.group(2))
    if hour < 7:
        hour += 12
    return f"{pack_date}T{hour:02d}:{minute:02d}:00"


# ─────────────────────────────────────────────────────────────
# STANDARD HELPERS
# ─────────────────────────────────────────────────────────────

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list):
    """Insert rows in batches of 100. Returns inserted data."""
    print(f"\n--- {table} ---")
    all_data = []
    if rows:
        for i in range(0, len(rows), 100):
            batch = rows[i:i + 100]
            result = supabase.table(table).insert(batch).execute()
            all_data.extend(result.data)
        print(f"  Inserted {len(rows)} rows")
    return all_data


def parse_date(date_str):
    if not date_str or not str(date_str).strip():
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def safe_numeric(val, default=0):
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def safe_int(val, default=None):
    try:
        v = str(val).strip().replace(",", "")
        return int(float(v)) if v else default
    except (ValueError, TypeError):
        return default


def parse_bool(val):
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def get_sheets():
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# FAIL CATEGORIES (lookup table)
# ─────────────────────────────────────────────────────────────

def migrate_fail_categories(supabase):
    """Seed the 7 pack_fail_category rows for the lettuce farm.

    Renamed from pack_productivity_fail_category by the 2026-05-19 pack
    module rewrite; same row set, same display_order semantics.
    """
    print("\nClearing pack_session_fails + pack_fail_category...")
    supabase.table("pack_session_fails") \
        .delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_fail_category") \
        .delete().neq("id", "__none__").execute()

    categories = [
        ("Film",        1, False),
        ("Tray",        2, False),
        ("Printer",     3, False),
        ("Leaves",      4, False),
        ("Ridges",      5, False),
        ("Unexplained", 6, False),
        ("Total",       7, True),
    ]

    rows = [
        audit({
            "id": name,
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "display_order": order,
            "is_active": active,
        })
        for name, order, active in categories
    ]

    insert_rows(supabase, "pack_fail_category", rows)


# ─────────────────────────────────────────────────────────────
# PACK PRODUCTIVITY → pack_session model
# ─────────────────────────────────────────────────────────────

def migrate_pack_productivity(supabase, gc):
    """Migrate pack_L_prod into the pack_session model.

    For each pack_date in the sheet:
      1. Convert cumulative case counts to hourly deltas per product.
      2. Insert one pack_session row per active product (harvest_date =
         pack_date; started_at/stopped_at from notes or hour fallback).
      3. Insert hourly pack_session_cases for every product with a
         positive delta.
      4. Insert one pack_session_labor_hour row per hour (crew counts +
         metal-detected flag/time).
      5. Insert pack_session_fails rows for each non-zero fail column.
      6. Insert one pack_session_leftover row per day (summed across
         hours by crop: LeftoverPounds→lettuce, wr_*→watercress,
         ar_*→arugula).
    """
    wb = gc.open_by_key(PACK_SHEET_ID)
    data = wb.worksheet("pack_L_prod").get_all_records()

    print(f"\nProcessing {len(data)} productivity rows...")

    # Group by date, sort by hour
    by_date = defaultdict(list)
    for r in data:
        pack_date = parse_date(r.get("PackDate"))
        pack_hour_str = str(r.get("PackHour", "")).strip()
        if not pack_date or pack_hour_str not in HOUR_MAP:
            continue
        hour_num = HOUR_MAP[pack_hour_str]
        by_date[pack_date].append((hour_num, r))

    for d in by_date:
        by_date[d].sort(key=lambda x: x[0])

    print(f"  {len(by_date)} unique pack dates")

    # Clear lettuce data from the pack_session tree.
    # pack_session children join by natural key (no FK to pack_session.id),
    # so each table needs its own DELETE.
    print("\nClearing pack_session model (lettuce)...")
    for tbl in (
        "pack_session_fails",
        "pack_session_cases",
        "pack_session_labor_hour",
        "pack_session_leftover",
        "pack_session",
    ):
        supabase.table(tbl).delete().eq("farm_id", FARM_ID).execute()
    print("  Cleared")

    session_rows = []
    cases_rows = []
    labor_rows = []
    fails_rows = []
    leftover_rows = []

    for pack_date in sorted(by_date.keys()):
        hours = by_date[pack_date]
        harvest_date = pack_date  # pack_L_prod has no HarvestDate

        # Cumulative → delta per product per hour
        prev_cumulative = {}
        hour_deltas = []  # list of (hour_num, row, {pid: delta_int})
        for hour_num, r in hours:
            deltas = {}
            for col, pid in PRODUCT_COLS.items():
                cumulative = safe_numeric(r.get(col), default=None)
                if cumulative is None:
                    continue
                prev = prev_cumulative.get(pid, 0)
                delta = max(0, cumulative - prev)
                if delta > 0 or cumulative > 0:
                    deltas[pid] = int(delta)
                prev_cumulative[pid] = cumulative
            hour_deltas.append((hour_num, r, deltas))

        # Active products on this day, ordered by first appearance.
        product_order = []
        product_first_hour = {}
        product_last_hour = {}
        for hour_num, _, deltas in hour_deltas:
            for pid, d in deltas.items():
                if d > 0:
                    if pid not in product_first_hour:
                        product_order.append(pid)
                        product_first_hour[pid] = hour_num
                    product_last_hour[pid] = hour_num

        if not product_order:
            continue

        # First reporter on the day wins for created_by on the parent rows.
        first_reporter = AUDIT_USER
        for _, r, _ in hour_deltas:
            rb = str(r.get("ReportedBy", "")).strip().lower()
            if rb:
                first_reporter = rb
                break

        # Parse product start/finish times from notes across all hours.
        product_times = {}
        for _, r, _ in hour_deltas:
            notes = str(r.get("Notes", "")).strip()
            parsed = parse_product_times(notes, pack_date)
            for pid, ts in parsed.items():
                product_times.setdefault(pid, {})
                if "start" in ts and "start" not in product_times[pid]:
                    product_times[pid]["start"] = ts["start"]
                if "finish" in ts:
                    product_times[pid]["finish"] = ts["finish"]

        # pack_session rows (one per (pack_date, product))
        for pid in product_order:
            first_h = product_first_hour[pid]
            last_h = product_last_hour[pid]
            started_at = (product_times.get(pid, {}).get("start")
                          or f"{pack_date}T{first_h:02d}:00:00")
            stopped_at = (product_times.get(pid, {}).get("finish")
                          or f"{pack_date}T{last_h:02d}:00:00")
            session_rows.append({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "sales_product_id": pid,
                "pack_date": pack_date,
                "harvest_date": harvest_date,
                "started_at": started_at,
                "stopped_at": stopped_at,
                "created_by": first_reporter,
                "updated_by": first_reporter,
            })

        # Accumulate per-day leftover by crop column.
        day_leftover = {col: 0.0 for col in LEFTOVER_COLS.values()}

        # Hour-level rows
        for hour_num, r, deltas in hour_deltas:
            reported_by = str(r.get("ReportedBy", "")).strip().lower() or AUDIT_USER
            pack_end_hour = f"{pack_date}T{hour_num:02d}:00:00"
            notes_raw = str(r.get("Notes", "")).strip() or None

            # pack_session_labor_hour (one row per clock hour)
            is_md = parse_bool(r.get("MD"))
            md_at = parse_md_time(notes_raw, pack_date) if is_md else None
            if is_md and not md_at:
                md_at = pack_end_hour
            labor_rows.append({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "pack_date": pack_date,
                "pack_end_hour": pack_end_hour,
                "catchers": safe_int(r.get("Catchers")) or 0,
                "packers":  safe_int(r.get("Packers"))  or 0,
                "mixers":   safe_int(r.get("Mixers"))   or 0,
                "boxers":   safe_int(r.get("Boxers"))   or 0,
                "fsafe_metal_detected": is_md,
                "fsafe_metal_detected_at": md_at,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

            # pack_session_cases (one row per (hour, product) with delta > 0)
            for pid, delta in deltas.items():
                if delta <= 0:
                    continue
                cases_rows.append({
                    "org_id": ORG_ID,
                    "farm_id": FARM_ID,
                    "pack_date": pack_date,
                    "harvest_date": harvest_date,
                    "pack_end_hour": pack_end_hour,
                    "sales_product_id": pid,
                    "cases_packed": delta,
                    "created_by": reported_by,
                    "updated_by": reported_by,
                })

            # pack_session_fails (per category)
            for fcol, fcat_id in FAIL_COLS.items():
                fval = safe_int(r.get(fcol))
                if fval and fval > 0:
                    fails_rows.append({
                        "org_id": ORG_ID,
                        "farm_id": FARM_ID,
                        "pack_date": pack_date,
                        "pack_end_hour": pack_end_hour,
                        "pack_fail_category_id": fcat_id,
                        "fail_count": fval,
                        "created_by": reported_by,
                        "updated_by": reported_by,
                    })

            # Leftover accumulation
            for lcol, target_col in LEFTOVER_COLS.items():
                lval = safe_numeric(r.get(lcol), default=0)
                if lval:
                    day_leftover[target_col] += lval

        # pack_session_leftover (one row per day, only if any non-zero)
        if any(v > 0 for v in day_leftover.values()):
            leftover_rows.append({
                "org_id": ORG_ID,
                "farm_id": FARM_ID,
                "pack_date": pack_date,
                "leftover_lettuce":    day_leftover["leftover_lettuce"],
                "leftover_watercress": day_leftover["leftover_watercress"],
                "leftover_arugula":    day_leftover["leftover_arugula"],
                "created_by": first_reporter,
                "updated_by": first_reporter,
            })

    insert_rows(supabase, "pack_session",            session_rows)
    insert_rows(supabase, "pack_session_cases",      cases_rows)
    insert_rows(supabase, "pack_session_labor_hour", labor_rows)
    insert_rows(supabase, "pack_session_fails",      fails_rows)
    insert_rows(supabase, "pack_session_leftover",   leftover_rows)


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("PACK PRODUCTIVITY MIGRATION (pack_session model)")
    print("=" * 60)

    migrate_fail_categories(supabase)
    migrate_pack_productivity(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
