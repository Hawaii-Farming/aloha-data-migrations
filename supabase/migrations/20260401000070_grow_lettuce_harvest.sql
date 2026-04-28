-- grow_lettuce_harvest: convenience view for dashboards that need pond
-- harvest aggregates — boards, pounds per board, total pounds — without
-- re-joining grow_harvest_weight to grow_lettuce_seed_batch + invnt_item
-- on every query. One row per harvest weigh-in.

CREATE OR REPLACE VIEW grow_lettuce_harvest
WITH (security_invoker = true) AS
SELECT
    h.id,
    h.harvest_date,
    UPPER(h.site_id) AS pond,
    COALESCE(i.id, '') AS seed_name,
    h.number_of_containers AS boards_per_pond,
    CASE WHEN h.number_of_containers > 0
         THEN h.net_weight / h.number_of_containers
         ELSE 0
    END AS pounds_per_board,
    h.net_weight AS greenhouse_net_weight,
    h.gross_weight,
    h.grow_lettuce_seed_batch_id,
    h.org_id,
    h.farm_id
FROM grow_harvest_weight h
LEFT JOIN grow_lettuce_seed_batch b ON b.id = h.grow_lettuce_seed_batch_id
LEFT JOIN invnt_item i ON i.id = b.invnt_item_id
WHERE h.farm_id = 'Lettuce' AND h.is_deleted = false;

COMMENT ON VIEW grow_lettuce_harvest IS 'Lettuce harvest weigh-ins with pond name uppercased (P1/P2/..) and seed cultivar name joined from invnt_item. boards_per_pond = number_of_containers, pounds_per_board = net_weight / number_of_containers.';
