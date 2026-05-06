"""
Pull Crodeon weather-station readings into edi_crodeon_weather.
=================================================================

Direct port of the legacy `fetchNewWeatherData()` Apps Script. Replaces
the old GAS -> Sheet -> Postgres flow with a single API -> Postgres
hop. Same Crodeon API, same connector layout, same unit conversions.

Crodeon emits measurements once per minute. This script does NOT
downsample -- every minute that has a fresh reading lands in the DB
unless it is already there (ON CONFLICT (org_id, reading_at) DO
NOTHING handles re-runs and cron jitter).

Two modes share the same code path:

  * Live mode (default)
        Pulls readings from now()-12 minutes through now(). Idempotent,
        so the every-10-minute cron can fire repeatedly and only new
        per-minute readings get inserted.

  * Backfill mode (CLI args / env vars)
        --since 2024-06-03T00:00:00Z   (or CRODEON_BACKFILL_SINCE=...)
        --until 2026-05-06T00:00:00Z   (or CRODEON_BACKFILL_UNTIL=...)
        Walks the requested range in daily chunks, paginates each chunk,
        bulk-inserts via execute_values.

Endpoints used:
    GET /reporters/{master_id}/sensors                 sensor metadata + per-channel display_unit.exponent
    GET /reporters/{master_id}/measurements?start_time=&end_time=&page_size=&page=
                                                       paginated historical measurements

Connector layout (matches the legacy GAS code):
    CONNECTOR_1  -> Outside  (temperature / humidity / wind / rain / wet bulb / dew point)
    CONNECTOR_2  -> Inside   (PAR; ANALOG channel skipped)
    CONNECTOR_3  -> Inside   (temperature / humidity; wet bulb + dew point skipped)
    INTERNAL     -> ReporterInternal (power supply, atmospheric pressure)

Environment:
    SUPABASE_DB_URL   -- Postgres connection string
    CRODEON_API_KEY   -- key from Crodeon developer portal
"""
import argparse
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from psycopg2.extras import execute_values

sys.path.insert(0, str(Path(__file__).parent))

from _config import _load_env_file  # noqa: E402  triggers .env load
from _pg import get_pg_conn  # noqa: E402

_load_env_file()

ORG_ID = os.environ.get("MIGRATION_ORG_ID", "hawaii_farming")
CRODEON_API_KEY = os.environ.get("CRODEON_API_KEY")
CRODEON_BASE = "https://api.crodeon.com/api/v2"
MASTER_ID = "724566542"

# Hawaii is fixed at UTC-10 year round (no DST). Crodeon timestamps come
# back UTC; we convert to HST wall-clock before storing so the column is
# directly readable in reports without timezone math.
HST = timezone(timedelta(hours=-10))

# How far back the live (cron) mode looks. The cron fires every 10 min;
# 12 min covers normal jitter and lets a missed cron tick recover on
# the next fire.
LIVE_LOOKBACK = timedelta(minutes=12)

# Backfill granularity. The Crodeon API page_size cap appears to be
# around 10,000 items, and a single day produces ~18,700 items, so a
# daily window paginates in 2 calls.
BACKFILL_CHUNK = timedelta(days=1)
PAGE_SIZE = 10000

CONNECTOR_LABELS = {
    "CONNECTOR_1": "Outside",
    "CONNECTOR_2": "Inside",
    "CONNECTOR_3": "Inside",
    "INTERNAL":    "ReporterInternal",
}

INSIDE_SKIP_TYPES = {"ANALOG", "WET_BULB_TEMPERATURE", "DEW_POINT_TEMPERATURE"}

COLUMN_MAP = {
    ("Outside", "TEMPERATURE"):              "outside_temperature",
    ("Outside", "HUMIDITY"):                 "outside_humidity",
    ("Outside", "WET_BULB_TEMPERATURE"):     "outside_wet_bulb_temperature",
    ("Outside", "DEW_POINT_TEMPERATURE"):    "outside_dew_point_temperature",
    ("Outside", "WIND_AVERAGE_SPEED"):       "outside_wind_average_speed",
    ("Outside", "WIND_AVERAGE_MAX_SPEED"):   "outside_wind_average_max_speed",
    ("Outside", "WIND_DIRECTION"):           "outside_wind_direction",
    ("Outside", "RAIN"):                     "outside_rain",
    ("Inside",  "PAR"):                      "inside_par",
    ("Inside",  "TEMPERATURE"):              "inside_temperature",
    ("Inside",  "HUMIDITY"):                 "inside_humidity",
    ("ReporterInternal", "POWER_SUPPLY"):           "power_supply",
    ("ReporterInternal", "ATMOSPHERIC_PRESSURE"):   "atmospheric_pressure",
}

WIND_DIRECTIONS = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
]

# Insert column order. Matches the bulk-insert SQL below.
INSERT_COLUMNS = ["org_id", "reading_at"] + list(dict.fromkeys(COLUMN_MAP.values()))


# ---------------------------------------------------------------------------
# Crodeon HTTP
# ---------------------------------------------------------------------------

def _crodeon_get(path, attempts=5):
    """Authenticated GET against the Crodeon API with retry on transient
    network errors (chunked-read drops, 5xx, timeouts). The historical
    /measurements endpoint occasionally truncates large responses
    mid-flight; one retry usually clears it."""
    if not CRODEON_API_KEY:
        raise SystemExit("ERROR: CRODEON_API_KEY must be set in env")
    url = f"{CRODEON_BASE}{path}"
    delay = 2.0
    last_err = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(
                url,
                headers={"Accept": "application/json", "X-API-KEY": CRODEON_API_KEY},
            )
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            # Retry 5xx/429; surface 4xx immediately.
            if e.code not in (429, 500, 502, 503, 504):
                body = e.read().decode(errors="replace")[:500]
                raise SystemExit(f"Crodeon HTTP {e.code} on {path}: {body}")
            last_err = e
        except (http.client.IncompleteRead, urllib.error.URLError,
                ConnectionError, TimeoutError) as e:
            # Retry truncated reads, connection resets, timeouts.
            # ConnectionError covers ConnectionResetError + ConnectionAbortedError
            # which can be raised mid-read after urlopen returned.
            last_err = e
        if i == attempts - 1:
            break
        print(f"  Crodeon transient error on {path[:60]} -- retry in {delay:.0f}s ({i+1}/{attempts-1}): {type(last_err).__name__}: {str(last_err)[:80]}")
        time.sleep(delay)
        delay *= 2
    raise SystemExit(f"Crodeon failed after {attempts} attempts: {last_err}")


def fetch_sensor_index():
    """Return {(device_id, channel_index): (label, type, exponent)}.

    Looked up once per script invocation -- the channel layout is stable.
    """
    sensors = _crodeon_get(f"/reporters/{MASTER_ID}/sensors")
    index = {}
    for sensor in sensors.get("sensors", []):
        connector = sensor.get("crlink")
        label = CONNECTOR_LABELS.get(connector)
        if not label:
            continue
        device_id = sensor["device_id"]["id"]
        for channel in sensor.get("channels", []):
            data_type = channel.get("type")
            if label == "Inside" and data_type in INSIDE_SKIP_TYPES:
                continue
            if (label, data_type) not in COLUMN_MAP:
                continue
            exponent = (channel.get("display_unit") or {}).get("exponent") or 0
            index[(device_id, channel["index"])] = (label, data_type, exponent)
    return index


def fetch_measurements_in_range(start_iso, end_iso):
    """Iterate every measurement item between start_iso and end_iso (UTC ISO)."""
    page = 0
    while True:
        qs = urllib.parse.urlencode({
            "start_time": start_iso,
            "end_time":   end_iso,
            "page":       page,
            "page_size":  PAGE_SIZE,
        })
        data = _crodeon_get(f"/reporters/{MASTER_ID}/measurements?{qs}")
        items = data.get("items", []) or []
        for item in items:
            yield item
        total_pages = data.get("total_pages") or 1
        if page + 1 >= total_pages or not items:
            return
        page += 1


# ---------------------------------------------------------------------------
# Build readings from raw measurements
# ---------------------------------------------------------------------------

def convert(data_type, raw_value, exponent):
    """Apply the same unit conversions the legacy GAS code did."""
    value = raw_value / (10 ** exponent)
    if data_type in ("TEMPERATURE", "WET_BULB_TEMPERATURE", "DEW_POINT_TEMPERATURE"):
        return round((value / 100) * 9 / 5 + 32, 2)
    if data_type == "HUMIDITY":
        return round(value / 100, 2)
    if data_type in ("WIND_AVERAGE_SPEED", "WIND_AVERAGE_MAX_SPEED"):
        return round((value / 100) * 2.23694, 2)
    if data_type == "WIND_DIRECTION":
        try:
            return WIND_DIRECTIONS[int(value)]
        except (IndexError, ValueError):
            return None
    if data_type == "RAIN":
        return round((value / 1000) * 0.0393701, 4)
    if data_type == "PAR":
        return round(value / 100, 2)
    if data_type == "POWER_SUPPLY":
        return "On" if int(raw_value) == 1 else "Off"
    if data_type == "ATMOSPHERIC_PRESSURE":
        return round(value / 100, 2)
    return value


def build_readings(measurements, sensor_index):
    """Group raw measurements by timestamp and turn each timestamp into a
    edi_crodeon_weather row tuple in INSERT_COLUMNS order."""
    by_ts = defaultdict(dict)
    for m in measurements:
        device_id = m["device_id"]["id"]
        channel = m["channel_index"]
        meta = sensor_index.get((device_id, channel))
        if not meta:
            continue
        label, data_type, exponent = meta
        column = COLUMN_MAP.get((label, data_type))
        if not column:
            continue
        ts = m.get("timestamp")
        if not ts:
            continue
        by_ts[ts][column] = convert(data_type, m["value"], exponent)

    rows = []
    for ts, columns in sorted(by_ts.items()):
        if not columns:
            continue
        # Convert UTC ISO to HST naive datetime (matches reading_at TIMESTAMP type).
        reading_at_utc = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        reading_at_hst = reading_at_utc.astimezone(HST).replace(tzinfo=None)
        row = [ORG_ID, reading_at_hst]
        for col in INSERT_COLUMNS[2:]:
            row.append(columns.get(col))
        rows.append(tuple(row))
    return rows


# ---------------------------------------------------------------------------
# DB write
# ---------------------------------------------------------------------------

def bulk_upsert(rows):
    if not rows:
        return 0
    col_list = ", ".join(INSERT_COLUMNS)
    sql = (
        f"INSERT INTO edi_crodeon_weather ({col_list}) VALUES %s "
        "ON CONFLICT (org_id, reading_at) DO NOTHING"
    )
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            execute_values(cur, sql, rows, page_size=1000)
            inserted = cur.rowcount
        conn.commit()
    return inserted


# ---------------------------------------------------------------------------
# Sync orchestration
# ---------------------------------------------------------------------------

def sync_range(start_dt, end_dt):
    """Pull, convert, and upsert measurements between start_dt and end_dt
    (UTC datetimes). Walks the range in daily chunks for backfill use."""
    sensor_index = fetch_sensor_index()
    if not sensor_index:
        print("  No mapped channels -- nothing to do.")
        return 0, 0

    total_readings = 0
    total_inserted = 0

    chunk_start = start_dt
    while chunk_start < end_dt:
        chunk_end = min(chunk_start + BACKFILL_CHUNK, end_dt)
        s_iso = chunk_start.isoformat().replace("+00:00", "Z")
        e_iso = chunk_end.isoformat().replace("+00:00", "Z")

        measurements = list(fetch_measurements_in_range(s_iso, e_iso))
        rows = build_readings(measurements, sensor_index)
        inserted = bulk_upsert(rows)

        total_readings += len(rows)
        total_inserted += inserted
        if rows:
            print(
                f"  {chunk_start.date()} -> {chunk_end.date()}: "
                f"{len(measurements)} items -> {len(rows)} readings -> {inserted} inserted"
            )

        chunk_start = chunk_end

    return total_readings, total_inserted


def parse_iso(s):
    if not s:
        return None
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--since",
        default=os.environ.get("CRODEON_BACKFILL_SINCE"),
        help="UTC ISO start time (default: now-12min for live mode)",
    )
    parser.add_argument(
        "--until",
        default=os.environ.get("CRODEON_BACKFILL_UNTIL"),
        help="UTC ISO end time (default: now)",
    )
    args = parser.parse_args()

    end_dt = parse_iso(args.until) or datetime.now(timezone.utc)
    start_dt = parse_iso(args.since) or end_dt - LIVE_LOOKBACK

    mode = "backfill" if args.since else "live"
    print(f"Crodeon weather sync ({mode})")
    print(f"  range: {start_dt.isoformat()}  ->  {end_dt.isoformat()}")

    readings, inserted = sync_range(start_dt, end_dt)
    print(f"  {readings} readings processed; {inserted} new rows inserted.")


if __name__ == "__main__":
    main()
