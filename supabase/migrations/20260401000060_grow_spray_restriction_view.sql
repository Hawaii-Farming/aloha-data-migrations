CREATE OR REPLACE VIEW grow_spray_restriction AS
WITH spray_events AS (
    -- Get each spray event with its max REI and PHI from compliance records
    SELECT
        tt.id AS ops_task_tracker_id,
        tt.org_id,
        tt.farm_id,
        tt.site_id,
        tt.stop_time AS spray_stop,
        MAX(c.rei_hours) AS max_rei_hours,
        MAX(c.phi_days) AS max_phi_days
    FROM ops_task_tracker tt
    JOIN grow_spray_input si ON si.ops_task_tracker_id = tt.id AND si.is_deleted = false
    JOIN grow_spray_compliance c ON c.id = si.grow_spray_compliance_id
    WHERE tt.is_deleted = false
      AND tt.is_completed = true
      AND tt.stop_time IS NOT NULL
    GROUP BY tt.id, tt.org_id, tt.farm_id, tt.site_id, tt.stop_time
),
rei_restrictions AS (
    -- Generate one row per calendar day for REI (No Entry) restriction
    SELECT
        se.ops_task_tracker_id,
        se.org_id,
        se.farm_id,
        se.site_id,
        'NE' AS restriction_type,
        d::DATE AS restriction_date,
        GREATEST(se.spray_stop, d::TIMESTAMPTZ) AS start_time,
        LEAST(
            se.spray_stop + (se.max_rei_hours * INTERVAL '1 hour'),
            (d + INTERVAL '1 day')::TIMESTAMPTZ
        ) AS end_time,
        se.spray_stop,
        se.spray_stop + (se.max_rei_hours * INTERVAL '1 hour') AS rei_stop,
        se.max_rei_hours
    FROM spray_events se
    CROSS JOIN LATERAL generate_series(
        se.spray_stop::DATE,
        (se.spray_stop + (se.max_rei_hours * INTERVAL '1 hour'))::DATE,
        INTERVAL '1 day'
    ) AS d
    WHERE se.max_rei_hours > 0
),
phi_restrictions AS (
    -- Generate one row per calendar day for PHI (No Harvest) restriction
    SELECT
        se.ops_task_tracker_id,
        se.org_id,
        se.farm_id,
        se.site_id,
        'NH' AS restriction_type,
        d::DATE AS restriction_date,
        GREATEST(se.spray_stop, d::TIMESTAMPTZ) AS start_time,
        LEAST(
            se.spray_stop + (se.max_phi_days * INTERVAL '1 day'),
            (d + INTERVAL '1 day')::TIMESTAMPTZ
        ) AS end_time,
        se.spray_stop,
        se.spray_stop + (se.max_phi_days * INTERVAL '1 day') AS phi_stop,
        se.max_phi_days
    FROM spray_events se
    CROSS JOIN LATERAL generate_series(
        se.spray_stop::DATE,
        (se.spray_stop + (se.max_phi_days * INTERVAL '1 day'))::DATE,
        INTERVAL '1 day'
    ) AS d
    WHERE se.max_phi_days > 0
)
SELECT
    ops_task_tracker_id,
    org_id,
    farm_id,
    site_id,
    restriction_type,
    restriction_date,
    start_time,
    end_time,
    spray_stop,
    rei_stop AS restriction_stop,
    max_rei_hours AS restriction_value
FROM rei_restrictions

UNION ALL

SELECT
    ops_task_tracker_id,
    org_id,
    farm_id,
    site_id,
    restriction_type,
    restriction_date,
    start_time,
    end_time,
    spray_stop,
    phi_stop AS restriction_stop,
    max_phi_days AS restriction_value
FROM phi_restrictions;

COMMENT ON VIEW grow_spray_restriction IS 'Derived daily restriction calendar per site after each spray event. NE (No Entry) rows span from spray stop to REI expiry. NH (No Harvest) rows span from spray stop to PHI expiry. One row per calendar day per restriction type per spray event.';
