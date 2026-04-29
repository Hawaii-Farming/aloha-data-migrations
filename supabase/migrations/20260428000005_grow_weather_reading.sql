-- grow_weather_reading
-- ====================
-- High-frequency weather-station readings — one row per timestamp,
-- ~10-minute cadence, 16 sensor channels (outside + inside greenhouse +
-- atmospheric). The DLI column from the source sheet is intentionally
-- excluded; it's derived on the fly from PAR readings.
--
-- Source: weather spreadsheet `weather` tab, synced nightly via
-- gsheets/migrations/20260401000037_grow_weather.py.
-- The sheet is treated as the single source of truth: nightly job
-- truncates org-scoped rows and reinserts.
--
-- Wide format because every row has the same set of sensors. If sensors
-- get added or removed, this table needs ALTER TABLE — but that's once
-- per hardware change, not once per reading.

CREATE TABLE IF NOT EXISTS grow_weather_reading (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id       TEXT NOT NULL REFERENCES org(id),
    farm_id      TEXT REFERENCES org_farm(id),
    reading_at   TIMESTAMPTZ NOT NULL,

    -- Outside (ambient) sensors
    outside_temperature             NUMERIC,
    outside_humidity                NUMERIC,
    outside_wet_bulb_temperature    NUMERIC,
    outside_dew_point_temperature   NUMERIC,
    outside_wind_average_speed      NUMERIC,
    outside_wind_average_max_speed  NUMERIC,
    outside_wind_direction          TEXT,
    outside_rain                    NUMERIC,

    -- Inside (greenhouse) sensors
    inside_par                      NUMERIC,
    inside_temperature              NUMERIC,
    inside_humidity                 NUMERIC,

    -- Station status / atmosphere
    power_supply                    TEXT,
    atmospheric_pressure            NUMERIC,

    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by   TEXT,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   TEXT,
    is_deleted   BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE grow_weather_reading IS 'Greenhouse weather-station readings, one row per ~10-minute sample. Outside (ambient) + inside (greenhouse) + atmospheric channels. Loaded nightly from the station spreadsheet. DLI is excluded — derived on demand from inside_par + sample interval.';

COMMENT ON COLUMN grow_weather_reading.reading_at                   IS 'Timestamp the station took the reading. Sheet supplies date + time in local (HST) wall clock; stored as TIMESTAMPTZ.';
COMMENT ON COLUMN grow_weather_reading.outside_temperature          IS 'Ambient temperature in degrees Fahrenheit.';
COMMENT ON COLUMN grow_weather_reading.outside_humidity             IS 'Ambient relative humidity in percent.';
COMMENT ON COLUMN grow_weather_reading.outside_wet_bulb_temperature IS 'Wet-bulb temperature in degrees Fahrenheit.';
COMMENT ON COLUMN grow_weather_reading.outside_dew_point_temperature IS 'Dew-point temperature in degrees Fahrenheit.';
COMMENT ON COLUMN grow_weather_reading.outside_wind_average_speed   IS 'Average wind speed for the sample interval, mph.';
COMMENT ON COLUMN grow_weather_reading.outside_wind_average_max_speed IS 'Peak gust within the sample interval, mph.';
COMMENT ON COLUMN grow_weather_reading.outside_wind_direction       IS 'Compass direction string (e.g. N, NNE, NE, ESE).';
COMMENT ON COLUMN grow_weather_reading.outside_rain                 IS 'Rainfall accumulation for the sample interval, inches.';
COMMENT ON COLUMN grow_weather_reading.inside_par                   IS 'Photosynthetically Active Radiation inside the greenhouse, μmol/m²/s.';
COMMENT ON COLUMN grow_weather_reading.inside_temperature           IS 'Greenhouse interior temperature, degrees Fahrenheit.';
COMMENT ON COLUMN grow_weather_reading.inside_humidity              IS 'Greenhouse interior relative humidity, percent.';
COMMENT ON COLUMN grow_weather_reading.power_supply                 IS 'Station mains/battery state — typically "On" when grid power is up.';
COMMENT ON COLUMN grow_weather_reading.atmospheric_pressure         IS 'Station-level atmospheric pressure, millibar.';

CREATE INDEX idx_grow_weather_reading_org_at ON grow_weather_reading (org_id, reading_at DESC);
CREATE INDEX idx_grow_weather_reading_at     ON grow_weather_reading (reading_at DESC);

-- ============================================================
-- RLS — org-scoped read for authenticated users.
-- ============================================================

ALTER TABLE grow_weather_reading ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_weather_reading_read" ON grow_weather_reading
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON grow_weather_reading TO authenticated;
