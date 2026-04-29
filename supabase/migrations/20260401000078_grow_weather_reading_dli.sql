-- grow_weather_reading_dli
-- ========================
-- Wraps grow_weather_reading with a derived `dli` column. Mirrors the
-- legacy spreadsheet ARRAYFORMULA:
--   IFERROR((IF(B3:B="",,24*3600*(B3:B-B2:B))*K2:K)/1000000, 0)
--
-- For each row N: DLI is the photon dose accumulated over the interval
-- starting at this reading and ending at the next reading, assuming
-- inside_par stayed constant during the interval (left-Riemann sum):
--
--   dli = inside_par(N) × seconds_to_next_reading / 1,000,000
--
-- Units: inside_par is μmol/m²/s, multiply by interval seconds to get
-- μmol/m², divide by 1,000,000 to get mol/m² (DLI's unit). Sum dli
-- across a 24h window per (org_id, farm_id) to get a daily DLI.
--
-- The last row in each (org_id, farm_id) partition has no "next reading"
-- so its dli is 0 — same fallback the sheet's IFERROR uses.

CREATE OR REPLACE VIEW public.grow_weather_reading_dli
WITH (security_invoker = true) AS
SELECT
    w.*,
    COALESCE(
        w.inside_par
        * EXTRACT(EPOCH FROM (
            LEAD(w.reading_at) OVER (
                PARTITION BY w.org_id, w.farm_id
                ORDER BY w.reading_at
            ) - w.reading_at
          ))
        / 1000000.0,
        0
    )::NUMERIC AS dli
FROM public.grow_weather_reading w
WHERE w.is_deleted = false;

GRANT SELECT ON public.grow_weather_reading_dli TO authenticated;

COMMENT ON VIEW public.grow_weather_reading_dli IS 'grow_weather_reading with a derived dli column: inside_par × seconds_to_next_reading / 1,000,000. Sum dli over a 24h window for daily DLI. The last row in each (org_id, farm_id) partition has dli=0 (no next reading).';
