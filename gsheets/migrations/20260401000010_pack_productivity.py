"""
Migrate Pack Productivity Data
================================
Migrates pack_L_prod from legacy Google Sheets to Supabase.

Converts cumulative case counts to hourly deltas and creates the full
ops_task_tracker → pack_productivity_hour → pack_productivity_hour_fail
chain for each product packed on each day.

Source: https://docs.google.com/spreadsheets/d/1XEwjbU_NKNmoUED4w5iuaGV_ilovCJg4f2AkA9lB2cg
  - pack_L_prod: 1907 rows → ops_task_tracker + pack_productivity_hour + pack_productivity_hour_fail

Usage:
    python scripts/migrations/20260401000010_pack_productivity.py

Rerunnable: clears and reinserts all data on each run.
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

PACK_SHEET_ID = "1XEwjbU_NKNmoUED4w5iuaGV_ilovCJg4f2AkA9lB2cg"

# Product case columns → sales_product_id
PRODUCT_COLS = {
    "LRCases": "lr",
    "LFCases": "lf",
    "LWCases": "lw",
    "WRCases": "wr",
    "wf_cases": "wf",
    "ar_cases": "ar",
    "af_cases": "af",
}

# Leftover columns → sales_product_id
LEFTOVER_COLS = {
    "LeftoverPounds": None,         # general leftover (assigned to first active product)
    "wr_leftover_pounds": "wr",
    "ar_leftover_pounds": "ar",
}

# Fail columns → fail category id
FAIL_COLS = {
    "FilmFails": "film",
    "TrayFails": "tray",
    "PrinterFails": "printer",
    "LeavesFails": "leaves",
    "RidgesFails": "ridges",
    "UnexplainedFails": "unexplained",
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

# Parse product start/finish times from notes
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
            pid = code.lower()
            times.setdefault(pid, {})
            times[pid]["start"] = _to_timestamp(pack_date, hour, minute)

    for m in FINISH_REGEX.finditer(notes):
        code = (m.group(1) or m.group(4) or "").upper()
        hour = m.group(2) or m.group(5)
        minute = m.group(3) or m.group(6)
        if code in PRODUCT_CODES and hour and minute:
            pid = code.lower()
            times.setdefault(pid, {})
            times[pid]["finish"] = _to_timestamp(pack_date, hour, minute)

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
    # Assume PM if hour < 7 (packing doesn't happen before 7 AM)
    if hour < 7:
        hour += 12
    return f"{pack_date}T{hour:02d}:{minute:02d}:00"


# ─────────────────────────────────────────────────────────────
# STANDARD HELPERS
# ─────────────────────────────────────────────────────────────

def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()


def audit(row: dict) -> dict:
    """Add audit fields to a row."""
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
    """Parse date string to YYYY-MM-DD or None."""
    if not date_str or not str(date_str).strip():
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def safe_int(val, default=None):
    """Parse an integer value or return default."""
    try:
        v = str(val).strip().replace(",", "")
        return int(float(v)) if v else default
    except (ValueError, TypeError):
        return default


def parse_bool(val):
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# FAIL CATEGORIES
# ─────────────────────────────────────────────────────────────

def migrate_fail_categories(supabase):
    """Seed the 6 fail categories for the lettuce farm."""
    print("\nClearing pack_productivity_fail_category...")
    supabase.table("pack_productivity_hour_fail").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_productivity_fail_category").delete().neq("name", "__none__").execute()

    categories = [
        ("film", "Film", 1, False),
        ("tray", "Tray", 2, False),
        ("printer", "Printer", 3, False),
        ("leaves", "Leaves", 4, False),
        ("ridges", "Ridges", 5, False),
        ("unexplained", "Unexplained", 6, False),
        ("total", "Total", 7, True),
    ]

    rows = [
        audit({
            "id": cat_id,
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "name": name,
            "display_order": order,
            "is_active": active,
        })
        for cat_id, name, order, active in categories
    ]

    insert_rows(supabase, "pack_productivity_fail_category", rows)


# ─────────────────────────────────────────────────────────────
# PRODUCTIVITY MIGRATION
# ─────────────────────────────────────────────────────────────

def migrate_pack_productivity(supabase, gc):
    """Migrate pack_L_prod → ops_task_tracker + pack_productivity_hour + pack_productivity_hour_fail.

    Legacy data uses cumulative case counts per product per day. This migration:
    1. Groups rows by date, sorted by hour
    2. Converts cumulative → delta (cases packed in each specific hour)
    3. Identifies product transitions (when a new product starts getting cases)
    4. Creates one ops_task_tracker per product per day
    5. Creates pack_productivity_hour rows with delta cases, linked to the tracker
    6. Creates pack_productivity_hour_fail rows for non-zero fail counts
    """
    wb = gc.open_by_key(PACK_SHEET_ID)
    data = wb.worksheet("pack_L_prod").get_all_records()

    print(f"\nProcessing {len(data)} productivity rows...")

    # --- Group by date, sort by hour ---
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

    # --- Clear existing data (FK order) ---
    print("\nClearing productivity tables...")
    supabase.table("pack_productivity_hour_fail").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_productivity_hour").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    # Clear only packing task trackers created by this migration (loop until empty)
    while True:
        batch = supabase.table("ops_task_tracker").select("id").eq("ops_task_name", "packing").eq("farm_name", "lettuce").limit(100).execute()
        if not batch.data:
            break
        supabase.table("ops_task_tracker").delete().in_("id", [t["id"] for t in batch.data]).execute()
    print("  Cleared")

    # --- Process each day ---
    all_tracker_rows = []
    all_hour_rows = []
    all_fail_rows = []

    for pack_date in sorted(by_date.keys()):
        hours = by_date[pack_date]

        # Compute cumulative → delta per product
        prev_cumulative = {}  # product_id → previous cumulative value
        hour_deltas = []      # (hour_num, row, {product_id: delta_cases})

        for hour_num, r in hours:
            deltas = {}
            for col, product_id in PRODUCT_COLS.items():
                cumulative = safe_numeric(r.get(col), default=None)
                if cumulative is None:
                    continue
                prev = prev_cumulative.get(product_id, 0)
                delta = max(0, cumulative - prev)
                if delta > 0 or cumulative > 0:
                    deltas[product_id] = delta
                prev_cumulative[product_id] = cumulative

            hour_deltas.append((hour_num, r, deltas))

        # Identify which products were active on this day
        day_products = set()
        for _, _, deltas in hour_deltas:
            day_products.update(deltas.keys())

        if not day_products:
            continue

        # Determine product order by first appearance
        product_order = []
        seen_products = set()
        for _, _, deltas in hour_deltas:
            for pid in deltas:
                if pid not in seen_products:
                    product_order.append(pid)
                    seen_products.add(pid)

        # Find first reporter for the day
        first_reporter = AUDIT_USER
        for _, r, _ in hour_deltas:
            rb = str(r.get("ReportedBy", "")).strip().lower()
            if rb:
                first_reporter = rb
                break

        # Create one ops_task_tracker per product per day
        # Track which hours each product was actively being packed
        product_hours = defaultdict(list)  # product_id → [(hour_num, r, delta)]
        for hour_num, r, deltas in hour_deltas:
            for pid, delta in deltas.items():
                if delta > 0:
                    product_hours[pid].append((hour_num, r, delta))

        # Parse product start/finish times from notes across all hours
        product_times = {}  # pid → {"start": ts, "finish": ts}
        for hour_num, r, deltas in hour_deltas:
            notes = str(r.get("Notes", "")).strip()
            parsed = parse_product_times(notes, pack_date)
            for pid, times in parsed.items():
                product_times.setdefault(pid, {})
                if "start" in times and "start" not in product_times[pid]:
                    product_times[pid]["start"] = times["start"]
                if "finish" in times:
                    product_times[pid]["finish"] = times["finish"]

        # Build tracker rows — one per product per day
        trackers_for_day = {}  # product_id → tracker row dict (pre-insert)
        for pid in product_order:
            p_hours = product_hours.get(pid, [])
            if not p_hours:
                continue

            first_hour = p_hours[0][0]
            last_hour = p_hours[-1][0]
            reported_by = str(p_hours[0][1].get("ReportedBy", "")).strip().lower() or AUDIT_USER

            # Use parsed times if available, otherwise fall back to hour boundaries
            start_time = product_times.get(pid, {}).get("start") or f"{pack_date}T{first_hour:02d}:00:00"
            stop_time = product_times.get(pid, {}).get("finish") or f"{pack_date}T{last_hour + 1:02d}:00:00"

            tracker = {
                "org_id": ORG_ID,
                "farm_name": "Lettuce",
                "site_id": "lettuce_ph",
                "ops_task_name": "Packing",
                "sales_product_id": pid,
                "start_time": start_time,
                "stop_time": stop_time,
                "is_completed": True,
                "created_by": reported_by,
                "updated_by": reported_by,
            }
            trackers_for_day[pid] = tracker
            all_tracker_rows.append(tracker)

    # Insert all trackers
    inserted_trackers = insert_rows(supabase, "ops_task_tracker", all_tracker_rows)

    # Build lookup: (date, product_id) → tracker UUID
    tracker_lookup = {}
    for t in inserted_trackers:
        start = t["start_time"]
        # Extract date from start_time
        t_date = start[:10]
        pid = t["sales_product_id"]
        tracker_lookup[(t_date, pid)] = t["id"]

    print(f"  Created {len(inserted_trackers)} task trackers")

    # --- Second pass: build hour rows and fail rows ---
    hour_counter = 0
    pending_fails = {}  # hour_idx → {fail_counts, reported_by}
    for pack_date in sorted(by_date.keys()):
        hours = by_date[pack_date]

        # Recompute deltas (same logic as above)
        prev_cumulative = {}
        for hour_num, r in hours:
            deltas = {}
            for col, product_id in PRODUCT_COLS.items():
                cumulative = safe_numeric(r.get(col), default=None)
                if cumulative is None:
                    continue
                prev = prev_cumulative.get(product_id, 0)
                delta = max(0, cumulative - prev)
                deltas[product_id] = delta
                prev_cumulative[product_id] = cumulative

            # Common fields for this hour
            reported_by = str(r.get("ReportedBy", "")).strip().lower() or AUDIT_USER
            catchers = safe_int(r.get("Catchers")) or 0
            packers = safe_int(r.get("Packers")) or 0
            mixers = safe_int(r.get("Mixers")) or 0
            boxers = safe_int(r.get("Boxers")) or 0
            is_md = parse_bool(r.get("MD"))
            notes = str(r.get("Notes", "")).strip() or None
            pack_end_hour = f"{pack_date}T{hour_num:02d}:00:00"

            # Resolve metal detection timestamp
            md_at = None
            if is_md:
                md_at = parse_md_time(notes, pack_date)
                if not md_at:
                    # Default to pack_end_hour and note the fallback
                    md_at = pack_end_hour
                    notes = f"[MD time defaulted to hour] {notes}" if notes else "[MD time defaulted to hour]"

            # Leftover pounds — assign general leftover to first product with delta > 0
            leftover_by_product = {}
            for lcol, lpid in LEFTOVER_COLS.items():
                lval = safe_numeric(r.get(lcol), default=None)
                if lval and lval > 0:
                    if lpid:
                        leftover_by_product[lpid] = lval
                    else:
                        # General leftover → first active product
                        for pid in deltas:
                            if deltas[pid] > 0:
                                leftover_by_product.setdefault(pid, 0)
                                leftover_by_product[pid] += lval
                                break

            # Fail counts (shared across products — assign to first active product)
            # Use individual categories when available, otherwise use TotalFails as "total"
            fail_counts = {}
            has_individual = False
            for fcol, fcat_id in FAIL_COLS.items():
                fval = safe_int(r.get(fcol))
                if fval and fval > 0:
                    fail_counts[fcat_id] = fval
                    has_individual = True
            if not has_individual:
                total_fails = safe_int(r.get("TotalFails"))
                if total_fails and total_fails > 0:
                    fail_counts["total"] = total_fails

            # Create one pack_productivity_hour per product with delta > 0
            first_product_this_hour = True
            for product_id, delta in deltas.items():
                if delta <= 0:
                    continue

                tracker_id = tracker_lookup.get((pack_date, product_id))
                if not tracker_id:
                    continue

                hour_counter += 1
                hour_idx = len(all_hour_rows)

                hour_row = {
                    "org_id": ORG_ID,
                    "farm_name": "Lettuce",
                    "ops_task_tracker_id": tracker_id,
                    "pack_end_hour": pack_end_hour,
                    "catchers": catchers,
                    "packers": packers,
                    "mixers": mixers,
                    "boxers": boxers,
                    "cases_packed": int(delta),
                    "leftover_pounds": leftover_by_product.get(product_id, 0),
                    "fsafe_metal_detected_at": md_at if first_product_this_hour else None,
                    "notes": notes if first_product_this_hour else None,
                    "created_by": reported_by,
                    "updated_by": reported_by,
                }
                all_hour_rows.append(hour_row)

                # Track fail counts by hour index (resolve to UUID after insert)
                if first_product_this_hour and fail_counts:
                    pending_fails[hour_idx] = {
                        "fail_counts": fail_counts,
                        "reported_by": reported_by,
                    }

                first_product_this_hour = False

    inserted_hours = insert_rows(supabase, "pack_productivity_hour", all_hour_rows)

    # Build fail rows using inserted UUIDs
    for hour_idx, fail_info in pending_fails.items():
        hour_uuid = inserted_hours[hour_idx]["id"]
        for fcat_id, fcount in fail_info["fail_counts"].items():
            all_fail_rows.append({
                "org_id": ORG_ID,
                "farm_name": "Lettuce",
                "pack_productivity_hour_id": hour_uuid,
                "pack_productivity_fail_category_name": fcat_id,
                "fail_count": fcount,
                "created_by": fail_info["reported_by"],
                "updated_by": fail_info["reported_by"],
            })

    insert_rows(supabase, "pack_productivity_hour_fail", all_fail_rows)


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("PACK PRODUCTIVITY MIGRATION")
    print("=" * 60)

    # Step 1: Seed fail categories
    migrate_fail_categories(supabase)

    # Step 2: Productivity data (trackers + hours + fails)
    migrate_pack_productivity(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
