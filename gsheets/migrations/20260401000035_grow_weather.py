"""
Sync greenhouse weather-station readings
=========================================
Nightly load of the weather spreadsheet `weather` tab into
`grow_weather_reading`. One row per ~10-minute sample, 16 sensor
channels. The DLI column from the source is intentionally skipped — it
is derived on demand from inside_par.

Source (https://docs.google.com/spreadsheets/d/1dPUsCbXKg8pmlEa3lylnow5BJKYL0FL8vLyJz3bsfMY):
  weather (gid=64413419) — columns:
    Date, Time, OutsideTemperature, OutsideHumidity,
    OutsideWetBulbTemperature, OutsideDewPointTemperature,
    OutsideWindAverageSpeed, OutsideWindAverageMaxSpeed,
    OutsideWindDirection, OutsideRain, InsidePAR, InsideTemperature,
    InsideHumidity, PowerSupply, AtmosphericPressure, DLI (skipped)

Date+Time are local (HST) wall clock; we attach the HST offset before
storing so the TIMESTAMPTZ column normalizes correctly.

Sheet is treated as the single source of truth: every run wipes the
org-scoped rows and reinserts. ~73k rows -> ~1-2 min insert time.

Usage:
    python gsheets/migrations/20260401000035_grow_weather.py
"""

import csv
import io
import sys
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from supabase import create_client

from gsheets.migrations._config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)


SHEET_ID = SHEET_IDS["weather"]
SHEET_TAB = "weather"

# Station lives in the lettuce greenhouse — readings are scoped to that farm.
FARM_ID = "Lettuce"

# Sheet timestamps are HST wall clock (Hawaii is UTC-10 year round, no DST).
HST = timezone(timedelta(hours=-10))


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, batch_size: int = 500):
    if not rows:
        print(f"  {table}: no rows")
        return
    total_batches = (len(rows) + batch_size - 1) // batch_size
    inserted = 0
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        batch_num = (i // batch_size) + 1
        try:
            supabase.table(table).insert(batch).execute()
            inserted += len(batch)
        except Exception as e:
            print(
                f"  ERROR on batch {batch_num}/{total_batches} "
                f"(rows {i + 1}-{i + len(batch)}): {type(e).__name__}: {e}"
            )
            print(f"  {inserted} rows committed before failure")
            print(f"  Re-run the script to retry — it is idempotent.")
            raise
        if batch_num % 20 == 0 or batch_num == total_batches:
            print(f"  {table}: batch {batch_num}/{total_batches} ({inserted} rows)")
    print(f"  {table}: inserted {inserted} rows")


def fetch_gviz_csv(sheet_id: str, tab: str) -> list[dict]:
    """Fetch one tab as list of dicts via gviz CSV (no auth required)."""
    from urllib.parse import quote
    url = (
        f"https://docs.google.com/spreadsheets/d/{sheet_id}"
        f"/gviz/tq?tqx=out:csv&sheet={quote(tab)}"
    )
    with urllib.request.urlopen(url) as resp:
        raw = resp.read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(raw)))


def parse_reading_at(date_str: str, time_str: str):
    """Combine the sheet's Date + Time columns into a TIMESTAMPTZ in HST."""
    if not date_str or not time_str:
        return None
    date_str = date_str.strip()
    time_str = time_str.strip()
    if not date_str or not time_str:
        return None
    # Date formats observed: M/D/YYYY and MM/DD/YYYY both surface in the sheet.
    parsed_date = None
    for dfmt in ("%m/%d/%Y", "%-m/%-d/%Y"):
        try:
            parsed_date = datetime.strptime(date_str, dfmt).date()
            break
        except ValueError:
            continue
    if parsed_date is None:
        return None
    # Time: "h:mm:ss AM/PM"
    for tfmt in ("%I:%M:%S %p", "%I:%M %p"):
        try:
            parsed_time = datetime.strptime(time_str, tfmt).time()
            break
        except ValueError:
            parsed_time = None
            continue
    if parsed_time is None:
        return None
    return datetime.combine(parsed_date, parsed_time, tzinfo=HST)


def parse_number(s):
    if s is None:
        return None
    s = str(s).strip().replace(",", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def clean(s):
    if s is None:
        return None
    s = str(s).strip()
    return s if s else None


# ---------------------------------------------------------------------------
# Clear
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    print("\nClearing existing rows for this org (sheet is truth)...")
    supabase.table("grow_weather_reading").delete().eq("org_id", ORG_ID).execute()
    print("  Cleared grow_weather_reading")


# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------

def transform(r: dict) -> dict | None:
    reading_at = parse_reading_at(r.get("Date"), r.get("Time"))
    if reading_at is None:
        return None

    return audit({
        "org_id":                          ORG_ID,
        "farm_id":                         FARM_ID,
        "reading_at":                      reading_at.isoformat(),
        "outside_temperature":             parse_number(r.get("OutsideTemperature")),
        "outside_humidity":                parse_number(r.get("OutsideHumidity")),
        "outside_wet_bulb_temperature":    parse_number(r.get("OutsideWetBulbTemperature")),
        "outside_dew_point_temperature":   parse_number(r.get("OutsideDewPointTemperature")),
        "outside_wind_average_speed":      parse_number(r.get("OutsideWindAverageSpeed")),
        "outside_wind_average_max_speed":  parse_number(r.get("OutsideWindAverageMaxSpeed")),
        "outside_wind_direction":          clean(r.get("OutsideWindDirection")),
        "outside_rain":                    parse_number(r.get("OutsideRain")),
        "inside_par":                      parse_number(r.get("InsidePAR")),
        "inside_temperature":              parse_number(r.get("InsideTemperature")),
        "inside_humidity":                 parse_number(r.get("InsideHumidity")),
        "power_supply":                    clean(r.get("PowerSupply")),
        "atmospheric_pressure":            parse_number(r.get("AtmosphericPressure")),
    })


def sync(records) -> list[dict]:
    rows = []
    skipped = 0
    for r in records:
        out = transform(r)
        if out:
            rows.append(out)
        else:
            skipped += 1
    print(f"  {len(records)} sheet rows -> {len(rows)} kept, {skipped} skipped")
    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())

    print("=" * 60)
    print("GROW WEATHER MIGRATION")
    print("=" * 60)

    print(f"\nFetching '{SHEET_TAB}' from sheet {SHEET_ID}...")
    records = fetch_gviz_csv(SHEET_ID, SHEET_TAB)
    print(f"  {len(records)} sheet rows loaded")

    rows = sync(records)

    clear_existing(supabase)

    print(f"\nInserting {len(rows)} weather readings...")
    insert_rows(supabase, "grow_weather_reading", rows)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
