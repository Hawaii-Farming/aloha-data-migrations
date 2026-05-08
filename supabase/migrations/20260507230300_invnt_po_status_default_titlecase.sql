-- invnt_po.status default was 'requested' (lowercase) but the CHECK
-- constraint requires Title-Case ('Requested', 'Approved', ...). Same
-- bug for invnt_po.request_type default ('inventory_item' lowercase
-- vs CHECK requiring 'Inventory Item'). Inserts relying on these
-- defaults would fail. Original migration 20260401000035 has been
-- edited in place; this patch fixes the live DBs.

ALTER TABLE invnt_po ALTER COLUMN status SET DEFAULT 'Requested';
ALTER TABLE invnt_po ALTER COLUMN request_type SET DEFAULT 'Inventory Item';
