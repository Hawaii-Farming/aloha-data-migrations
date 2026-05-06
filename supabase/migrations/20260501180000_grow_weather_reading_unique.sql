-- grow_weather_reading: drop farm_id, dedupe, add UNIQUE (org_id, reading_at)
-- ============================================================================
-- The new Crodeon-direct weather sync runs every 10 minutes against a single
-- station. There's no farm-level fan-out -- the station lives in the lettuce
-- greenhouse but readings represent the whole site, so farm_id is just noise.
--
-- Two changes:
--   1. Drop the farm_id column (and its composite FK to org_farm).
--   2. Add a UNIQUE constraint on (org_id, reading_at) so the every-10-min
--      sync can upsert via ON CONFLICT.
--
-- Existing rows: 73,441 with 49 dup keys on (org_id, farm_id, reading_at).
-- After dropping farm_id the dup count is the same (49); we keep the lowest
-- id row in each dup group.

-- Step 1: drop the dependent DLI view, drop farm_id + its FK, then recreate
-- the DLI view without the farm_id partition.
DROP VIEW IF EXISTS public.grow_weather_reading_dli;

ALTER TABLE grow_weather_reading
    DROP CONSTRAINT IF EXISTS grow_weather_reading_farm_fkey;

ALTER TABLE grow_weather_reading
    DROP COLUMN IF EXISTS farm_id;

-- Step 2: dedupe (keep one row per (org_id, reading_at)). Postgres MIN()
-- doesn't take a UUID directly, so use a window function on id::text.
DELETE FROM grow_weather_reading
WHERE id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY org_id, reading_at
                   ORDER BY id::text
               ) AS rn
        FROM grow_weather_reading
    ) t
    WHERE rn > 1
);

-- Step 3: add the UNIQUE constraint the new sync needs.
ALTER TABLE grow_weather_reading
    ADD CONSTRAINT grow_weather_reading_org_reading_at_key
    UNIQUE (org_id, reading_at);

COMMENT ON CONSTRAINT grow_weather_reading_org_reading_at_key
  ON grow_weather_reading IS
  'One reading per org per timestamp. Required for the every-10-min Crodeon sync to upsert via ON CONFLICT.';

-- Step 4: recreate the DLI view without farm_id. Same DLI math, but the
-- LEAD window now partitions by org_id only (the station is org-level).
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
