-- edi_crodeon_weather
-- ===================
-- Per-minute weather-station readings pulled from the Crodeon API.
-- One row per (org_id, reading_at). Lives under the `edi_` module
-- prefix alongside edi_qb_invoice / edi_qb_expense -- this is data
-- exchange with an external system.
--
-- Source: Crodeon /reporters/{master_id}/measurements, polled every
-- 10 minutes by .github/workflows/weather-sync.yml which runs
-- gsheets/migrations/_crodeon_weather_sync.py. The script pulls a
-- 12-minute window each fire and ON CONFLICT-skips anything already
-- inserted, so cron jitter / restarts are safe.
--
-- Schema choices, in plain English:
--   * Natural PK on (org_id, reading_at) -- the device timestamp is
--     unique per org, no surrogate id needed.
--   * No created_at / created_by / updated_at / updated_by /
--     is_deleted. We aren't the source of truth, rows come from
--     Crodeon and are never user-edited; reading_at IS the provenance.
--   * reading_at is plain TIMESTAMP in HST wall clock. Hawaii is fixed
--     UTC-10 year round, so dropping the TZ removes a constant
--     conversion step from every report query.

CREATE TABLE IF NOT EXISTS edi_crodeon_weather (
    org_id       TEXT NOT NULL REFERENCES org(id),
    reading_at   TIMESTAMP NOT NULL,

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

    PRIMARY KEY (org_id, reading_at)
);

COMMENT ON TABLE edi_crodeon_weather IS 'Per-minute Crodeon weather-station readings. Outside (ambient) + inside (greenhouse) + atmospheric channels. Pulled every 10 minutes from Crodeon''s API by the weather-sync workflow. (org_id, reading_at) is the natural PK; reading_at is HST wall-clock TIMESTAMP.';

COMMENT ON COLUMN edi_crodeon_weather.reading_at                   IS 'Timestamp the station took the reading, in HST wall clock (Hawaii is fixed UTC-10 year round). No timezone math needed in reports.';
COMMENT ON COLUMN edi_crodeon_weather.outside_temperature          IS 'Ambient temperature, degrees Fahrenheit.';
COMMENT ON COLUMN edi_crodeon_weather.outside_humidity             IS 'Ambient relative humidity, percent.';
COMMENT ON COLUMN edi_crodeon_weather.outside_wet_bulb_temperature IS 'Wet-bulb temperature, degrees Fahrenheit.';
COMMENT ON COLUMN edi_crodeon_weather.outside_dew_point_temperature IS 'Dew-point temperature, degrees Fahrenheit.';
COMMENT ON COLUMN edi_crodeon_weather.outside_wind_average_speed   IS 'Average wind speed for the sample interval, mph.';
COMMENT ON COLUMN edi_crodeon_weather.outside_wind_average_max_speed IS 'Peak gust within the sample interval, mph.';
COMMENT ON COLUMN edi_crodeon_weather.outside_wind_direction       IS 'Compass direction string (N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW).';
COMMENT ON COLUMN edi_crodeon_weather.outside_rain                 IS 'Rainfall accumulation for the sample interval, inches.';
COMMENT ON COLUMN edi_crodeon_weather.inside_par                   IS 'Photosynthetically Active Radiation inside the greenhouse, micromol/m^2/s.';
COMMENT ON COLUMN edi_crodeon_weather.inside_temperature           IS 'Greenhouse interior temperature, degrees Fahrenheit.';
COMMENT ON COLUMN edi_crodeon_weather.inside_humidity              IS 'Greenhouse interior relative humidity, percent.';
COMMENT ON COLUMN edi_crodeon_weather.power_supply                 IS 'Station mains/battery state -- "On" when grid power is up.';
COMMENT ON COLUMN edi_crodeon_weather.atmospheric_pressure         IS 'Station-level atmospheric pressure, millibar.';

CREATE INDEX idx_edi_crodeon_weather_org_at ON edi_crodeon_weather (org_id, reading_at DESC);
CREATE INDEX idx_edi_crodeon_weather_at     ON edi_crodeon_weather (reading_at DESC);

-- RLS lives in 20260401000200_sys_rls_policies.sql (project convention).
