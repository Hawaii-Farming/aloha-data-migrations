-- ============================================================
-- PART 1: View Contracts (Template <-> Consumer Schema Bridge)
-- Run this in Supabase SQL Editor for project kfwqtaazdankxmdlqdak
-- ============================================================

CREATE OR REPLACE VIEW public.app_user_profile
WITH (security_invoker = true)
AS
SELECT
  e.id         AS employee_id,
  e.org_id     AS org_id,
  e.first_name AS first_name,
  e.last_name  AS last_name,
  e.user_id    AS auth_user_id,
  e.sys_access_level_id AS access_level_id
FROM public.hr_employee e
WHERE e.user_id IS NOT NULL
  AND e.user_id = auth.uid()
  AND e.is_deleted = false;

CREATE OR REPLACE VIEW public.app_user_orgs
WITH (security_invoker = true)
AS
SELECT
  o.id       AS org_id,
  o.name     AS org_name,
  e.user_id  AS auth_user_id
FROM public.hr_employee e
JOIN public.org o ON o.id = e.org_id
WHERE e.user_id IS NOT NULL
  AND e.user_id = auth.uid()
  AND e.is_deleted = false
  AND o.is_deleted = false;

CREATE OR REPLACE VIEW public.app_org_context
WITH (security_invoker = true)
AS
SELECT
  o.id       AS org_id,
  o.name     AS org_name,
  e.id       AS employee_id,
  e.user_id  AS auth_user_id,
  e.sys_access_level_id AS access_level_id
FROM public.hr_employee e
JOIN public.org o ON o.id = e.org_id
WHERE e.user_id IS NOT NULL
  AND e.user_id = auth.uid()
  AND e.is_deleted = false
  AND o.is_deleted = false;

CREATE OR REPLACE VIEW public.app_nav_modules
WITH (security_invoker = true)
AS
SELECT
  om.id               AS module_id,
  om.org_id            AS org_id,
  om.sys_module_id     AS module_slug,
  om.display_name      AS display_name,
  om.display_order     AS display_order,
  hma.can_edit         AS can_edit,
  hma.can_delete       AS can_delete,
  hma.can_verify       AS can_verify
FROM public.org_module om
JOIN public.hr_module_access hma
  ON hma.org_module_id = om.id
  AND hma.is_enabled = true
  AND hma.is_deleted = false
JOIN public.hr_employee e
  ON e.id = hma.hr_employee_id
  AND e.user_id = auth.uid()
  AND e.is_deleted = false
WHERE om.is_enabled = true
  AND om.is_deleted = false;

CREATE OR REPLACE VIEW public.app_nav_sub_modules
WITH (security_invoker = true)
AS
SELECT
  osm.id                AS sub_module_id,
  osm.org_id            AS org_id,
  osm.sys_module_id     AS module_slug,
  osm.sys_sub_module_id AS sub_module_slug,
  osm.display_name      AS display_name,
  osm.display_order     AS display_order
FROM public.org_sub_module osm
JOIN public.hr_employee e
  ON e.org_id = osm.org_id
  AND e.user_id = auth.uid()
  AND e.is_deleted = false
JOIN public.sys_access_level sal_user
  ON sal_user.id = e.sys_access_level_id
JOIN public.sys_access_level sal_required
  ON sal_required.id = osm.sys_access_level_id
WHERE osm.is_enabled = true
  AND osm.is_deleted = false
  AND sal_user.level >= sal_required.level;

GRANT SELECT ON public.app_user_profile TO authenticated;
GRANT SELECT ON public.app_user_orgs TO authenticated;
GRANT SELECT ON public.app_org_context TO authenticated;
GRANT SELECT ON public.app_nav_modules TO authenticated;
GRANT SELECT ON public.app_nav_sub_modules TO authenticated;

-- ============================================================
-- PART 2: Seed Data for Testing
-- ============================================================

-- 2a. System access levels
INSERT INTO sys_access_level (id, name, level, display_order) VALUES
  ('employee',  'Employee',  1, 1),
  ('team_lead', 'Team Lead', 2, 2),
  ('manager',   'Manager',   3, 3),
  ('admin',     'Admin',     4, 4),
  ('owner',     'Owner',     5, 5)
ON CONFLICT (id) DO NOTHING;

-- 2b. System modules
INSERT INTO sys_module (id, name, display_order) VALUES
  ('inventory',   'Inventory',   1),
  ('hr',          'HR',          2),
  ('operations',  'Operations',  3),
  ('grow',        'Grow',        4),
  ('pack',        'Pack',        5),
  ('sales',       'Sales',       6),
  ('maintenance', 'Maintenance', 7),
  ('food_safety', 'Food Safety', 8)
ON CONFLICT (id) DO NOTHING;

-- 2c. System sub-modules (representative subset)
INSERT INTO sys_sub_module (id, sys_module_id, name, sys_access_level_id, display_order) VALUES
  ('invnt_vendors',   'inventory',   'Vendors',          'employee',  1),
  ('invnt_items',     'inventory',   'Items',            'employee',  2),
  ('invnt_pos',       'inventory',   'Purchase Orders',  'manager',   3),
  ('hr_employees',    'hr',          'Employees',        'manager',   1),
  ('hr_departments',  'hr',          'Departments',      'admin',     2),
  ('hr_payroll',      'hr',          'Payroll',          'owner',     3),
  ('ops_tasks',       'operations',  'Tasks',            'employee',  1),
  ('ops_training',    'operations',  'Training',         'team_lead', 2),
  ('ops_checklists',  'operations',  'Checklists',       'employee',  3),
  ('grow_seeding',    'grow',        'Seeding',          'employee',  1),
  ('grow_harvesting', 'grow',        'Harvesting',       'employee',  2),
  ('grow_scouting',   'grow',        'Scouting',         'employee',  3),
  ('grow_spraying',   'grow',        'Spraying',         'team_lead', 4),
  ('pack_lots',       'pack',        'Lots',             'employee',  1),
  ('pack_productivity','pack',       'Productivity',     'team_lead', 2),
  ('sales_customers', 'sales',       'Customers',        'manager',   1),
  ('sales_orders',    'sales',       'Orders',           'employee',  2),
  ('sales_products',  'sales',       'Products',         'manager',   3),
  ('maint_requests',  'maintenance', 'Work Orders',      'employee',  1),
  ('fsafe_testing',   'food_safety', 'Testing',          'team_lead', 1)
ON CONFLICT (id) DO NOTHING;

-- 2d. Test organization
INSERT INTO org (id, name, currency) VALUES
  ('hawaii-farming', 'Hawaii Farming', 'USD')
ON CONFLICT (id) DO NOTHING;

-- 2e. Org modules (enable all for Hawaii Farming)
INSERT INTO org_module (id, org_id, sys_module_id, display_name, display_order, is_enabled) VALUES
  ('hf-inventory',   'hawaii-farming', 'inventory',   'Inventory',   1, true),
  ('hf-hr',          'hawaii-farming', 'hr',          'HR',          2, true),
  ('hf-operations',  'hawaii-farming', 'operations',  'Operations',  3, true),
  ('hf-grow',        'hawaii-farming', 'grow',        'Grow',        4, true),
  ('hf-pack',        'hawaii-farming', 'pack',        'Pack',        5, true),
  ('hf-sales',       'hawaii-farming', 'sales',       'Sales',       6, true),
  ('hf-maintenance', 'hawaii-farming', 'maintenance', 'Maintenance', 7, true),
  ('hf-food_safety', 'hawaii-farming', 'food_safety', 'Food Safety', 8, true)
ON CONFLICT (id) DO NOTHING;

-- 2f. Org sub-modules (enable all for Hawaii Farming)
INSERT INTO org_sub_module (id, org_id, sys_module_id, sys_sub_module_id, sys_access_level_id, display_name, display_order, is_enabled) VALUES
  ('hf-invnt_vendors',    'hawaii-farming', 'inventory',   'invnt_vendors',    'employee',  'Vendors',         1, true),
  ('hf-invnt_items',      'hawaii-farming', 'inventory',   'invnt_items',      'employee',  'Items',           2, true),
  ('hf-invnt_pos',        'hawaii-farming', 'inventory',   'invnt_pos',        'manager',   'Purchase Orders', 3, true),
  ('hf-hr_employees',     'hawaii-farming', 'hr',          'hr_employees',     'manager',   'Employees',       1, true),
  ('hf-hr_departments',   'hawaii-farming', 'hr',          'hr_departments',   'admin',     'Departments',     2, true),
  ('hf-hr_payroll',       'hawaii-farming', 'hr',          'hr_payroll',       'owner',     'Payroll',         3, true),
  ('hf-ops_tasks',        'hawaii-farming', 'operations',  'ops_tasks',        'employee',  'Tasks',           1, true),
  ('hf-ops_training',     'hawaii-farming', 'operations',  'ops_training',     'team_lead', 'Training',        2, true),
  ('hf-ops_checklists',   'hawaii-farming', 'operations',  'ops_checklists',   'employee',  'Checklists',      3, true),
  ('hf-grow_seeding',     'hawaii-farming', 'grow',        'grow_seeding',     'employee',  'Seeding',         1, true),
  ('hf-grow_harvesting',  'hawaii-farming', 'grow',        'grow_harvesting',  'employee',  'Harvesting',      2, true),
  ('hf-grow_scouting',    'hawaii-farming', 'grow',        'grow_scouting',    'employee',  'Scouting',        3, true),
  ('hf-grow_spraying',    'hawaii-farming', 'grow',        'grow_spraying',    'team_lead', 'Spraying',        4, true),
  ('hf-pack_lots',        'hawaii-farming', 'pack',        'pack_lots',        'employee',  'Lots',            1, true),
  ('hf-pack_productivity','hawaii-farming', 'pack',        'pack_productivity','team_lead', 'Productivity',    2, true),
  ('hf-sales_customers',  'hawaii-farming', 'sales',       'sales_customers',  'manager',   'Customers',       1, true),
  ('hf-sales_orders',     'hawaii-farming', 'sales',       'sales_orders',     'employee',  'Orders',          2, true),
  ('hf-sales_products',   'hawaii-farming', 'sales',       'sales_products',   'manager',   'Products',        3, true),
  ('hf-maint_requests',   'hawaii-farming', 'maintenance', 'maint_requests',   'employee',  'Work Orders',     1, true),
  ('hf-fsafe_testing',    'hawaii-farming', 'food_safety', 'fsafe_testing',    'team_lead', 'Testing',         1, true)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- PART 3: Test Users
-- Create via Supabase Auth, then link to hr_employee
-- ============================================================

-- 3a. Create test users in auth.users
-- Owner: admin@hawaiifarming.com / password123
-- Manager: manager@hawaiifarming.com / password123
-- Employee: employee@hawaiifarming.com / password123

DO $$
DECLARE
  v_owner_id   UUID;
  v_manager_id UUID;
  v_employee_id UUID;
BEGIN
  -- Create owner user
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, is_super_admin
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    'admin@hawaiifarming.com',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Admin Owner"}'::jsonb,
    now(), now(), '', false
  )
  ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
  RETURNING id INTO v_owner_id;

  -- Create manager user
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, is_super_admin
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    'manager@hawaiifarming.com',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Farm Manager"}'::jsonb,
    now(), now(), '', false
  )
  ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
  RETURNING id INTO v_manager_id;

  -- Create employee user
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, is_super_admin
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    'employee@hawaiifarming.com',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"Field Worker"}'::jsonb,
    now(), now(), '', false
  )
  ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
  RETURNING id INTO v_employee_id;

  -- 3b. Create identities for each user (required for Supabase Auth login)
  INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_owner_id, 'admin@hawaiifarming.com',
     jsonb_build_object('sub', v_owner_id, 'email', 'admin@hawaiifarming.com'),
     'email', now(), now(), now()),
    (gen_random_uuid(), v_manager_id, 'manager@hawaiifarming.com',
     jsonb_build_object('sub', v_manager_id, 'email', 'manager@hawaiifarming.com'),
     'email', now(), now(), now()),
    (gen_random_uuid(), v_employee_id, 'employee@hawaiifarming.com',
     jsonb_build_object('sub', v_employee_id, 'email', 'employee@hawaiifarming.com'),
     'email', now(), now(), now())
  ON CONFLICT DO NOTHING;

  -- 3c. Link users to hr_employee records
  INSERT INTO hr_employee (id, org_id, first_name, last_name, email, user_id, sys_access_level_id) VALUES
    ('hf-admin',    'hawaii-farming', 'Admin',   'Owner',   'admin@hawaiifarming.com',    v_owner_id,    'owner'),
    ('hf-manager',  'hawaii-farming', 'Farm',    'Manager', 'manager@hawaiifarming.com',  v_manager_id,  'manager'),
    ('hf-employee', 'hawaii-farming', 'Field',   'Worker',  'employee@hawaiifarming.com', v_employee_id, 'employee')
  ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id;

  -- 3d. Grant module access to each employee
  -- Owner gets all modules
  INSERT INTO hr_module_access (org_id, hr_employee_id, org_module_id, is_enabled, can_edit, can_delete, can_verify) VALUES
    ('hawaii-farming', 'hf-admin', 'hf-inventory',   true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-hr',          true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-operations',  true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-grow',        true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-pack',        true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-sales',       true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-maintenance', true, true, true, true),
    ('hawaii-farming', 'hf-admin', 'hf-food_safety', true, true, true, true)
  ON CONFLICT (hr_employee_id, org_module_id) DO NOTHING;

  -- Manager gets operations, grow, pack, inventory
  INSERT INTO hr_module_access (org_id, hr_employee_id, org_module_id, is_enabled, can_edit, can_delete, can_verify) VALUES
    ('hawaii-farming', 'hf-manager', 'hf-inventory',  true, true, false, true),
    ('hawaii-farming', 'hf-manager', 'hf-operations', true, true, false, true),
    ('hawaii-farming', 'hf-manager', 'hf-grow',       true, true, false, true),
    ('hawaii-farming', 'hf-manager', 'hf-pack',       true, true, false, true)
  ON CONFLICT (hr_employee_id, org_module_id) DO NOTHING;

  -- Employee gets operations and grow only
  INSERT INTO hr_module_access (org_id, hr_employee_id, org_module_id, is_enabled, can_edit, can_delete, can_verify) VALUES
    ('hawaii-farming', 'hf-employee', 'hf-operations', true, true, false, false),
    ('hawaii-farming', 'hf-employee', 'hf-grow',       true, true, false, false)
  ON CONFLICT (hr_employee_id, org_module_id) DO NOTHING;

  RAISE NOTICE 'Seed complete. Test users:';
  RAISE NOTICE '  Owner:    admin@hawaiifarming.com / password123 (user_id: %)', v_owner_id;
  RAISE NOTICE '  Manager:  manager@hawaiifarming.com / password123 (user_id: %)', v_manager_id;
  RAISE NOTICE '  Employee: employee@hawaiifarming.com / password123 (user_id: %)', v_employee_id;
END $$;
