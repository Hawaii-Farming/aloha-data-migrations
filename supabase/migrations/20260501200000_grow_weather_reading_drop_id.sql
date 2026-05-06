-- grow_weather_reading: drop redundant id column, promote (org_id, reading_at) to PK
-- ===================================================================================
-- The surrogate UUID `id` is redundant -- (org_id, reading_at) already
-- uniquely identifies a reading (after the prior dedupe + UNIQUE
-- constraint). Drop the surrogate and promote the natural key to the
-- primary key.
--
-- The DLI view selects w.* and would inherit `id`; drop and recreate
-- around the column change.

DROP VIEW IF EXISTS public.grow_weather_reading_dli;

ALTER TABLE grow_weather_reading
    DROP CONSTRAINT IF EXISTS grow_weather_reading_pkey;

ALTER TABLE grow_weather_reading
    DROP CONSTRAINT IF EXISTS grow_weather_reading_org_reading_at_key;

ALTER TABLE grow_weather_reading
    DROP COLUMN IF EXISTS id;

ALTER TABLE grow_weather_reading
    ADD CONSTRAINT grow_weather_reading_pkey
    PRIMARY KEY (org_id, reading_at);

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
