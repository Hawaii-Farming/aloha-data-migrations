-- grow_cuke_harvest_v: convenience view for dashboards that need display-
-- friendly greenhouse names (GH1, Kona, HK, etc.) and the variety letter
-- (K/J/E) without re-joining seed batch + invnt_item on every query.

CREATE OR REPLACE VIEW grow_cuke_harvest_v AS
SELECT
    h.id,
    h.harvest_date,
    h.site_id,
    CASE h.site_id
        WHEN '01' THEN 'GH1'
        WHEN '02' THEN 'GH2'
        WHEN '03' THEN 'GH3'
        WHEN '04' THEN 'GH4'
        WHEN '05' THEN 'GH5'
        WHEN '06' THEN 'GH6'
        WHEN '07' THEN 'GH7'
        WHEN '08' THEN 'GH8'
        WHEN 'ko' THEN 'Kona'
        WHEN 'hk' THEN 'HK'
        WHEN 'hi' THEN 'Hilo'
        WHEN 'wa' THEN 'Waimea'
        ELSE UPPER(h.site_id)
    END AS greenhouse,
    UPPER(COALESCE(i.grow_variety_id, '')) AS variety,
    h.grow_grade_id AS grade,
    h.net_weight AS greenhouse_net_weight,
    h.gross_weight,
    h.number_of_containers,
    h.weight_uom,
    h.grow_cuke_seed_batch_id,
    h.org_id,
    h.farm_id
FROM grow_harvest_weight h
LEFT JOIN grow_cuke_seed_batch b ON b.id = h.grow_cuke_seed_batch_id
LEFT JOIN invnt_item i ON i.id = b.invnt_item_id
WHERE h.farm_id = 'cuke' AND h.is_deleted = false;

COMMENT ON VIEW grow_cuke_harvest_v IS 'Cuke harvest weigh-ins with display-friendly greenhouse names (GH1/Kona/HK/etc.) and variety letter (K/J/E) for dashboards. Joins grow_harvest_weight to grow_cuke_seed_batch and invnt_item';
