-- Rename grow_weather_reading -> edi_crodeon_weather; drop audit columns
-- =======================================================================
-- The weather feed is part of the EDI integration surface (data exchange
-- with an external system: Crodeon's API). Same naming pattern as
-- edi_qb_invoice / edi_qb_expense -- module prefix `edi_`, vendor name
-- `crodeon`, then the data type.
--
-- Audit columns (created_at / created_by / updated_at / updated_by /
-- is_deleted) are dropped: we aren't the source of truth, rows are
-- (re)inserted from Crodeon every minute, and provenance is captured by
-- reading_at + the never-modified row itself. Keeps the schema tight.
--
-- The DLI view (was grow_weather_reading_dli) gets renamed and recreated
-- because (a) it selects w.* and would still have the dropped audit
-- columns in its column list, and (b) we want it under the same
-- edi_crodeon_ prefix.

-- 1. Drop the dependent view.
DROP VIEW IF EXISTS public.grow_weather_reading_dli;

-- 2. Drop audit columns.
ALTER TABLE public.grow_weather_reading
    DROP COLUMN IF EXISTS created_at,
    DROP COLUMN IF EXISTS created_by,
    DROP COLUMN IF EXISTS updated_at,
    DROP COLUMN IF EXISTS updated_by,
    DROP COLUMN IF EXISTS is_deleted;

-- 3. Rename the table. Postgres carries the PK constraint
-- (now `grow_weather_reading_pkey`) along with it; rename it for tidiness.
ALTER TABLE public.grow_weather_reading
    RENAME TO edi_crodeon_weather;

ALTER TABLE public.edi_crodeon_weather
    RENAME CONSTRAINT grow_weather_reading_pkey TO edi_crodeon_weather_pkey;

-- 4. Rename the RLS policy + GRANT. Policies move with the table; only
-- the policy NAME needs to be updated for tidiness.
ALTER POLICY "grow_weather_reading_read"
    ON public.edi_crodeon_weather
    RENAME TO "edi_crodeon_weather_read";

-- 5. Recreate the DLI view as edi_crodeon_weather_dli, no is_deleted
-- filter (column gone), no farm_id partition (column gone).
CREATE OR REPLACE VIEW public.edi_crodeon_weather_dli
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
FROM public.edi_crodeon_weather w;

GRANT SELECT ON public.edi_crodeon_weather_dli TO authenticated;

COMMENT ON TABLE public.edi_crodeon_weather IS
  'Per-minute weather readings pulled from the Crodeon greenhouse station via /reporters/{master_id}/measurements. (org_id, reading_at) is the natural PK; reading_at is HST wall-clock. No audit columns -- we aren''t the source of truth, rows come from the every-10-min sync and are never user-edited.';

COMMENT ON VIEW public.edi_crodeon_weather_dli IS
  'edi_crodeon_weather with a derived dli column: inside_par * seconds_to_next_reading / 1,000,000. Sum dli over a 24h window for daily DLI. The last row in each org_id partition has dli=0 (no next reading).';
