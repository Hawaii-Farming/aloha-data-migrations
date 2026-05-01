-- System RLS Policies & Helpers
-- ==============================
-- Single home for every Row-Level Security policy and the helper functions
-- they depend on. Lives at the end of the migration chain because policies
-- reference tables created earlier and the helper function reads from
-- hr_employee -- both must exist before this file runs.
--
-- Policy convention for org-scoped tables: SELECT-only RLS using
-- get_user_org_ids() to bound rows to the caller's org membership.
-- Mutations flow through the service_role key in server-side route
-- actions; granular CRUD (can_create / can_edit / can_delete /
-- can_verify) is enforced in the app layer via hr_module_access
-- before each write. Direct PostgREST writes from the browser session
-- client are blocked because no INSERT/UPDATE/DELETE policy permits
-- them. Every org-scoped table follows this same pattern with no
-- exceptions.
--
-- Policies are ordered to match the order their tables are created in
-- the migration chain.

-- ============================================================
-- Helper: get_user_org_ids()
-- ============================================================
-- Returns the org_ids the currently authenticated user belongs to.
-- SECURITY DEFINER + RLS-bypassing query into hr_employee so policies
-- on hr_employee can call this without re-triggering their own RLS
-- (which would infinite-recurse).

CREATE OR REPLACE FUNCTION public.get_user_org_ids()
RETURNS SETOF TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT org_id FROM public.hr_employee
  WHERE user_id = auth.uid()
    AND is_deleted = false;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_org_ids() TO authenticated;

-- ============================================================
-- org
-- ============================================================
-- The root tenant table. Policy is keyed on `id` (the org PK) rather
-- than `org_id` since this IS the org row itself.

ALTER TABLE public.org ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_read" ON public.org
  FOR SELECT TO authenticated
  USING (id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org TO authenticated;

-- ============================================================
-- org_module
-- ============================================================

ALTER TABLE public.org_module ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_module_read" ON public.org_module
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_module TO authenticated;

-- ============================================================
-- org_sub_module
-- ============================================================

ALTER TABLE public.org_sub_module ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_sub_module_read" ON public.org_sub_module
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_sub_module TO authenticated;

-- ============================================================
-- org_farm
-- ============================================================

ALTER TABLE public.org_farm ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_farm_read" ON public.org_farm
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_farm TO authenticated;

-- ============================================================
-- org_site_category
-- ============================================================

ALTER TABLE public.org_site_category ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_category_read" ON public.org_site_category
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site_category TO authenticated;

-- ============================================================
-- org_site
-- ============================================================

ALTER TABLE public.org_site ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_read" ON public.org_site
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site TO authenticated;

-- ============================================================
-- org_site_cuke_gh
-- ============================================================

ALTER TABLE public.org_site_cuke_gh ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_cuke_gh_read" ON public.org_site_cuke_gh
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site_cuke_gh TO authenticated;

-- ============================================================
-- org_site_cuke_gh_block
-- ============================================================

ALTER TABLE public.org_site_cuke_gh_block ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_cuke_gh_block_read" ON public.org_site_cuke_gh_block
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site_cuke_gh_block TO authenticated;

-- ============================================================
-- org_site_cuke_gh_row
-- ============================================================

ALTER TABLE public.org_site_cuke_gh_row ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_cuke_gh_row_read" ON public.org_site_cuke_gh_row
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site_cuke_gh_row TO authenticated;

-- ============================================================
-- org_site_housing
-- ============================================================

ALTER TABLE public.org_site_housing ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_housing_read" ON public.org_site_housing
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site_housing TO authenticated;

-- ============================================================
-- org_site_housing_area
-- ============================================================

ALTER TABLE public.org_site_housing_area ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_site_housing_area_read" ON public.org_site_housing_area
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_site_housing_area TO authenticated;

-- ============================================================
-- org_equipment
-- ============================================================

ALTER TABLE public.org_equipment ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_equipment_read" ON public.org_equipment
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_equipment TO authenticated;

-- ============================================================
-- org_business_rule
-- ============================================================

ALTER TABLE public.org_business_rule ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_business_rule_read" ON public.org_business_rule
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.org_business_rule TO authenticated;

-- ============================================================
-- grow_variety
-- ============================================================

ALTER TABLE public.grow_variety ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_variety_read" ON public.grow_variety
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_variety TO authenticated;

-- ============================================================
-- grow_grade
-- ============================================================

ALTER TABLE public.grow_grade ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_grade_read" ON public.grow_grade
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_grade TO authenticated;

-- ============================================================
-- hr_department
-- ============================================================

ALTER TABLE public.hr_department ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_department_read" ON public.hr_department
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_department TO authenticated;

-- ============================================================
-- hr_work_authorization
-- ============================================================

ALTER TABLE public.hr_work_authorization ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_work_authorization_read" ON public.hr_work_authorization
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_work_authorization TO authenticated;

-- ============================================================
-- hr_employee
-- ============================================================

ALTER TABLE public.hr_employee ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_employee_read" ON public.hr_employee
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_employee TO authenticated;

-- ============================================================
-- hr_module_access
-- ============================================================

ALTER TABLE public.hr_module_access ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_module_access_read" ON public.hr_module_access
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_module_access TO authenticated;

-- ============================================================
-- hr_time_off_request
-- ============================================================

ALTER TABLE public.hr_time_off_request ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_time_off_request_read" ON public.hr_time_off_request
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_time_off_request TO authenticated;

-- ============================================================
-- hr_travel_request
-- ============================================================

ALTER TABLE public.hr_travel_request ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_travel_request_read" ON public.hr_travel_request
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_travel_request TO authenticated;

-- ============================================================
-- hr_disciplinary_warning
-- ============================================================

ALTER TABLE public.hr_disciplinary_warning ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_disciplinary_warning_read" ON public.hr_disciplinary_warning
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_disciplinary_warning TO authenticated;

-- ============================================================
-- hr_payroll
-- ============================================================

ALTER TABLE public.hr_payroll ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_payroll_read" ON public.hr_payroll
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_payroll TO authenticated;

-- ============================================================
-- hr_employee_review
-- ============================================================

ALTER TABLE public.hr_employee_review ENABLE ROW LEVEL SECURITY;

CREATE POLICY "hr_employee_review_read" ON public.hr_employee_review
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.hr_employee_review TO authenticated;

-- ============================================================
-- invnt_vendor
-- ============================================================

ALTER TABLE public.invnt_vendor ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_vendor_read" ON public.invnt_vendor
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_vendor TO authenticated;

-- ============================================================
-- invnt_category
-- ============================================================

ALTER TABLE public.invnt_category ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_category_read" ON public.invnt_category
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_category TO authenticated;

-- ============================================================
-- invnt_item
-- ============================================================

ALTER TABLE public.invnt_item ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_item_read" ON public.invnt_item
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_item TO authenticated;

-- ============================================================
-- invnt_po
-- ============================================================

ALTER TABLE public.invnt_po ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_po_read" ON public.invnt_po
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_po TO authenticated;

-- ============================================================
-- invnt_lot
-- ============================================================

ALTER TABLE public.invnt_lot ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_lot_read" ON public.invnt_lot
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_lot TO authenticated;

-- ============================================================
-- invnt_po_received
-- ============================================================

ALTER TABLE public.invnt_po_received ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_po_received_read" ON public.invnt_po_received
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_po_received TO authenticated;

-- ============================================================
-- invnt_onhand
-- ============================================================

ALTER TABLE public.invnt_onhand ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invnt_onhand_read" ON public.invnt_onhand
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.invnt_onhand TO authenticated;

-- ============================================================
-- ops_task
-- ============================================================

ALTER TABLE public.ops_task ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_task_read" ON public.ops_task
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_task TO authenticated;

-- ============================================================
-- sales_product
-- ============================================================

ALTER TABLE public.sales_product ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_product_read" ON public.sales_product
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_product TO authenticated;

-- ============================================================
-- ops_task_tracker
-- ============================================================

ALTER TABLE public.ops_task_tracker ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_task_tracker_read" ON public.ops_task_tracker
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_task_tracker TO authenticated;

-- ============================================================
-- ops_task_schedule
-- ============================================================

ALTER TABLE public.ops_task_schedule ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_task_schedule_read" ON public.ops_task_schedule
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_task_schedule TO authenticated;

-- ============================================================
-- ops_training_type
-- ============================================================

ALTER TABLE public.ops_training_type ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_training_type_read" ON public.ops_training_type
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_training_type TO authenticated;

-- ============================================================
-- ops_training
-- ============================================================

ALTER TABLE public.ops_training ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_training_read" ON public.ops_training
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_training TO authenticated;

-- ============================================================
-- ops_training_attendee
-- ============================================================

ALTER TABLE public.ops_training_attendee ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_training_attendee_read" ON public.ops_training_attendee
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_training_attendee TO authenticated;

-- ============================================================
-- ops_template
-- ============================================================

ALTER TABLE public.ops_template ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_template_read" ON public.ops_template
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_template TO authenticated;

-- ============================================================
-- ops_task_template
-- ============================================================

ALTER TABLE public.ops_task_template ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_task_template_read" ON public.ops_task_template
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_task_template TO authenticated;

-- ============================================================
-- ops_corrective_action_choice
-- ============================================================

ALTER TABLE public.ops_corrective_action_choice ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_corrective_action_choice_read" ON public.ops_corrective_action_choice
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_corrective_action_choice TO authenticated;

-- ============================================================
-- ops_template_question
-- ============================================================

ALTER TABLE public.ops_template_question ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_template_question_read" ON public.ops_template_question
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_template_question TO authenticated;

-- ============================================================
-- ops_template_result
-- ============================================================

ALTER TABLE public.ops_template_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_template_result_read" ON public.ops_template_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_template_result TO authenticated;

-- ============================================================
-- ops_template_result_photo
-- ============================================================

ALTER TABLE public.ops_template_result_photo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_template_result_photo_read" ON public.ops_template_result_photo
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_template_result_photo TO authenticated;

-- ============================================================
-- grow_cycle_pattern
-- ============================================================

ALTER TABLE public.grow_cycle_pattern ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_cycle_pattern_read" ON public.grow_cycle_pattern
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_cycle_pattern TO authenticated;

-- ============================================================
-- grow_trial_type
-- ============================================================

ALTER TABLE public.grow_trial_type ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_trial_type_read" ON public.grow_trial_type
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_trial_type TO authenticated;

-- ============================================================
-- grow_lettuce_seed_mix
-- ============================================================

ALTER TABLE public.grow_lettuce_seed_mix ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_lettuce_seed_mix_read" ON public.grow_lettuce_seed_mix
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_lettuce_seed_mix TO authenticated;

-- ============================================================
-- grow_lettuce_seed_mix_item
-- ============================================================

ALTER TABLE public.grow_lettuce_seed_mix_item ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_lettuce_seed_mix_item_read" ON public.grow_lettuce_seed_mix_item
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_lettuce_seed_mix_item TO authenticated;

-- ============================================================
-- grow_lettuce_seed_batch
-- ============================================================

ALTER TABLE public.grow_lettuce_seed_batch ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_lettuce_seed_batch_read" ON public.grow_lettuce_seed_batch
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_lettuce_seed_batch TO authenticated;

-- ============================================================
-- grow_cuke_seed_batch
-- ============================================================

ALTER TABLE public.grow_cuke_seed_batch ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_cuke_seed_batch_read" ON public.grow_cuke_seed_batch
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_cuke_seed_batch TO authenticated;

-- ============================================================
-- grow_harvest_container
-- ============================================================

ALTER TABLE public.grow_harvest_container ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_harvest_container_read" ON public.grow_harvest_container
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_harvest_container TO authenticated;

-- ============================================================
-- grow_harvest_weight
-- ============================================================

ALTER TABLE public.grow_harvest_weight ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_harvest_weight_read" ON public.grow_harvest_weight
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_harvest_weight TO authenticated;

-- ============================================================
-- grow_scout_result
-- ============================================================

ALTER TABLE public.grow_scout_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_scout_result_read" ON public.grow_scout_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_scout_result TO authenticated;

-- ============================================================
-- grow_spray_compliance
-- ============================================================

ALTER TABLE public.grow_spray_compliance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_spray_compliance_read" ON public.grow_spray_compliance
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_spray_compliance TO authenticated;

-- ============================================================
-- grow_spray_input
-- ============================================================

ALTER TABLE public.grow_spray_input ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_spray_input_read" ON public.grow_spray_input
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_spray_input TO authenticated;

-- ============================================================
-- grow_spray_equipment
-- ============================================================

ALTER TABLE public.grow_spray_equipment ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_spray_equipment_read" ON public.grow_spray_equipment
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_spray_equipment TO authenticated;

-- ============================================================
-- grow_cuke_gh_row_planting
-- ============================================================

ALTER TABLE public.grow_cuke_gh_row_planting ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_cuke_gh_row_planting_read" ON public.grow_cuke_gh_row_planting
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_cuke_gh_row_planting TO authenticated;

-- ============================================================
-- grow_cuke_rotation
-- ============================================================

ALTER TABLE public.grow_cuke_rotation ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_cuke_rotation_read" ON public.grow_cuke_rotation
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_cuke_rotation TO authenticated;

-- ============================================================
-- grow_fertigation_recipe
-- ============================================================

ALTER TABLE public.grow_fertigation_recipe ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_fertigation_recipe_read" ON public.grow_fertigation_recipe
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_fertigation_recipe TO authenticated;

-- ============================================================
-- grow_fertigation_recipe_item
-- ============================================================

ALTER TABLE public.grow_fertigation_recipe_item ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_fertigation_recipe_item_read" ON public.grow_fertigation_recipe_item
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_fertigation_recipe_item TO authenticated;

-- ============================================================
-- grow_fertigation_recipe_site
-- ============================================================

ALTER TABLE public.grow_fertigation_recipe_site ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_fertigation_recipe_site_read" ON public.grow_fertigation_recipe_site
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_fertigation_recipe_site TO authenticated;

-- ============================================================
-- grow_fertigation
-- ============================================================

ALTER TABLE public.grow_fertigation ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_fertigation_read" ON public.grow_fertigation
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_fertigation TO authenticated;

-- ============================================================
-- grow_monitoring_metric
-- ============================================================

ALTER TABLE public.grow_monitoring_metric ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_monitoring_metric_read" ON public.grow_monitoring_metric
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_monitoring_metric TO authenticated;

-- ============================================================
-- grow_monitoring_result
-- ============================================================

ALTER TABLE public.grow_monitoring_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_monitoring_result_read" ON public.grow_monitoring_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_monitoring_result TO authenticated;

-- ============================================================
-- grow_task_seed_batch
-- ============================================================

ALTER TABLE public.grow_task_seed_batch ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_task_seed_batch_read" ON public.grow_task_seed_batch
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_task_seed_batch TO authenticated;

-- ============================================================
-- grow_task_photo
-- ============================================================

ALTER TABLE public.grow_task_photo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_task_photo_read" ON public.grow_task_photo
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_task_photo TO authenticated;

-- ============================================================
-- sales_fob
-- ============================================================

ALTER TABLE public.sales_fob ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_fob_read" ON public.sales_fob
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_fob TO authenticated;

-- ============================================================
-- sales_customer_group
-- ============================================================

ALTER TABLE public.sales_customer_group ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_customer_group_read" ON public.sales_customer_group
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_customer_group TO authenticated;

-- ============================================================
-- sales_customer
-- ============================================================

ALTER TABLE public.sales_customer ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_customer_read" ON public.sales_customer
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_customer TO authenticated;

-- ============================================================
-- sales_product_price
-- ============================================================

ALTER TABLE public.sales_product_price ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_product_price_read" ON public.sales_product_price
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_product_price TO authenticated;

-- ============================================================
-- sales_po
-- ============================================================

ALTER TABLE public.sales_po ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_po_read" ON public.sales_po
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_po TO authenticated;

-- ============================================================
-- sales_po_line
-- ============================================================

ALTER TABLE public.sales_po_line ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_po_line_read" ON public.sales_po_line
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_po_line TO authenticated;

-- ============================================================
-- pack_lot
-- ============================================================

ALTER TABLE public.pack_lot ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_lot_read" ON public.pack_lot
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_lot TO authenticated;

-- ============================================================
-- sales_container_type
-- ============================================================

ALTER TABLE public.sales_container_type ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_container_type_read" ON public.sales_container_type
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_container_type TO authenticated;

-- ============================================================
-- pack_lot_item
-- ============================================================

ALTER TABLE public.pack_lot_item ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_lot_item_read" ON public.pack_lot_item
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_lot_item TO authenticated;

-- ============================================================
-- sales_po_fulfillment
-- ============================================================

ALTER TABLE public.sales_po_fulfillment ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_po_fulfillment_read" ON public.sales_po_fulfillment
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_po_fulfillment TO authenticated;

-- ============================================================
-- sales_crm_external_product
-- ============================================================

ALTER TABLE public.sales_crm_external_product ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_crm_external_product_read" ON public.sales_crm_external_product
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_crm_external_product TO authenticated;

-- ============================================================
-- sales_crm_store
-- ============================================================

ALTER TABLE public.sales_crm_store ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_crm_store_read" ON public.sales_crm_store
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_crm_store TO authenticated;

-- ============================================================
-- sales_crm_store_visit
-- ============================================================

ALTER TABLE public.sales_crm_store_visit ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_crm_store_visit_read" ON public.sales_crm_store_visit
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_crm_store_visit TO authenticated;

-- ============================================================
-- sales_crm_store_visit_photo
-- ============================================================

ALTER TABLE public.sales_crm_store_visit_photo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_crm_store_visit_photo_read" ON public.sales_crm_store_visit_photo
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_crm_store_visit_photo TO authenticated;

-- ============================================================
-- sales_crm_store_visit_result
-- ============================================================

ALTER TABLE public.sales_crm_store_visit_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_crm_store_visit_result_read" ON public.sales_crm_store_visit_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_crm_store_visit_result TO authenticated;

-- ============================================================
-- sales_invoice
-- ============================================================

ALTER TABLE public.sales_invoice ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_invoice_read" ON public.sales_invoice
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_invoice TO authenticated;

-- ============================================================
-- pack_shelf_life_metric
-- ============================================================

ALTER TABLE public.pack_shelf_life_metric ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_shelf_life_metric_read" ON public.pack_shelf_life_metric
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_shelf_life_metric TO authenticated;

-- ============================================================
-- pack_shelf_life
-- ============================================================

ALTER TABLE public.pack_shelf_life ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_shelf_life_read" ON public.pack_shelf_life
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_shelf_life TO authenticated;

-- ============================================================
-- pack_shelf_life_result
-- ============================================================

ALTER TABLE public.pack_shelf_life_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_shelf_life_result_read" ON public.pack_shelf_life_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_shelf_life_result TO authenticated;

-- ============================================================
-- pack_shelf_life_photo
-- ============================================================

ALTER TABLE public.pack_shelf_life_photo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_shelf_life_photo_read" ON public.pack_shelf_life_photo
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_shelf_life_photo TO authenticated;

-- ============================================================
-- pack_dryer_result
-- ============================================================

ALTER TABLE public.pack_dryer_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_dryer_result_read" ON public.pack_dryer_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_dryer_result TO authenticated;

-- ============================================================
-- pack_productivity_fail_category
-- ============================================================

ALTER TABLE public.pack_productivity_fail_category ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_productivity_fail_category_read" ON public.pack_productivity_fail_category
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_productivity_fail_category TO authenticated;

-- ============================================================
-- pack_productivity_hour
-- ============================================================

ALTER TABLE public.pack_productivity_hour ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_productivity_hour_read" ON public.pack_productivity_hour
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_productivity_hour TO authenticated;

-- ============================================================
-- pack_productivity_hour_fail
-- ============================================================

ALTER TABLE public.pack_productivity_hour_fail ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pack_productivity_hour_fail_read" ON public.pack_productivity_hour_fail
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.pack_productivity_hour_fail TO authenticated;

-- ============================================================
-- maint_request
-- ============================================================

ALTER TABLE public.maint_request ENABLE ROW LEVEL SECURITY;

CREATE POLICY "maint_request_read" ON public.maint_request
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.maint_request TO authenticated;

-- ============================================================
-- maint_request_invnt_item
-- ============================================================

ALTER TABLE public.maint_request_invnt_item ENABLE ROW LEVEL SECURITY;

CREATE POLICY "maint_request_invnt_item_read" ON public.maint_request_invnt_item
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.maint_request_invnt_item TO authenticated;

-- ============================================================
-- maint_request_photo
-- ============================================================

ALTER TABLE public.maint_request_photo ENABLE ROW LEVEL SECURITY;

CREATE POLICY "maint_request_photo_read" ON public.maint_request_photo
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.maint_request_photo TO authenticated;

-- ============================================================
-- fsafe_lab
-- ============================================================

ALTER TABLE public.fsafe_lab ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fsafe_lab_read" ON public.fsafe_lab
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fsafe_lab TO authenticated;

-- ============================================================
-- fsafe_lab_test
-- ============================================================

ALTER TABLE public.fsafe_lab_test ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fsafe_lab_test_read" ON public.fsafe_lab_test
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fsafe_lab_test TO authenticated;

-- ============================================================
-- fsafe_test_hold
-- ============================================================

ALTER TABLE public.fsafe_test_hold ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fsafe_test_hold_read" ON public.fsafe_test_hold
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fsafe_test_hold TO authenticated;

-- ============================================================
-- fsafe_test_hold_po
-- ============================================================

ALTER TABLE public.fsafe_test_hold_po ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fsafe_test_hold_po_read" ON public.fsafe_test_hold_po
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fsafe_test_hold_po TO authenticated;

-- ============================================================
-- fsafe_result
-- ============================================================

ALTER TABLE public.fsafe_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fsafe_result_read" ON public.fsafe_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fsafe_result TO authenticated;

-- ============================================================
-- fsafe_pest_result
-- ============================================================

ALTER TABLE public.fsafe_pest_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fsafe_pest_result_read" ON public.fsafe_pest_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fsafe_pest_result TO authenticated;

-- ============================================================
-- ops_corrective_action_taken
-- ============================================================

ALTER TABLE public.ops_corrective_action_taken ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ops_corrective_action_taken_read" ON public.ops_corrective_action_taken
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.ops_corrective_action_taken TO authenticated;

-- ============================================================
-- fin_expense
-- ============================================================

ALTER TABLE public.fin_expense ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fin_expense_read" ON public.fin_expense
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.fin_expense TO authenticated;

-- ============================================================
-- grow_chemistry_result
-- ============================================================

ALTER TABLE public.grow_chemistry_result ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_chemistry_result_read" ON public.grow_chemistry_result
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_chemistry_result TO authenticated;

-- ============================================================
-- grow_weather_reading
-- ============================================================

ALTER TABLE public.grow_weather_reading ENABLE ROW LEVEL SECURITY;

CREATE POLICY "grow_weather_reading_read" ON public.grow_weather_reading
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.grow_weather_reading TO authenticated;

-- ============================================================
-- sales_trading_partner
-- ============================================================

ALTER TABLE public.sales_trading_partner ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_trading_partner_read" ON public.sales_trading_partner
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_trading_partner TO authenticated;

-- ============================================================
-- sales_product_buyer_part
-- ============================================================

ALTER TABLE public.sales_product_buyer_part ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_product_buyer_part_read" ON public.sales_product_buyer_part
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_product_buyer_part TO authenticated;

-- ============================================================
-- sales_edi_inbound_message
-- ============================================================

ALTER TABLE public.sales_edi_inbound_message ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_edi_inbound_message_read" ON public.sales_edi_inbound_message
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_edi_inbound_message TO authenticated;

-- ============================================================
-- sales_shipment
-- ============================================================

ALTER TABLE public.sales_shipment ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_shipment_read" ON public.sales_shipment
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_shipment TO authenticated;

-- ============================================================
-- sales_shipment_container
-- ============================================================

ALTER TABLE public.sales_shipment_container ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_shipment_container_read" ON public.sales_shipment_container
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_shipment_container TO authenticated;

-- ============================================================
-- sales_pallet
-- ============================================================

ALTER TABLE public.sales_pallet ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_pallet_read" ON public.sales_pallet
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_pallet TO authenticated;

-- ============================================================
-- sales_pallet_allocation
-- ============================================================

ALTER TABLE public.sales_pallet_allocation ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_pallet_allocation_read" ON public.sales_pallet_allocation
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_pallet_allocation TO authenticated;

-- ============================================================
-- sales_po_asn
-- ============================================================

ALTER TABLE public.sales_po_asn ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_po_asn_read" ON public.sales_po_asn
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_po_asn TO authenticated;

-- ============================================================
-- sales_po_asn_carton
-- ============================================================

ALTER TABLE public.sales_po_asn_carton ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_po_asn_carton_read" ON public.sales_po_asn_carton
  FOR SELECT TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT SELECT ON public.sales_po_asn_carton TO authenticated;

-- ============================================================
-- Views
-- ============================================================
-- Views don't carry their own RLS policies. Each view is created with
-- WITH (security_invoker = true) (set in the view's own migration file)
-- so it executes as the calling user, and the per-table policies above
-- gate which rows actually flow through. The grants here just allow the
-- authenticated role to call SELECT on the view. Each view's create
-- migration also issues the same grant — restated here so the central
-- RLS file inventories every authenticated-readable surface.

GRANT SELECT ON public.fin_expense_v                  TO authenticated;
GRANT SELECT ON public.grow_cuke_harvest              TO authenticated;
GRANT SELECT ON public.grow_lettuce_harvest           TO authenticated;
GRANT SELECT ON public.grow_spray_restriction         TO authenticated;
GRANT SELECT ON public.grow_weather_reading_dli       TO authenticated;
GRANT SELECT ON public.hr_payroll_by_task             TO authenticated;
GRANT SELECT ON public.hr_payroll_employee_comparison TO authenticated;
GRANT SELECT ON public.hr_payroll_task_comparison     TO authenticated;
GRANT SELECT ON public.hr_rba_navigation              TO authenticated;
GRANT SELECT ON public.invnt_item_summary             TO authenticated;
GRANT SELECT ON public.ops_task_weekly_schedule       TO authenticated;
GRANT SELECT ON public.org_site_housing_tenant_count  TO authenticated;
GRANT SELECT ON public.sales_invoice_v                TO authenticated;

-- ============================================================
-- WRITE POLICIES (INSERT / UPDATE / DELETE)
-- ============================================================
-- Browser session client (anon JWT) writes directly when row.org_id is
-- one of the caller's orgs. The fine-grained can_edit / can_delete /
-- can_verify flags on hr_module_access are NOT checked at the DB layer
-- -- they exist to drive frontend UI (rendering action buttons) and
-- the app filters by them before allowing a request to leave the client.
--
-- Tables NOT listed here remain service-role-only -- reference data
-- (sys_*, org_module, sales_fob, grow_grade, etc.), tables only written
-- by server workers (sales_edi_inbound_message), or admin-controlled
-- tables (hr_module_access, hr_department, hr_work_authorization,
-- ops_task / ops_template definitions).


-- ===== Operations =====

CREATE POLICY "ops_task_tracker_insert" ON public.ops_task_tracker
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_tracker_update" ON public.ops_task_tracker
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_tracker_delete" ON public.ops_task_tracker
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_task_tracker TO authenticated;

CREATE POLICY "ops_task_schedule_insert" ON public.ops_task_schedule
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_schedule_update" ON public.ops_task_schedule
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_task_schedule_delete" ON public.ops_task_schedule
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_task_schedule TO authenticated;

CREATE POLICY "ops_template_result_insert" ON public.ops_template_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_template_result_update" ON public.ops_template_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_template_result_delete" ON public.ops_template_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_template_result TO authenticated;

CREATE POLICY "ops_template_result_photo_insert" ON public.ops_template_result_photo
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_template_result_photo_update" ON public.ops_template_result_photo
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_template_result_photo_delete" ON public.ops_template_result_photo
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_template_result_photo TO authenticated;

CREATE POLICY "ops_corrective_action_taken_insert" ON public.ops_corrective_action_taken
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_corrective_action_taken_update" ON public.ops_corrective_action_taken
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_corrective_action_taken_delete" ON public.ops_corrective_action_taken
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_corrective_action_taken TO authenticated;

CREATE POLICY "ops_training_insert" ON public.ops_training
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_training_update" ON public.ops_training
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_training_delete" ON public.ops_training
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_training TO authenticated;

CREATE POLICY "ops_training_attendee_insert" ON public.ops_training_attendee
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_training_attendee_update" ON public.ops_training_attendee
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "ops_training_attendee_delete" ON public.ops_training_attendee
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.ops_training_attendee TO authenticated;

CREATE POLICY "fin_expense_insert" ON public.fin_expense
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fin_expense_update" ON public.fin_expense
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fin_expense_delete" ON public.fin_expense
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fin_expense TO authenticated;


-- ===== Grow =====

CREATE POLICY "grow_task_photo_insert" ON public.grow_task_photo
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_task_photo_update" ON public.grow_task_photo
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_task_photo_delete" ON public.grow_task_photo
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_task_photo TO authenticated;

CREATE POLICY "grow_task_seed_batch_insert" ON public.grow_task_seed_batch
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_task_seed_batch_update" ON public.grow_task_seed_batch
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_task_seed_batch_delete" ON public.grow_task_seed_batch
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_task_seed_batch TO authenticated;

CREATE POLICY "grow_monitoring_result_insert" ON public.grow_monitoring_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_monitoring_result_update" ON public.grow_monitoring_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_monitoring_result_delete" ON public.grow_monitoring_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_monitoring_result TO authenticated;

CREATE POLICY "grow_scout_result_insert" ON public.grow_scout_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_scout_result_update" ON public.grow_scout_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_scout_result_delete" ON public.grow_scout_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_scout_result TO authenticated;

CREATE POLICY "grow_spray_input_insert" ON public.grow_spray_input
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_spray_input_update" ON public.grow_spray_input
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_spray_input_delete" ON public.grow_spray_input
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_spray_input TO authenticated;

CREATE POLICY "grow_spray_equipment_insert" ON public.grow_spray_equipment
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_spray_equipment_update" ON public.grow_spray_equipment
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_spray_equipment_delete" ON public.grow_spray_equipment
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_spray_equipment TO authenticated;

CREATE POLICY "grow_fertigation_insert" ON public.grow_fertigation
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_update" ON public.grow_fertigation
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_delete" ON public.grow_fertigation
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_fertigation TO authenticated;

CREATE POLICY "grow_fertigation_recipe_insert" ON public.grow_fertigation_recipe
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_recipe_update" ON public.grow_fertigation_recipe
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_recipe_delete" ON public.grow_fertigation_recipe
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_fertigation_recipe TO authenticated;

CREATE POLICY "grow_fertigation_recipe_site_insert" ON public.grow_fertigation_recipe_site
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_recipe_site_update" ON public.grow_fertigation_recipe_site
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_recipe_site_delete" ON public.grow_fertigation_recipe_site
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_fertigation_recipe_site TO authenticated;

CREATE POLICY "grow_fertigation_recipe_item_insert" ON public.grow_fertigation_recipe_item
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_recipe_item_update" ON public.grow_fertigation_recipe_item
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_fertigation_recipe_item_delete" ON public.grow_fertigation_recipe_item
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_fertigation_recipe_item TO authenticated;

CREATE POLICY "grow_harvest_weight_insert" ON public.grow_harvest_weight
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_harvest_weight_update" ON public.grow_harvest_weight
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_harvest_weight_delete" ON public.grow_harvest_weight
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_harvest_weight TO authenticated;

CREATE POLICY "grow_harvest_container_insert" ON public.grow_harvest_container
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_harvest_container_update" ON public.grow_harvest_container
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_harvest_container_delete" ON public.grow_harvest_container
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_harvest_container TO authenticated;

CREATE POLICY "grow_chemistry_result_insert" ON public.grow_chemistry_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_chemistry_result_update" ON public.grow_chemistry_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_chemistry_result_delete" ON public.grow_chemistry_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_chemistry_result TO authenticated;

CREATE POLICY "grow_weather_reading_insert" ON public.grow_weather_reading
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_weather_reading_update" ON public.grow_weather_reading
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_weather_reading_delete" ON public.grow_weather_reading
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_weather_reading TO authenticated;

CREATE POLICY "grow_lettuce_seed_batch_insert" ON public.grow_lettuce_seed_batch
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_lettuce_seed_batch_update" ON public.grow_lettuce_seed_batch
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_lettuce_seed_batch_delete" ON public.grow_lettuce_seed_batch
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_lettuce_seed_batch TO authenticated;

CREATE POLICY "grow_lettuce_seed_mix_insert" ON public.grow_lettuce_seed_mix
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_lettuce_seed_mix_update" ON public.grow_lettuce_seed_mix
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_lettuce_seed_mix_delete" ON public.grow_lettuce_seed_mix
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_lettuce_seed_mix TO authenticated;

CREATE POLICY "grow_lettuce_seed_mix_item_insert" ON public.grow_lettuce_seed_mix_item
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_lettuce_seed_mix_item_update" ON public.grow_lettuce_seed_mix_item
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_lettuce_seed_mix_item_delete" ON public.grow_lettuce_seed_mix_item
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_lettuce_seed_mix_item TO authenticated;

CREATE POLICY "grow_cuke_gh_row_planting_insert" ON public.grow_cuke_gh_row_planting
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_cuke_gh_row_planting_update" ON public.grow_cuke_gh_row_planting
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_cuke_gh_row_planting_delete" ON public.grow_cuke_gh_row_planting
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_cuke_gh_row_planting TO authenticated;

CREATE POLICY "grow_cuke_seed_batch_insert" ON public.grow_cuke_seed_batch
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_cuke_seed_batch_update" ON public.grow_cuke_seed_batch
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "grow_cuke_seed_batch_delete" ON public.grow_cuke_seed_batch
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.grow_cuke_seed_batch TO authenticated;


-- ===== Pack =====

CREATE POLICY "pack_lot_insert" ON public.pack_lot
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_lot_update" ON public.pack_lot
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_lot_delete" ON public.pack_lot
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_lot TO authenticated;

CREATE POLICY "pack_lot_item_insert" ON public.pack_lot_item
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_lot_item_update" ON public.pack_lot_item
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_lot_item_delete" ON public.pack_lot_item
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_lot_item TO authenticated;

CREATE POLICY "pack_productivity_hour_insert" ON public.pack_productivity_hour
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_productivity_hour_update" ON public.pack_productivity_hour
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_productivity_hour_delete" ON public.pack_productivity_hour
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_productivity_hour TO authenticated;

CREATE POLICY "pack_productivity_hour_fail_insert" ON public.pack_productivity_hour_fail
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_productivity_hour_fail_update" ON public.pack_productivity_hour_fail
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_productivity_hour_fail_delete" ON public.pack_productivity_hour_fail
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_productivity_hour_fail TO authenticated;

CREATE POLICY "pack_dryer_result_insert" ON public.pack_dryer_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_dryer_result_update" ON public.pack_dryer_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_dryer_result_delete" ON public.pack_dryer_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_dryer_result TO authenticated;

CREATE POLICY "pack_shelf_life_insert" ON public.pack_shelf_life
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_shelf_life_update" ON public.pack_shelf_life
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_shelf_life_delete" ON public.pack_shelf_life
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_shelf_life TO authenticated;

CREATE POLICY "pack_shelf_life_result_insert" ON public.pack_shelf_life_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_shelf_life_result_update" ON public.pack_shelf_life_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_shelf_life_result_delete" ON public.pack_shelf_life_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_shelf_life_result TO authenticated;

CREATE POLICY "pack_shelf_life_photo_insert" ON public.pack_shelf_life_photo
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_shelf_life_photo_update" ON public.pack_shelf_life_photo
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "pack_shelf_life_photo_delete" ON public.pack_shelf_life_photo
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.pack_shelf_life_photo TO authenticated;


-- ===== Food Safety =====

CREATE POLICY "fsafe_lab_insert" ON public.fsafe_lab
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_lab_update" ON public.fsafe_lab
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_lab_delete" ON public.fsafe_lab
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fsafe_lab TO authenticated;

CREATE POLICY "fsafe_lab_test_insert" ON public.fsafe_lab_test
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_lab_test_update" ON public.fsafe_lab_test
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_lab_test_delete" ON public.fsafe_lab_test
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fsafe_lab_test TO authenticated;

CREATE POLICY "fsafe_result_insert" ON public.fsafe_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_result_update" ON public.fsafe_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_result_delete" ON public.fsafe_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fsafe_result TO authenticated;

CREATE POLICY "fsafe_pest_result_insert" ON public.fsafe_pest_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_pest_result_update" ON public.fsafe_pest_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_pest_result_delete" ON public.fsafe_pest_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fsafe_pest_result TO authenticated;

CREATE POLICY "fsafe_test_hold_insert" ON public.fsafe_test_hold
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_test_hold_update" ON public.fsafe_test_hold
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_test_hold_delete" ON public.fsafe_test_hold
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fsafe_test_hold TO authenticated;

CREATE POLICY "fsafe_test_hold_po_insert" ON public.fsafe_test_hold_po
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_test_hold_po_update" ON public.fsafe_test_hold_po
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "fsafe_test_hold_po_delete" ON public.fsafe_test_hold_po
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.fsafe_test_hold_po TO authenticated;


-- ===== Maintenance =====

CREATE POLICY "maint_request_insert" ON public.maint_request
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "maint_request_update" ON public.maint_request
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "maint_request_delete" ON public.maint_request
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.maint_request TO authenticated;

CREATE POLICY "maint_request_invnt_item_insert" ON public.maint_request_invnt_item
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "maint_request_invnt_item_update" ON public.maint_request_invnt_item
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "maint_request_invnt_item_delete" ON public.maint_request_invnt_item
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.maint_request_invnt_item TO authenticated;

CREATE POLICY "maint_request_photo_insert" ON public.maint_request_photo
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "maint_request_photo_update" ON public.maint_request_photo
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "maint_request_photo_delete" ON public.maint_request_photo
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.maint_request_photo TO authenticated;


-- ===== Inventory =====

CREATE POLICY "invnt_po_insert" ON public.invnt_po
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_po_update" ON public.invnt_po
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_po_delete" ON public.invnt_po
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.invnt_po TO authenticated;

CREATE POLICY "invnt_po_received_insert" ON public.invnt_po_received
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_po_received_update" ON public.invnt_po_received
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_po_received_delete" ON public.invnt_po_received
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.invnt_po_received TO authenticated;

CREATE POLICY "invnt_lot_insert" ON public.invnt_lot
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_lot_update" ON public.invnt_lot
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_lot_delete" ON public.invnt_lot
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.invnt_lot TO authenticated;

CREATE POLICY "invnt_onhand_insert" ON public.invnt_onhand
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_onhand_update" ON public.invnt_onhand
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "invnt_onhand_delete" ON public.invnt_onhand
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.invnt_onhand TO authenticated;


-- ===== Sales =====

CREATE POLICY "sales_po_insert" ON public.sales_po
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_update" ON public.sales_po
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_delete" ON public.sales_po
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_po TO authenticated;

CREATE POLICY "sales_po_line_insert" ON public.sales_po_line
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_line_update" ON public.sales_po_line
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_line_delete" ON public.sales_po_line
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_po_line TO authenticated;

CREATE POLICY "sales_po_fulfillment_insert" ON public.sales_po_fulfillment
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_fulfillment_update" ON public.sales_po_fulfillment
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_fulfillment_delete" ON public.sales_po_fulfillment
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_po_fulfillment TO authenticated;

CREATE POLICY "sales_customer_insert" ON public.sales_customer
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_customer_update" ON public.sales_customer
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_customer_delete" ON public.sales_customer
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_customer TO authenticated;

CREATE POLICY "sales_customer_group_insert" ON public.sales_customer_group
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_customer_group_update" ON public.sales_customer_group
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_customer_group_delete" ON public.sales_customer_group
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_customer_group TO authenticated;

CREATE POLICY "sales_product_insert" ON public.sales_product
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_product_update" ON public.sales_product
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_product_delete" ON public.sales_product
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_product TO authenticated;

CREATE POLICY "sales_product_price_insert" ON public.sales_product_price
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_product_price_update" ON public.sales_product_price
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_product_price_delete" ON public.sales_product_price
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_product_price TO authenticated;

CREATE POLICY "sales_invoice_insert" ON public.sales_invoice
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_invoice_update" ON public.sales_invoice
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_invoice_delete" ON public.sales_invoice
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_invoice TO authenticated;

CREATE POLICY "sales_crm_external_product_insert" ON public.sales_crm_external_product
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_external_product_update" ON public.sales_crm_external_product
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_external_product_delete" ON public.sales_crm_external_product
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_crm_external_product TO authenticated;

CREATE POLICY "sales_crm_store_insert" ON public.sales_crm_store
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_update" ON public.sales_crm_store
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_delete" ON public.sales_crm_store
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_crm_store TO authenticated;

CREATE POLICY "sales_crm_store_visit_insert" ON public.sales_crm_store_visit
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_visit_update" ON public.sales_crm_store_visit
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_visit_delete" ON public.sales_crm_store_visit
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_crm_store_visit TO authenticated;

CREATE POLICY "sales_crm_store_visit_photo_insert" ON public.sales_crm_store_visit_photo
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_visit_photo_update" ON public.sales_crm_store_visit_photo
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_visit_photo_delete" ON public.sales_crm_store_visit_photo
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_crm_store_visit_photo TO authenticated;

CREATE POLICY "sales_crm_store_visit_result_insert" ON public.sales_crm_store_visit_result
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_visit_result_update" ON public.sales_crm_store_visit_result
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_crm_store_visit_result_delete" ON public.sales_crm_store_visit_result
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_crm_store_visit_result TO authenticated;

CREATE POLICY "sales_trading_partner_insert" ON public.sales_trading_partner
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_trading_partner_update" ON public.sales_trading_partner
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_trading_partner_delete" ON public.sales_trading_partner
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_trading_partner TO authenticated;

CREATE POLICY "sales_product_buyer_part_insert" ON public.sales_product_buyer_part
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_product_buyer_part_update" ON public.sales_product_buyer_part
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_product_buyer_part_delete" ON public.sales_product_buyer_part
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_product_buyer_part TO authenticated;

CREATE POLICY "sales_shipment_insert" ON public.sales_shipment
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_shipment_update" ON public.sales_shipment
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_shipment_delete" ON public.sales_shipment
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_shipment TO authenticated;

CREATE POLICY "sales_shipment_container_insert" ON public.sales_shipment_container
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_shipment_container_update" ON public.sales_shipment_container
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_shipment_container_delete" ON public.sales_shipment_container
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_shipment_container TO authenticated;

CREATE POLICY "sales_pallet_insert" ON public.sales_pallet
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_pallet_update" ON public.sales_pallet
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_pallet_delete" ON public.sales_pallet
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_pallet TO authenticated;

CREATE POLICY "sales_pallet_allocation_insert" ON public.sales_pallet_allocation
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_pallet_allocation_update" ON public.sales_pallet_allocation
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_pallet_allocation_delete" ON public.sales_pallet_allocation
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_pallet_allocation TO authenticated;

CREATE POLICY "sales_po_asn_insert" ON public.sales_po_asn
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_asn_update" ON public.sales_po_asn
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_asn_delete" ON public.sales_po_asn
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_po_asn TO authenticated;

CREATE POLICY "sales_po_asn_carton_insert" ON public.sales_po_asn_carton
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_asn_carton_update" ON public.sales_po_asn_carton
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "sales_po_asn_carton_delete" ON public.sales_po_asn_carton
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.sales_po_asn_carton TO authenticated;


-- ===== Human Resources =====

CREATE POLICY "hr_employee_insert" ON public.hr_employee
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_employee_update" ON public.hr_employee
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_employee_delete" ON public.hr_employee
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.hr_employee TO authenticated;

CREATE POLICY "hr_employee_review_insert" ON public.hr_employee_review
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_employee_review_update" ON public.hr_employee_review
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_employee_review_delete" ON public.hr_employee_review
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.hr_employee_review TO authenticated;

CREATE POLICY "hr_disciplinary_warning_insert" ON public.hr_disciplinary_warning
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_disciplinary_warning_update" ON public.hr_disciplinary_warning
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_disciplinary_warning_delete" ON public.hr_disciplinary_warning
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.hr_disciplinary_warning TO authenticated;

CREATE POLICY "hr_time_off_request_insert" ON public.hr_time_off_request
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_time_off_request_update" ON public.hr_time_off_request
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_time_off_request_delete" ON public.hr_time_off_request
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.hr_time_off_request TO authenticated;

CREATE POLICY "hr_travel_request_insert" ON public.hr_travel_request
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_travel_request_update" ON public.hr_travel_request
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_travel_request_delete" ON public.hr_travel_request
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.hr_travel_request TO authenticated;

CREATE POLICY "hr_payroll_insert" ON public.hr_payroll
  FOR INSERT TO authenticated
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_payroll_update" ON public.hr_payroll
  FOR UPDATE TO authenticated
  USING      (org_id IN (SELECT public.get_user_org_ids()))
  WITH CHECK (org_id IN (SELECT public.get_user_org_ids()));

CREATE POLICY "hr_payroll_delete" ON public.hr_payroll
  FOR DELETE TO authenticated
  USING (org_id IN (SELECT public.get_user_org_ids()));

GRANT INSERT, UPDATE, DELETE ON public.hr_payroll TO authenticated;
