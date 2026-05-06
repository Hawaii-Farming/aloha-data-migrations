-- grow_weather_reading: store reading_at as HST wall-clock TIMESTAMP
-- ===================================================================
-- Switch reading_at from TIMESTAMPTZ (instant + UTC display by default) to
-- plain TIMESTAMP carrying the HST wall-clock value. Reports and grids that
-- read this column now show "2026-05-06 15:35" without any timezone math.
--
-- Hawaii is fixed at UTC-10 year round (no DST) so the HST <-> UTC mapping
-- is unambiguous; we don't lose any disambiguation by dropping the TZ.
--
-- Existing rows are preserved by casting AT TIME ZONE 'Pacific/Honolulu' --
-- e.g. a row stored as 2026-05-06T01:35:00Z becomes 2026-05-05 15:35:00.
--
-- Audit columns (created_at, updated_at) remain TIMESTAMPTZ -- those are
-- system bookkeeping, not user-facing reports.

-- The DLI view depends on reading_at; drop and recreate around the type
-- change.
DROP VIEW IF EXISTS public.grow_weather_reading_dli;

ALTER TABLE grow_weather_reading
    ALTER COLUMN reading_at
    TYPE TIMESTAMP
    USING reading_at AT TIME ZONE 'Pacific/Honolulu';

COMMENT ON COLUMN grow_weather_reading.reading_at IS
  'Wall-clock HST timestamp at which the station emitted this reading. Stored as plain TIMESTAMP -- no timezone math needed in queries.';

-- Recreate the DLI view -- same math, just on the new column type.
CREATE OR REPLACE VIEW public.grow_weather_reading_dli
WITH (security_invoker = true) AS
SELECT
    w.*,
    COALESCE(
        w.inside_par
        * EXTRACT(EPOCH FROM (
            LEAD(w.reading_at) OVER (
                PARTITION BY w.org_id
                ORDER BY w.reading_at
            ) - w.reading_at
          ))
        / 1000000.0,
        0
    )::NUMERIC AS dli
FROM public.grow_weather_reading w
WHERE w.is_deleted = false;

GRANT SELECT ON public.grow_weather_reading_dli TO authenticated;

COMMENT ON VIEW public.grow_weather_reading_dli IS 'grow_weather_reading with a derived dli column: inside_par * seconds_to_next_reading / 1,000,000. Sum dli over a 24h window for daily DLI. The last row in each org_id partition has dli=0 (no next reading).';
