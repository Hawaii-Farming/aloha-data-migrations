CREATE OR REPLACE VIEW invnt_item_summary
WITH (security_invoker = true) AS
WITH latest_onhand AS (
    SELECT DISTINCT ON (invnt_item_id)
        invnt_item_id,
        onhand_quantity,
        onhand_uom,
        burn_per_onhand,
        onhand_date
    FROM invnt_onhand
    WHERE is_deleted = false
    ORDER BY invnt_item_id, onhand_date DESC, created_at DESC
),
open_orders AS (
    SELECT
        po.invnt_item_id,
        COALESCE(SUM(po.order_quantity * po.burn_per_order), 0) AS ordered_quantity_in_burn,
        COALESCE(SUM(r.received_quantity_in_burn), 0) AS received_quantity_in_burn
    FROM invnt_po po
    LEFT JOIN (
        SELECT
            invnt_po_id,
            SUM(received_quantity * burn_per_received) AS received_quantity_in_burn
        FROM invnt_po_received
        WHERE is_deleted = false
        GROUP BY invnt_po_id
    ) r ON r.invnt_po_id = po.id
    WHERE po.is_deleted = false
      AND po.invnt_item_id IS NOT NULL
      AND po.status IN ('approved', 'ordered', 'partial')
    GROUP BY po.invnt_item_id
)
SELECT
    -- Item identification
    i.org_id,
    i.farm_id,
    i.id AS invnt_item_id,
    i.invnt_category_id,
    i.invnt_subcategory_id,
    i.invnt_vendor_id,

    -- Item UOMs & conversions
    i.burn_uom,
    i.onhand_uom,
    i.order_uom,
    i.burn_per_onhand,
    i.burn_per_order,

    -- Forecasting settings
    i.is_frequently_used,
    i.burn_per_week,
    i.cushion_weeks,

    -- Reorder settings
    i.is_auto_reorder,
    i.reorder_point_in_burn,
    i.reorder_quantity_in_burn,

    -- Current on-hand (from latest invnt_onhand record)
    COALESCE(lo.onhand_quantity, 0) AS onhand_quantity,
    COALESCE(lo.onhand_quantity * lo.burn_per_onhand, 0) AS onhand_quantity_in_burn,
    lo.onhand_date,
    CURRENT_DATE - lo.onhand_date AS days_since_onhand,

    -- Open orders (from invnt_po + invnt_po_received)
    COALESCE(oo.ordered_quantity_in_burn, 0) AS ordered_quantity_in_burn,
    COALESCE(oo.received_quantity_in_burn, 0) AS received_quantity_in_burn,
    COALESCE(oo.ordered_quantity_in_burn, 0) - COALESCE(oo.received_quantity_in_burn, 0) AS remaining_quantity_in_burn,

    -- Computed forecasts
    CASE
        WHEN COALESCE(i.burn_per_week, 0) > 0
        THEN COALESCE(lo.onhand_quantity * lo.burn_per_onhand, 0) / i.burn_per_week
        ELSE NULL
    END AS weeks_on_hand,

    CASE
        WHEN COALESCE(i.burn_per_week, 0) > 0 AND lo.onhand_date IS NOT NULL
        THEN lo.onhand_date + (
            COALESCE(lo.onhand_quantity * lo.burn_per_onhand, 0) / i.burn_per_week * 7
            - COALESCE(i.cushion_weeks, 0) * 7
        )::INT
        ELSE NULL
    END AS next_order_date

FROM invnt_item i
LEFT JOIN latest_onhand lo ON lo.invnt_item_id = i.id
LEFT JOIN open_orders oo ON oo.invnt_item_id = i.id
WHERE i.is_deleted = false;
