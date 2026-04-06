-- ============================================================
-- Seed test data for aloha-app
-- Run in Supabase SQL Editor for project kfwqtaazdankxmdlqdak
--
-- Prerequisites: sys_access_level, sys_module, sys_sub_module
-- already seeded. Views already created.
-- ============================================================

-- 1. Org already exists as hawaii_farming

-- 2. Org modules — use existing sys_module IDs
INSERT INTO org_module (id, org_id, sys_module_id, display_name, display_order, is_enabled)
SELECT
  'hf-' || sm.id,
  'hawaii_farming',
  sm.id,
  sm.name,
  sm.display_order,
  true
FROM sys_module sm
WHERE sm.is_deleted = false
ON CONFLICT (org_id, sys_module_id) DO NOTHING;

-- 3. Org sub-modules — use existing sys_sub_module IDs and access levels
INSERT INTO org_sub_module (id, org_id, sys_module_id, sys_sub_module_id, sys_access_level_id, display_name, display_order, is_enabled)
SELECT
  'hf-' || ssm.id,
  'hawaii_farming',
  ssm.sys_module_id,
  ssm.id,
  ssm.sys_access_level_id,
  ssm.name,
  ssm.display_order,
  true
FROM sys_sub_module ssm
WHERE ssm.is_deleted = false
ON CONFLICT (org_id, sys_module_id, sys_sub_module_id) DO NOTHING;

-- 4. Test users + employees + module access
DO $$
DECLARE
  v_owner_id    UUID;
  v_manager_id  UUID;
  v_employee_id UUID;
  v_mod         RECORD;
BEGIN
  -- Check for existing users first, create only if missing
  SELECT id INTO v_owner_id FROM auth.users WHERE email = 'admin@hawaiifarming.com';
  IF v_owner_id IS NULL THEN
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
    ) RETURNING id INTO v_owner_id;

    INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (gen_random_uuid(), v_owner_id, 'admin@hawaiifarming.com',
      jsonb_build_object('sub', v_owner_id, 'email', 'admin@hawaiifarming.com'),
      'email', now(), now(), now());
  END IF;

  SELECT id INTO v_manager_id FROM auth.users WHERE email = 'manager@hawaiifarming.com';
  IF v_manager_id IS NULL THEN
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
    ) RETURNING id INTO v_manager_id;

    INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (gen_random_uuid(), v_manager_id, 'manager@hawaiifarming.com',
      jsonb_build_object('sub', v_manager_id, 'email', 'manager@hawaiifarming.com'),
      'email', now(), now(), now());
  END IF;

  SELECT id INTO v_employee_id FROM auth.users WHERE email = 'employee@hawaiifarming.com';
  IF v_employee_id IS NULL THEN
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
    ) RETURNING id INTO v_employee_id;

    INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (gen_random_uuid(), v_employee_id, 'employee@hawaiifarming.com',
      jsonb_build_object('sub', v_employee_id, 'email', 'employee@hawaiifarming.com'),
      'email', now(), now(), now());
  END IF;

  -- hr_employee records
  INSERT INTO hr_employee (id, org_id, first_name, last_name, email, user_id, sys_access_level_id) VALUES
    ('hf-admin',    'hawaii_farming', 'Admin',  'Owner',   'admin@hawaiifarming.com',    v_owner_id,    'owner'),
    ('hf-manager',  'hawaii_farming', 'Farm',   'Manager', 'manager@hawaiifarming.com',  v_manager_id,  'manager'),
    ('hf-employee', 'hawaii_farming', 'Field',  'Worker',  'employee@hawaiifarming.com', v_employee_id, 'employee')
  ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id;

  -- Owner: all modules, full permissions
  FOR v_mod IN SELECT id FROM org_module WHERE org_id = 'hawaii_farming' AND is_deleted = false
  LOOP
    INSERT INTO hr_module_access (org_id, hr_employee_id, org_module_id, is_enabled, can_edit, can_delete, can_verify)
    VALUES ('hawaii_farming', 'hf-admin', v_mod.id, true, true, true, true)
    ON CONFLICT (hr_employee_id, org_module_id) DO NOTHING;
  END LOOP;

  -- Manager: inventory, operations, grow, pack
  FOR v_mod IN
    SELECT id FROM org_module
    WHERE org_id = 'hawaii_farming'
      AND sys_module_id IN ('inventory', 'operations', 'grow', 'pack')
      AND is_deleted = false
  LOOP
    INSERT INTO hr_module_access (org_id, hr_employee_id, org_module_id, is_enabled, can_edit, can_delete, can_verify)
    VALUES ('hawaii_farming', 'hf-manager', v_mod.id, true, true, false, true)
    ON CONFLICT (hr_employee_id, org_module_id) DO NOTHING;
  END LOOP;

  -- Employee: operations and grow only
  FOR v_mod IN
    SELECT id FROM org_module
    WHERE org_id = 'hawaii_farming'
      AND sys_module_id IN ('operations', 'grow')
      AND is_deleted = false
  LOOP
    INSERT INTO hr_module_access (org_id, hr_employee_id, org_module_id, is_enabled, can_edit, can_delete, can_verify)
    VALUES ('hawaii_farming', 'hf-employee', v_mod.id, true, true, false, false)
    ON CONFLICT (hr_employee_id, org_module_id) DO NOTHING;
  END LOOP;

  RAISE NOTICE 'Seed complete. Test users:';
  RAISE NOTICE '  Owner:    admin@hawaiifarming.com / password123 (user_id: %)', v_owner_id;
  RAISE NOTICE '  Manager:  manager@hawaiifarming.com / password123 (user_id: %)', v_manager_id;
  RAISE NOTICE '  Employee: employee@hawaiifarming.com / password123 (user_id: %)', v_employee_id;
END $$;
