-- Diagnostic-only: count what's in the new pack_* tables after restructure.
-- Idempotent no-op. Helps verify whether backfilled rows actually landed and
-- whether there is any historical data for lettuce / cuke to display.

DO $$
DECLARE
    v_session_total       INT;
    v_session_lettuce     INT;
    v_session_cuke        INT;
    v_session_started     INT;
    v_session_stopped     INT;
    v_session_backfilled  INT;
    v_cases_total         INT;
    v_cases_lettuce       INT;
    v_cases_cuke          INT;
    v_labor_hour_total    INT;
    v_labor_hour_lettuce  INT;
    v_fails_total         INT;
    v_leftover_total      INT;
    v_distinct_pack_dates INT;
    v_min_pack_date       DATE;
    v_max_pack_date       DATE;
    rec                   RECORD;
BEGIN
    SELECT COUNT(*) INTO v_session_total       FROM pack_session;
    SELECT COUNT(*) INTO v_session_lettuce     FROM pack_session WHERE farm_id LIKE '%lettuce%' OR farm_id NOT LIKE '%cuke%';
    SELECT COUNT(*) INTO v_session_cuke        FROM pack_session WHERE farm_id LIKE '%cuke%';
    SELECT COUNT(*) INTO v_session_started     FROM pack_session WHERE started_at IS NOT NULL;
    SELECT COUNT(*) INTO v_session_stopped     FROM pack_session WHERE stopped_at IS NOT NULL;
    SELECT COUNT(*) INTO v_session_backfilled  FROM pack_session WHERE started_at IS NULL AND stopped_at IS NULL;

    SELECT COUNT(DISTINCT pack_date), MIN(pack_date), MAX(pack_date)
      INTO v_distinct_pack_dates, v_min_pack_date, v_max_pack_date
      FROM pack_session;

    SELECT COUNT(*) INTO v_cases_total          FROM pack_session_cases;
    SELECT COUNT(*) INTO v_cases_lettuce        FROM pack_session_cases WHERE farm_id NOT LIKE '%cuke%';
    SELECT COUNT(*) INTO v_cases_cuke           FROM pack_session_cases WHERE farm_id LIKE '%cuke%';

    SELECT COUNT(*) INTO v_labor_hour_total     FROM pack_session_labor_hour;
    SELECT COUNT(*) INTO v_labor_hour_lettuce   FROM pack_session_labor_hour WHERE farm_id NOT LIKE '%cuke%';

    SELECT COUNT(*) INTO v_fails_total          FROM pack_session_fails;
    SELECT COUNT(*) INTO v_leftover_total       FROM pack_session_leftover;

    RAISE NOTICE '== pack_session ==';
    RAISE NOTICE 'total=%, lettuce_like=%, cuke_like=%, started=%, stopped=%, backfilled(both null)=%',
        v_session_total, v_session_lettuce, v_session_cuke, v_session_started, v_session_stopped, v_session_backfilled;
    RAISE NOTICE 'distinct_pack_dates=%, min=%, max=%',
        v_distinct_pack_dates, v_min_pack_date, v_max_pack_date;

    RAISE NOTICE '== pack_session_cases ==';
    RAISE NOTICE 'total=%, lettuce_like=%, cuke_like=%', v_cases_total, v_cases_lettuce, v_cases_cuke;

    RAISE NOTICE '== pack_session_labor_hour ==';
    RAISE NOTICE 'total=%, lettuce_like=%', v_labor_hour_total, v_labor_hour_lettuce;

    RAISE NOTICE '== pack_session_fails ==';
    RAISE NOTICE 'total=%', v_fails_total;

    RAISE NOTICE '== pack_session_leftover ==';
    RAISE NOTICE 'total=%', v_leftover_total;

    -- Distinct farm_ids actually in pack_session
    RAISE NOTICE '== distinct farm_ids in pack_session ==';
    FOR rec IN
        SELECT farm_id, COUNT(*) AS n, MIN(pack_date) AS first_date, MAX(pack_date) AS last_date
          FROM pack_session
         GROUP BY farm_id
         ORDER BY n DESC
    LOOP
        RAISE NOTICE 'farm_id=%, rows=%, first=%, last=%', rec.farm_id, rec.n, rec.first_date, rec.last_date;
    END LOOP;

    -- A sample of the most recent 5 pack_session rows
    RAISE NOTICE '== sample: most-recent 5 pack_session rows ==';
    FOR rec IN
        SELECT pack_date, farm_id, sales_product_id, harvest_date, pack_lot,
               started_at IS NOT NULL AS started, stopped_at IS NOT NULL AS stopped
          FROM pack_session
         ORDER BY pack_date DESC, created_at DESC
         LIMIT 5
    LOOP
        RAISE NOTICE 'pack_date=%, farm=%, product=%, harvest=%, lot=%, started=%, stopped=%',
            rec.pack_date, rec.farm_id, rec.sales_product_id, rec.harvest_date, rec.pack_lot, rec.started, rec.stopped;
    END LOOP;
END $$;
