"""
Pull the latest Crodeon weather-station reading into grow_weather_reading.
==========================================================================

Direct port of the legacy `fetchNewWeatherData()` Apps Script that wrote
into the `weather` Google Sheet. Same Crodeon API endpoints, same unit
conversions, same connector -> column mapping. The Sheet middle-step is
gone -- this script writes straight into Postgres on a 10-minute cron.

Endpoints:
    GET /reporters/{master_id}/sensors            sensor metadata + per-channel display_unit.exponent
    GET /reporters/{master_id}/measurements/latest the most recent reading per channel

Connector layout (matches the legacy GAS code):
    CONNECTOR_1  -> Outside  (temperature / humidity / wind / rain / wet bulb / dew point)
    CONNECTOR_2  -> Inside   (PAR; ANALOG channel skipped)
    CONNECTOR_3  -> Inside   (temperature / humidity; wet bulb + dew point skipped)
    INTERNAL     -> ReporterInternal (power supply, atmospheric pressure)

Idempotent: ON CONFLICT (org_id, farm_id, reading_at) DO NOTHING. If
Crodeon hasn't issued a new reading since the last cron tick we skip
the insert silently.

Environment:
    SUPABASE_DB_URL    -- Postgres connection string
    CRODEON_API_KEY    -- key from Crodeon developer portal

Usage:
    python gsheets/migrations/_crodeon_weather_sync.py
"""
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

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

CONNECTOR_LABELS = {
    "CONNECTOR_1": "Outside",
    "CONNECTOR_2": "Inside",
    "CONNECTOR_3": "Inside",
    "INTERNAL":    "ReporterInternal",
}

# (label, dataType) tuples we don't want for the Inside sensors -- mirrors the
# GAS skip list. Keeps us from over-writing inside_temperature with the wrong
# CONNECTOR_2 ANALOG reading, etc.
INSIDE_SKIP_TYPES = {"ANALOG", "WET_BULB_TEMPERATURE", "DEW_POINT_TEMPERATURE"}

# Map of (label, dataType) -> grow_weather_reading column name.
# Anything not in this map is silently dropped (e.g. the ReporterInternal
# DEVICE_TEMPERATURE channel, if Crodeon ever adds new types).
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


def _crodeon_get(path):
    """Authenticated GET against the Crodeon API. Returns parsed JSON."""
    if not CRODEON_API_KEY:
        raise SystemExit("ERROR: CRODEON_API_KEY must be set in env")
    url = f"{CRODEON_BASE}{path}"
    req = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "X-API-KEY": CRODEON_API_KEY},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:500]
        raise SystemExit(f"Crodeon HTTP {e.code} on {path}: {body}")


def convert(data_type, raw_value, exponent):
    """Apply the same unit conversions the legacy GAS code did.

    Crodeon ships values as integers; the per-channel display_unit.exponent
    tells us how many decimals were shifted out. We undo that, then apply
    the type-specific conversion (C->F for temperatures, m/s->mph for
    wind, mm->inches for rain, code->compass for wind direction, etc.).
    """
    value = raw_value / (10 ** exponent)

    if data_type in ("TEMPERATURE", "WET_BULB_TEMPERATURE", "DEW_POINT_TEMPERATURE"):
        # Raw is in centi-degrees C; convert to Fahrenheit.
        return round((value / 100) * 9 / 5 + 32, 2)
    if data_type == "HUMIDITY":
        # Raw is humidity * 100; the existing column stores the percentage.
        return round(value / 100, 2)
    if data_type in ("WIND_AVERAGE_SPEED", "WIND_AVERAGE_MAX_SPEED"):
        # Raw is centi-meters/second; convert to mph.
        return round((value / 100) * 2.23694, 2)
    if data_type == "WIND_DIRECTION":
        # Raw is a 0-15 compass-octant code.
        try:
            return WIND_DIRECTIONS[int(value)]
        except (IndexError, ValueError):
            return None
    if data_type == "RAIN":
        # Raw is in micro-meters of rainfall; convert to inches.
        return round((value / 1000) * 0.0393701, 4)
    if data_type == "PAR":
        return round(value / 100, 2)
    if data_type == "POWER_SUPPLY":
        return "On" if int(raw_value) == 1 else "Off"
    if data_type == "ATMOSPHERIC_PRESSURE":
        return round(value / 100, 2)
    # Unknown type -- pass through the exponent-corrected value.
    return value


def collect_reading():
    """Pull sensors + latest measurements from Crodeon, return (reading_at, columns_dict).

    columns_dict keys are grow_weather_reading column names.
    Returns (None, None) if Crodeon hasn't issued any measurements yet.
    """
    sensors = _crodeon_get(f"/reporters/{MASTER_ID}/sensors")
    measurements = _crodeon_get(f"/reporters/{MASTER_ID}/measurements/latest")

    # sensors.sensors -> [{crlink, device_id.id, channels: [{index, type, display_unit.exponent}, ...]}]
    sensors_by_connector = {s["crlink"]: s for s in sensors.get("sensors", [])}

    # measurements.items -> [{device_id.id, channel_index, value, timestamp}, ...]
    measurements_by_device_chan = {
        (m["device_id"]["id"], m["channel_index"]): m
        for m in measurements.get("items", [])
    }

    columns = {}
    reading_at = None

    for connector, label in CONNECTOR_LABELS.items():
        sensor = sensors_by_connector.get(connector)
        if not sensor:
            continue
        device_id = sensor["device_id"]["id"]
        for channel in sensor.get("channels", []):
            data_type = channel["type"]
            if label == "Inside" and data_type in INSIDE_SKIP_TYPES:
                continue
            col = COLUMN_MAP.get((label, data_type))
            if not col:
                # Unmapped -- ignore (matches GAS behaviour for unrecognised types).
                continue
            measurement = measurements_by_device_chan.get((device_id, channel["index"]))
            if not measurement:
                continue
            exponent = (channel.get("display_unit") or {}).get("exponent") or 0
            columns[col] = convert(data_type, measurement["value"], exponent)
            if reading_at is None:
                reading_at = measurement.get("timestamp")

    return reading_at, columns


def upsert_reading(reading_at_iso, columns):
    """Insert one weather reading. ON CONFLICT do nothing -- if the same
    timestamp already exists we silently skip (Crodeon hasn't moved on)."""
    # Crodeon timestamps are ISO-8601 UTC ("...Z"). reading_at is a plain
    # TIMESTAMP holding HST wall-clock, so convert UTC -> HST and drop the
    # tzinfo before inserting.
    reading_at_utc = datetime.fromisoformat(reading_at_iso.replace("Z", "+00:00"))
    reading_at = reading_at_utc.astimezone(HST).replace(tzinfo=None)

    cols = ["org_id", "reading_at"] + list(columns.keys())
    vals = [ORG_ID, reading_at] + list(columns.values())
    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)

    sql = (
        f"INSERT INTO grow_weather_reading ({col_list}) VALUES ({placeholders}) "
        "ON CONFLICT (org_id, reading_at) DO NOTHING"
    )

    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, vals)
            inserted = cur.rowcount
        conn.commit()
    return inserted


def main():
    print("Crodeon weather sync")
    reading_at, columns = collect_reading()
    if not reading_at:
        print("  No reading available from Crodeon -- skipping.")
        return
    if not columns:
        print(f"  Reading at {reading_at} had no recognised channels -- skipping.")
        return

    inserted = upsert_reading(reading_at, columns)
    if inserted:
        sample = ", ".join(f"{k}={v}" for k, v in list(columns.items())[:4])
        print(f"  Inserted reading at {reading_at}: {sample}, ... ({len(columns)} cols total)")
    else:
        print(f"  Reading at {reading_at} already in DB -- no-op.")


if __name__ == "__main__":
    main()
