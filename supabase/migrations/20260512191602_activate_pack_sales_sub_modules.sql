-- Activate Pack + Sales modules and seed their first sub-modules
-- ===============================================================
-- Hawaii Farming is bringing Pack and Sales online. Three sub-modules
-- per module to start:
--   Pack:  Products, Packlot, Packing
--   Sales: Customers, FOB, Product Prices
--
-- "Packlot" + "Packing" were already inserted directly on dev (likely
-- via Studio) at access level Manager. This migration standardizes all
-- six entries to Employee access via UPSERT so dev and prod end up
-- consistent regardless of starting state.

BEGIN;

-- 1. Flip is_enabled on the org_module rows so the modules show up in
--    the nav for HF.
UPDATE public.org_module
   SET is_enabled = true,
       updated_at = now(),
       updated_by = 'data@hawaiifarming.com'
 WHERE org_id        = 'hawaii_farming'
   AND sys_module_id IN ('Pack', 'Sales')
   AND is_enabled    = false;

-- 2. Seed sys_sub_module catalog. UPSERT so we converge state between
--    dev (where Packlot + Packing already exist at Manager) and prod
--    (where they may not exist at all).
INSERT INTO public.sys_sub_module
    (id, sys_module_id, sys_access_level_id, display_order, created_by, updated_by)
VALUES
    ('Packlot',        'Pack',  'Employee', 1, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('Packing',        'Pack',  'Employee', 2, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('Products',       'Pack',  'Employee', 3, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('Customers',      'Sales', 'Employee', 4, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('FOB',            'Sales', 'Employee', 5, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('Product Prices', 'Sales', 'Employee', 6, 'data@hawaiifarming.com', 'data@hawaiifarming.com')
ON CONFLICT (id) DO UPDATE
    SET sys_module_id       = EXCLUDED.sys_module_id,
        sys_access_level_id = EXCLUDED.sys_access_level_id,
        display_order       = EXCLUDED.display_order,
        updated_at          = now(),
        updated_by          = 'data@hawaiifarming.com';

-- 3. Provision org_sub_module rows for HF so the new sub-modules are
--    visible in the nav. UPSERT for the same dev/prod reasons as above.
INSERT INTO public.org_sub_module
    (org_id, sys_module_id, sys_sub_module_id, sys_access_level_id, is_enabled, display_order, created_by, updated_by)
VALUES
    ('hawaii_farming', 'Pack',  'Packlot',        'Employee', true, 1, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('hawaii_farming', 'Pack',  'Packing',        'Employee', true, 2, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('hawaii_farming', 'Pack',  'Products',       'Employee', true, 3, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('hawaii_farming', 'Sales', 'Customers',      'Employee', true, 4, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('hawaii_farming', 'Sales', 'FOB',            'Employee', true, 5, 'data@hawaiifarming.com', 'data@hawaiifarming.com'),
    ('hawaii_farming', 'Sales', 'Product Prices', 'Employee', true, 6, 'data@hawaiifarming.com', 'data@hawaiifarming.com')
ON CONFLICT (org_id, sys_sub_module_id) DO UPDATE
    SET sys_module_id       = EXCLUDED.sys_module_id,
        sys_access_level_id = EXCLUDED.sys_access_level_id,
        is_enabled          = EXCLUDED.is_enabled,
        display_order       = EXCLUDED.display_order,
        updated_at          = now(),
        updated_by          = 'data@hawaiifarming.com';

COMMIT;
