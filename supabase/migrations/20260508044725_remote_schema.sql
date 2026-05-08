drop policy "edi_crodeon_weather_delete" on "public"."edi_crodeon_weather";

drop policy "edi_crodeon_weather_insert" on "public"."edi_crodeon_weather";

drop policy "edi_crodeon_weather_update" on "public"."edi_crodeon_weather";

revoke references on table "public"."edi_crodeon_weather" from "anon";

revoke trigger on table "public"."edi_crodeon_weather" from "anon";

revoke truncate on table "public"."edi_crodeon_weather" from "anon";

revoke references on table "public"."edi_crodeon_weather" from "authenticated";

revoke trigger on table "public"."edi_crodeon_weather" from "authenticated";

revoke truncate on table "public"."edi_crodeon_weather" from "authenticated";

revoke references on table "public"."edi_crodeon_weather" from "service_role";

revoke trigger on table "public"."edi_crodeon_weather" from "service_role";

revoke truncate on table "public"."edi_crodeon_weather" from "service_role";

revoke references on table "public"."edi_qb_expense" from "anon";

revoke trigger on table "public"."edi_qb_expense" from "anon";

revoke truncate on table "public"."edi_qb_expense" from "anon";

revoke references on table "public"."edi_qb_expense" from "authenticated";

revoke trigger on table "public"."edi_qb_expense" from "authenticated";

revoke truncate on table "public"."edi_qb_expense" from "authenticated";

revoke references on table "public"."edi_qb_expense" from "service_role";

revoke trigger on table "public"."edi_qb_expense" from "service_role";

revoke truncate on table "public"."edi_qb_expense" from "service_role";

revoke references on table "public"."edi_qb_expense_line" from "anon";

revoke trigger on table "public"."edi_qb_expense_line" from "anon";

revoke truncate on table "public"."edi_qb_expense_line" from "anon";

revoke references on table "public"."edi_qb_expense_line" from "authenticated";

revoke trigger on table "public"."edi_qb_expense_line" from "authenticated";

revoke truncate on table "public"."edi_qb_expense_line" from "authenticated";

revoke references on table "public"."edi_qb_expense_line" from "service_role";

revoke trigger on table "public"."edi_qb_expense_line" from "service_role";

revoke truncate on table "public"."edi_qb_expense_line" from "service_role";

revoke references on table "public"."edi_qb_invoice" from "anon";

revoke trigger on table "public"."edi_qb_invoice" from "anon";

revoke truncate on table "public"."edi_qb_invoice" from "anon";

revoke references on table "public"."edi_qb_invoice" from "authenticated";

revoke trigger on table "public"."edi_qb_invoice" from "authenticated";

revoke truncate on table "public"."edi_qb_invoice" from "authenticated";

revoke references on table "public"."edi_qb_invoice" from "service_role";

revoke trigger on table "public"."edi_qb_invoice" from "service_role";

revoke truncate on table "public"."edi_qb_invoice" from "service_role";

revoke references on table "public"."edi_qb_invoice_line" from "anon";

revoke trigger on table "public"."edi_qb_invoice_line" from "anon";

revoke truncate on table "public"."edi_qb_invoice_line" from "anon";

revoke references on table "public"."edi_qb_invoice_line" from "authenticated";

revoke trigger on table "public"."edi_qb_invoice_line" from "authenticated";

revoke truncate on table "public"."edi_qb_invoice_line" from "authenticated";

revoke references on table "public"."edi_qb_invoice_line" from "service_role";

revoke trigger on table "public"."edi_qb_invoice_line" from "service_role";

revoke truncate on table "public"."edi_qb_invoice_line" from "service_role";

revoke references on table "public"."fin_expense" from "anon";

revoke trigger on table "public"."fin_expense" from "anon";

revoke truncate on table "public"."fin_expense" from "anon";

revoke references on table "public"."fin_expense" from "authenticated";

revoke trigger on table "public"."fin_expense" from "authenticated";

revoke truncate on table "public"."fin_expense" from "authenticated";

revoke references on table "public"."fin_expense" from "service_role";

revoke trigger on table "public"."fin_expense" from "service_role";

revoke truncate on table "public"."fin_expense" from "service_role";

revoke references on table "public"."fsafe_lab" from "anon";

revoke trigger on table "public"."fsafe_lab" from "anon";

revoke truncate on table "public"."fsafe_lab" from "anon";

revoke references on table "public"."fsafe_lab" from "authenticated";

revoke trigger on table "public"."fsafe_lab" from "authenticated";

revoke truncate on table "public"."fsafe_lab" from "authenticated";

revoke references on table "public"."fsafe_lab" from "service_role";

revoke trigger on table "public"."fsafe_lab" from "service_role";

revoke truncate on table "public"."fsafe_lab" from "service_role";

revoke references on table "public"."fsafe_lab_test" from "anon";

revoke trigger on table "public"."fsafe_lab_test" from "anon";

revoke truncate on table "public"."fsafe_lab_test" from "anon";

revoke references on table "public"."fsafe_lab_test" from "authenticated";

revoke trigger on table "public"."fsafe_lab_test" from "authenticated";

revoke truncate on table "public"."fsafe_lab_test" from "authenticated";

revoke references on table "public"."fsafe_lab_test" from "service_role";

revoke trigger on table "public"."fsafe_lab_test" from "service_role";

revoke truncate on table "public"."fsafe_lab_test" from "service_role";

revoke references on table "public"."fsafe_pest_result" from "anon";

revoke trigger on table "public"."fsafe_pest_result" from "anon";

revoke truncate on table "public"."fsafe_pest_result" from "anon";

revoke references on table "public"."fsafe_pest_result" from "authenticated";

revoke trigger on table "public"."fsafe_pest_result" from "authenticated";

revoke truncate on table "public"."fsafe_pest_result" from "authenticated";

revoke references on table "public"."fsafe_pest_result" from "service_role";

revoke trigger on table "public"."fsafe_pest_result" from "service_role";

revoke truncate on table "public"."fsafe_pest_result" from "service_role";

revoke references on table "public"."fsafe_result" from "anon";

revoke trigger on table "public"."fsafe_result" from "anon";

revoke truncate on table "public"."fsafe_result" from "anon";

revoke references on table "public"."fsafe_result" from "authenticated";

revoke trigger on table "public"."fsafe_result" from "authenticated";

revoke truncate on table "public"."fsafe_result" from "authenticated";

revoke references on table "public"."fsafe_result" from "service_role";

revoke trigger on table "public"."fsafe_result" from "service_role";

revoke truncate on table "public"."fsafe_result" from "service_role";

revoke references on table "public"."fsafe_test_hold" from "anon";

revoke trigger on table "public"."fsafe_test_hold" from "anon";

revoke truncate on table "public"."fsafe_test_hold" from "anon";

revoke references on table "public"."fsafe_test_hold" from "authenticated";

revoke trigger on table "public"."fsafe_test_hold" from "authenticated";

revoke truncate on table "public"."fsafe_test_hold" from "authenticated";

revoke references on table "public"."fsafe_test_hold" from "service_role";

revoke trigger on table "public"."fsafe_test_hold" from "service_role";

revoke truncate on table "public"."fsafe_test_hold" from "service_role";

revoke references on table "public"."fsafe_test_hold_po" from "anon";

revoke trigger on table "public"."fsafe_test_hold_po" from "anon";

revoke truncate on table "public"."fsafe_test_hold_po" from "anon";

revoke references on table "public"."fsafe_test_hold_po" from "authenticated";

revoke trigger on table "public"."fsafe_test_hold_po" from "authenticated";

revoke truncate on table "public"."fsafe_test_hold_po" from "authenticated";

revoke references on table "public"."fsafe_test_hold_po" from "service_role";

revoke trigger on table "public"."fsafe_test_hold_po" from "service_role";

revoke truncate on table "public"."fsafe_test_hold_po" from "service_role";

revoke references on table "public"."grow_chemistry_result" from "anon";

revoke trigger on table "public"."grow_chemistry_result" from "anon";

revoke truncate on table "public"."grow_chemistry_result" from "anon";

revoke references on table "public"."grow_chemistry_result" from "authenticated";

revoke trigger on table "public"."grow_chemistry_result" from "authenticated";

revoke truncate on table "public"."grow_chemistry_result" from "authenticated";

revoke references on table "public"."grow_chemistry_result" from "service_role";

revoke trigger on table "public"."grow_chemistry_result" from "service_role";

revoke truncate on table "public"."grow_chemistry_result" from "service_role";

revoke references on table "public"."grow_cuke_gh_row_planting" from "anon";

revoke trigger on table "public"."grow_cuke_gh_row_planting" from "anon";

revoke truncate on table "public"."grow_cuke_gh_row_planting" from "anon";

revoke references on table "public"."grow_cuke_gh_row_planting" from "authenticated";

revoke trigger on table "public"."grow_cuke_gh_row_planting" from "authenticated";

revoke truncate on table "public"."grow_cuke_gh_row_planting" from "authenticated";

revoke references on table "public"."grow_cuke_gh_row_planting" from "service_role";

revoke trigger on table "public"."grow_cuke_gh_row_planting" from "service_role";

revoke truncate on table "public"."grow_cuke_gh_row_planting" from "service_role";

revoke references on table "public"."grow_cuke_rotation" from "anon";

revoke trigger on table "public"."grow_cuke_rotation" from "anon";

revoke truncate on table "public"."grow_cuke_rotation" from "anon";

revoke references on table "public"."grow_cuke_rotation" from "authenticated";

revoke trigger on table "public"."grow_cuke_rotation" from "authenticated";

revoke truncate on table "public"."grow_cuke_rotation" from "authenticated";

revoke references on table "public"."grow_cuke_rotation" from "service_role";

revoke trigger on table "public"."grow_cuke_rotation" from "service_role";

revoke truncate on table "public"."grow_cuke_rotation" from "service_role";

revoke references on table "public"."grow_cuke_seed_batch" from "anon";

revoke trigger on table "public"."grow_cuke_seed_batch" from "anon";

revoke truncate on table "public"."grow_cuke_seed_batch" from "anon";

revoke references on table "public"."grow_cuke_seed_batch" from "authenticated";

revoke trigger on table "public"."grow_cuke_seed_batch" from "authenticated";

revoke truncate on table "public"."grow_cuke_seed_batch" from "authenticated";

revoke references on table "public"."grow_cuke_seed_batch" from "service_role";

revoke trigger on table "public"."grow_cuke_seed_batch" from "service_role";

revoke truncate on table "public"."grow_cuke_seed_batch" from "service_role";

revoke references on table "public"."grow_cycle_pattern" from "anon";

revoke trigger on table "public"."grow_cycle_pattern" from "anon";

revoke truncate on table "public"."grow_cycle_pattern" from "anon";

revoke references on table "public"."grow_cycle_pattern" from "authenticated";

revoke trigger on table "public"."grow_cycle_pattern" from "authenticated";

revoke truncate on table "public"."grow_cycle_pattern" from "authenticated";

revoke references on table "public"."grow_cycle_pattern" from "service_role";

revoke trigger on table "public"."grow_cycle_pattern" from "service_role";

revoke truncate on table "public"."grow_cycle_pattern" from "service_role";

revoke references on table "public"."grow_disease" from "anon";

revoke trigger on table "public"."grow_disease" from "anon";

revoke truncate on table "public"."grow_disease" from "anon";

revoke references on table "public"."grow_disease" from "authenticated";

revoke trigger on table "public"."grow_disease" from "authenticated";

revoke truncate on table "public"."grow_disease" from "authenticated";

revoke references on table "public"."grow_disease" from "service_role";

revoke trigger on table "public"."grow_disease" from "service_role";

revoke truncate on table "public"."grow_disease" from "service_role";

revoke references on table "public"."grow_fertigation" from "anon";

revoke trigger on table "public"."grow_fertigation" from "anon";

revoke truncate on table "public"."grow_fertigation" from "anon";

revoke references on table "public"."grow_fertigation" from "authenticated";

revoke trigger on table "public"."grow_fertigation" from "authenticated";

revoke truncate on table "public"."grow_fertigation" from "authenticated";

revoke references on table "public"."grow_fertigation" from "service_role";

revoke trigger on table "public"."grow_fertigation" from "service_role";

revoke truncate on table "public"."grow_fertigation" from "service_role";

revoke references on table "public"."grow_fertigation_recipe" from "anon";

revoke trigger on table "public"."grow_fertigation_recipe" from "anon";

revoke truncate on table "public"."grow_fertigation_recipe" from "anon";

revoke references on table "public"."grow_fertigation_recipe" from "authenticated";

revoke trigger on table "public"."grow_fertigation_recipe" from "authenticated";

revoke truncate on table "public"."grow_fertigation_recipe" from "authenticated";

revoke references on table "public"."grow_fertigation_recipe" from "service_role";

revoke trigger on table "public"."grow_fertigation_recipe" from "service_role";

revoke truncate on table "public"."grow_fertigation_recipe" from "service_role";

revoke references on table "public"."grow_fertigation_recipe_item" from "anon";

revoke trigger on table "public"."grow_fertigation_recipe_item" from "anon";

revoke truncate on table "public"."grow_fertigation_recipe_item" from "anon";

revoke references on table "public"."grow_fertigation_recipe_item" from "authenticated";

revoke trigger on table "public"."grow_fertigation_recipe_item" from "authenticated";

revoke truncate on table "public"."grow_fertigation_recipe_item" from "authenticated";

revoke references on table "public"."grow_fertigation_recipe_item" from "service_role";

revoke trigger on table "public"."grow_fertigation_recipe_item" from "service_role";

revoke truncate on table "public"."grow_fertigation_recipe_item" from "service_role";

revoke references on table "public"."grow_fertigation_recipe_site" from "anon";

revoke trigger on table "public"."grow_fertigation_recipe_site" from "anon";

revoke truncate on table "public"."grow_fertigation_recipe_site" from "anon";

revoke references on table "public"."grow_fertigation_recipe_site" from "authenticated";

revoke trigger on table "public"."grow_fertigation_recipe_site" from "authenticated";

revoke truncate on table "public"."grow_fertigation_recipe_site" from "authenticated";

revoke references on table "public"."grow_fertigation_recipe_site" from "service_role";

revoke trigger on table "public"."grow_fertigation_recipe_site" from "service_role";

revoke truncate on table "public"."grow_fertigation_recipe_site" from "service_role";

revoke references on table "public"."grow_grade" from "anon";

revoke trigger on table "public"."grow_grade" from "anon";

revoke truncate on table "public"."grow_grade" from "anon";

revoke references on table "public"."grow_grade" from "authenticated";

revoke trigger on table "public"."grow_grade" from "authenticated";

revoke truncate on table "public"."grow_grade" from "authenticated";

revoke references on table "public"."grow_grade" from "service_role";

revoke trigger on table "public"."grow_grade" from "service_role";

revoke truncate on table "public"."grow_grade" from "service_role";

revoke references on table "public"."grow_harvest_container" from "anon";

revoke trigger on table "public"."grow_harvest_container" from "anon";

revoke truncate on table "public"."grow_harvest_container" from "anon";

revoke references on table "public"."grow_harvest_container" from "authenticated";

revoke trigger on table "public"."grow_harvest_container" from "authenticated";

revoke truncate on table "public"."grow_harvest_container" from "authenticated";

revoke references on table "public"."grow_harvest_container" from "service_role";

revoke trigger on table "public"."grow_harvest_container" from "service_role";

revoke truncate on table "public"."grow_harvest_container" from "service_role";

revoke references on table "public"."grow_harvest_weight" from "anon";

revoke trigger on table "public"."grow_harvest_weight" from "anon";

revoke truncate on table "public"."grow_harvest_weight" from "anon";

revoke references on table "public"."grow_harvest_weight" from "authenticated";

revoke trigger on table "public"."grow_harvest_weight" from "authenticated";

revoke truncate on table "public"."grow_harvest_weight" from "authenticated";

revoke references on table "public"."grow_harvest_weight" from "service_role";

revoke trigger on table "public"."grow_harvest_weight" from "service_role";

revoke truncate on table "public"."grow_harvest_weight" from "service_role";

revoke references on table "public"."grow_lettuce_seed_batch" from "anon";

revoke trigger on table "public"."grow_lettuce_seed_batch" from "anon";

revoke truncate on table "public"."grow_lettuce_seed_batch" from "anon";

revoke references on table "public"."grow_lettuce_seed_batch" from "authenticated";

revoke trigger on table "public"."grow_lettuce_seed_batch" from "authenticated";

revoke truncate on table "public"."grow_lettuce_seed_batch" from "authenticated";

revoke references on table "public"."grow_lettuce_seed_batch" from "service_role";

revoke trigger on table "public"."grow_lettuce_seed_batch" from "service_role";

revoke truncate on table "public"."grow_lettuce_seed_batch" from "service_role";

revoke references on table "public"."grow_lettuce_seed_mix" from "anon";

revoke trigger on table "public"."grow_lettuce_seed_mix" from "anon";

revoke truncate on table "public"."grow_lettuce_seed_mix" from "anon";

revoke references on table "public"."grow_lettuce_seed_mix" from "authenticated";

revoke trigger on table "public"."grow_lettuce_seed_mix" from "authenticated";

revoke truncate on table "public"."grow_lettuce_seed_mix" from "authenticated";

revoke references on table "public"."grow_lettuce_seed_mix" from "service_role";

revoke trigger on table "public"."grow_lettuce_seed_mix" from "service_role";

revoke truncate on table "public"."grow_lettuce_seed_mix" from "service_role";

revoke references on table "public"."grow_lettuce_seed_mix_item" from "anon";

revoke trigger on table "public"."grow_lettuce_seed_mix_item" from "anon";

revoke truncate on table "public"."grow_lettuce_seed_mix_item" from "anon";

revoke references on table "public"."grow_lettuce_seed_mix_item" from "authenticated";

revoke trigger on table "public"."grow_lettuce_seed_mix_item" from "authenticated";

revoke truncate on table "public"."grow_lettuce_seed_mix_item" from "authenticated";

revoke references on table "public"."grow_lettuce_seed_mix_item" from "service_role";

revoke trigger on table "public"."grow_lettuce_seed_mix_item" from "service_role";

revoke truncate on table "public"."grow_lettuce_seed_mix_item" from "service_role";

revoke references on table "public"."grow_monitoring_metric" from "anon";

revoke trigger on table "public"."grow_monitoring_metric" from "anon";

revoke truncate on table "public"."grow_monitoring_metric" from "anon";

revoke references on table "public"."grow_monitoring_metric" from "authenticated";

revoke trigger on table "public"."grow_monitoring_metric" from "authenticated";

revoke truncate on table "public"."grow_monitoring_metric" from "authenticated";

revoke references on table "public"."grow_monitoring_metric" from "service_role";

revoke trigger on table "public"."grow_monitoring_metric" from "service_role";

revoke truncate on table "public"."grow_monitoring_metric" from "service_role";

revoke references on table "public"."grow_monitoring_result" from "anon";

revoke trigger on table "public"."grow_monitoring_result" from "anon";

revoke truncate on table "public"."grow_monitoring_result" from "anon";

revoke references on table "public"."grow_monitoring_result" from "authenticated";

revoke trigger on table "public"."grow_monitoring_result" from "authenticated";

revoke truncate on table "public"."grow_monitoring_result" from "authenticated";

revoke references on table "public"."grow_monitoring_result" from "service_role";

revoke trigger on table "public"."grow_monitoring_result" from "service_role";

revoke truncate on table "public"."grow_monitoring_result" from "service_role";

revoke references on table "public"."grow_pest" from "anon";

revoke trigger on table "public"."grow_pest" from "anon";

revoke truncate on table "public"."grow_pest" from "anon";

revoke references on table "public"."grow_pest" from "authenticated";

revoke trigger on table "public"."grow_pest" from "authenticated";

revoke truncate on table "public"."grow_pest" from "authenticated";

revoke references on table "public"."grow_pest" from "service_role";

revoke trigger on table "public"."grow_pest" from "service_role";

revoke truncate on table "public"."grow_pest" from "service_role";

revoke references on table "public"."grow_scout_result" from "anon";

revoke trigger on table "public"."grow_scout_result" from "anon";

revoke truncate on table "public"."grow_scout_result" from "anon";

revoke references on table "public"."grow_scout_result" from "authenticated";

revoke trigger on table "public"."grow_scout_result" from "authenticated";

revoke truncate on table "public"."grow_scout_result" from "authenticated";

revoke references on table "public"."grow_scout_result" from "service_role";

revoke trigger on table "public"."grow_scout_result" from "service_role";

revoke truncate on table "public"."grow_scout_result" from "service_role";

revoke references on table "public"."grow_spray_compliance" from "anon";

revoke trigger on table "public"."grow_spray_compliance" from "anon";

revoke truncate on table "public"."grow_spray_compliance" from "anon";

revoke references on table "public"."grow_spray_compliance" from "authenticated";

revoke trigger on table "public"."grow_spray_compliance" from "authenticated";

revoke truncate on table "public"."grow_spray_compliance" from "authenticated";

revoke references on table "public"."grow_spray_compliance" from "service_role";

revoke trigger on table "public"."grow_spray_compliance" from "service_role";

revoke truncate on table "public"."grow_spray_compliance" from "service_role";

revoke references on table "public"."grow_spray_equipment" from "anon";

revoke trigger on table "public"."grow_spray_equipment" from "anon";

revoke truncate on table "public"."grow_spray_equipment" from "anon";

revoke references on table "public"."grow_spray_equipment" from "authenticated";

revoke trigger on table "public"."grow_spray_equipment" from "authenticated";

revoke truncate on table "public"."grow_spray_equipment" from "authenticated";

revoke references on table "public"."grow_spray_equipment" from "service_role";

revoke trigger on table "public"."grow_spray_equipment" from "service_role";

revoke truncate on table "public"."grow_spray_equipment" from "service_role";

revoke references on table "public"."grow_spray_input" from "anon";

revoke trigger on table "public"."grow_spray_input" from "anon";

revoke truncate on table "public"."grow_spray_input" from "anon";

revoke references on table "public"."grow_spray_input" from "authenticated";

revoke trigger on table "public"."grow_spray_input" from "authenticated";

revoke truncate on table "public"."grow_spray_input" from "authenticated";

revoke references on table "public"."grow_spray_input" from "service_role";

revoke trigger on table "public"."grow_spray_input" from "service_role";

revoke truncate on table "public"."grow_spray_input" from "service_role";

revoke references on table "public"."grow_task_photo" from "anon";

revoke trigger on table "public"."grow_task_photo" from "anon";

revoke truncate on table "public"."grow_task_photo" from "anon";

revoke references on table "public"."grow_task_photo" from "authenticated";

revoke trigger on table "public"."grow_task_photo" from "authenticated";

revoke truncate on table "public"."grow_task_photo" from "authenticated";

revoke references on table "public"."grow_task_photo" from "service_role";

revoke trigger on table "public"."grow_task_photo" from "service_role";

revoke truncate on table "public"."grow_task_photo" from "service_role";

revoke references on table "public"."grow_task_seed_batch" from "anon";

revoke trigger on table "public"."grow_task_seed_batch" from "anon";

revoke truncate on table "public"."grow_task_seed_batch" from "anon";

revoke references on table "public"."grow_task_seed_batch" from "authenticated";

revoke trigger on table "public"."grow_task_seed_batch" from "authenticated";

revoke truncate on table "public"."grow_task_seed_batch" from "authenticated";

revoke references on table "public"."grow_task_seed_batch" from "service_role";

revoke trigger on table "public"."grow_task_seed_batch" from "service_role";

revoke truncate on table "public"."grow_task_seed_batch" from "service_role";

revoke references on table "public"."grow_trial_type" from "anon";

revoke trigger on table "public"."grow_trial_type" from "anon";

revoke truncate on table "public"."grow_trial_type" from "anon";

revoke references on table "public"."grow_trial_type" from "authenticated";

revoke trigger on table "public"."grow_trial_type" from "authenticated";

revoke truncate on table "public"."grow_trial_type" from "authenticated";

revoke references on table "public"."grow_trial_type" from "service_role";

revoke trigger on table "public"."grow_trial_type" from "service_role";

revoke truncate on table "public"."grow_trial_type" from "service_role";

revoke references on table "public"."grow_variety" from "anon";

revoke trigger on table "public"."grow_variety" from "anon";

revoke truncate on table "public"."grow_variety" from "anon";

revoke references on table "public"."grow_variety" from "authenticated";

revoke trigger on table "public"."grow_variety" from "authenticated";

revoke truncate on table "public"."grow_variety" from "authenticated";

revoke references on table "public"."grow_variety" from "service_role";

revoke trigger on table "public"."grow_variety" from "service_role";

revoke truncate on table "public"."grow_variety" from "service_role";

revoke references on table "public"."hr_department" from "anon";

revoke trigger on table "public"."hr_department" from "anon";

revoke truncate on table "public"."hr_department" from "anon";

revoke references on table "public"."hr_department" from "authenticated";

revoke trigger on table "public"."hr_department" from "authenticated";

revoke truncate on table "public"."hr_department" from "authenticated";

revoke references on table "public"."hr_department" from "service_role";

revoke trigger on table "public"."hr_department" from "service_role";

revoke truncate on table "public"."hr_department" from "service_role";

revoke references on table "public"."hr_disciplinary_warning" from "anon";

revoke trigger on table "public"."hr_disciplinary_warning" from "anon";

revoke truncate on table "public"."hr_disciplinary_warning" from "anon";

revoke references on table "public"."hr_disciplinary_warning" from "authenticated";

revoke trigger on table "public"."hr_disciplinary_warning" from "authenticated";

revoke truncate on table "public"."hr_disciplinary_warning" from "authenticated";

revoke references on table "public"."hr_disciplinary_warning" from "service_role";

revoke trigger on table "public"."hr_disciplinary_warning" from "service_role";

revoke truncate on table "public"."hr_disciplinary_warning" from "service_role";

revoke references on table "public"."hr_employee" from "anon";

revoke trigger on table "public"."hr_employee" from "anon";

revoke truncate on table "public"."hr_employee" from "anon";

revoke references on table "public"."hr_employee" from "authenticated";

revoke trigger on table "public"."hr_employee" from "authenticated";

revoke truncate on table "public"."hr_employee" from "authenticated";

revoke references on table "public"."hr_employee" from "service_role";

revoke trigger on table "public"."hr_employee" from "service_role";

revoke truncate on table "public"."hr_employee" from "service_role";

revoke references on table "public"."hr_employee_review" from "anon";

revoke trigger on table "public"."hr_employee_review" from "anon";

revoke truncate on table "public"."hr_employee_review" from "anon";

revoke references on table "public"."hr_employee_review" from "authenticated";

revoke trigger on table "public"."hr_employee_review" from "authenticated";

revoke truncate on table "public"."hr_employee_review" from "authenticated";

revoke references on table "public"."hr_employee_review" from "service_role";

revoke trigger on table "public"."hr_employee_review" from "service_role";

revoke truncate on table "public"."hr_employee_review" from "service_role";

revoke references on table "public"."hr_module_access" from "anon";

revoke trigger on table "public"."hr_module_access" from "anon";

revoke truncate on table "public"."hr_module_access" from "anon";

revoke references on table "public"."hr_module_access" from "authenticated";

revoke trigger on table "public"."hr_module_access" from "authenticated";

revoke truncate on table "public"."hr_module_access" from "authenticated";

revoke references on table "public"."hr_module_access" from "service_role";

revoke trigger on table "public"."hr_module_access" from "service_role";

revoke truncate on table "public"."hr_module_access" from "service_role";

revoke references on table "public"."hr_payroll" from "anon";

revoke trigger on table "public"."hr_payroll" from "anon";

revoke truncate on table "public"."hr_payroll" from "anon";

revoke references on table "public"."hr_payroll" from "authenticated";

revoke trigger on table "public"."hr_payroll" from "authenticated";

revoke truncate on table "public"."hr_payroll" from "authenticated";

revoke references on table "public"."hr_payroll" from "service_role";

revoke trigger on table "public"."hr_payroll" from "service_role";

revoke truncate on table "public"."hr_payroll" from "service_role";

revoke references on table "public"."hr_time_off_request" from "anon";

revoke trigger on table "public"."hr_time_off_request" from "anon";

revoke truncate on table "public"."hr_time_off_request" from "anon";

revoke references on table "public"."hr_time_off_request" from "authenticated";

revoke trigger on table "public"."hr_time_off_request" from "authenticated";

revoke truncate on table "public"."hr_time_off_request" from "authenticated";

revoke references on table "public"."hr_time_off_request" from "service_role";

revoke trigger on table "public"."hr_time_off_request" from "service_role";

revoke truncate on table "public"."hr_time_off_request" from "service_role";

revoke references on table "public"."hr_travel_request" from "anon";

revoke trigger on table "public"."hr_travel_request" from "anon";

revoke truncate on table "public"."hr_travel_request" from "anon";

revoke references on table "public"."hr_travel_request" from "authenticated";

revoke trigger on table "public"."hr_travel_request" from "authenticated";

revoke truncate on table "public"."hr_travel_request" from "authenticated";

revoke references on table "public"."hr_travel_request" from "service_role";

revoke trigger on table "public"."hr_travel_request" from "service_role";

revoke truncate on table "public"."hr_travel_request" from "service_role";

revoke references on table "public"."hr_work_authorization" from "anon";

revoke trigger on table "public"."hr_work_authorization" from "anon";

revoke truncate on table "public"."hr_work_authorization" from "anon";

revoke references on table "public"."hr_work_authorization" from "authenticated";

revoke trigger on table "public"."hr_work_authorization" from "authenticated";

revoke truncate on table "public"."hr_work_authorization" from "authenticated";

revoke references on table "public"."hr_work_authorization" from "service_role";

revoke trigger on table "public"."hr_work_authorization" from "service_role";

revoke truncate on table "public"."hr_work_authorization" from "service_role";

revoke references on table "public"."invnt_category" from "anon";

revoke trigger on table "public"."invnt_category" from "anon";

revoke truncate on table "public"."invnt_category" from "anon";

revoke references on table "public"."invnt_category" from "authenticated";

revoke trigger on table "public"."invnt_category" from "authenticated";

revoke truncate on table "public"."invnt_category" from "authenticated";

revoke references on table "public"."invnt_category" from "service_role";

revoke trigger on table "public"."invnt_category" from "service_role";

revoke truncate on table "public"."invnt_category" from "service_role";

revoke references on table "public"."invnt_item" from "anon";

revoke trigger on table "public"."invnt_item" from "anon";

revoke truncate on table "public"."invnt_item" from "anon";

revoke references on table "public"."invnt_item" from "authenticated";

revoke trigger on table "public"."invnt_item" from "authenticated";

revoke truncate on table "public"."invnt_item" from "authenticated";

revoke references on table "public"."invnt_item" from "service_role";

revoke trigger on table "public"."invnt_item" from "service_role";

revoke truncate on table "public"."invnt_item" from "service_role";

revoke references on table "public"."invnt_lot" from "anon";

revoke trigger on table "public"."invnt_lot" from "anon";

revoke truncate on table "public"."invnt_lot" from "anon";

revoke references on table "public"."invnt_lot" from "authenticated";

revoke trigger on table "public"."invnt_lot" from "authenticated";

revoke truncate on table "public"."invnt_lot" from "authenticated";

revoke references on table "public"."invnt_lot" from "service_role";

revoke trigger on table "public"."invnt_lot" from "service_role";

revoke truncate on table "public"."invnt_lot" from "service_role";

revoke references on table "public"."invnt_onhand" from "anon";

revoke trigger on table "public"."invnt_onhand" from "anon";

revoke truncate on table "public"."invnt_onhand" from "anon";

revoke references on table "public"."invnt_onhand" from "authenticated";

revoke trigger on table "public"."invnt_onhand" from "authenticated";

revoke truncate on table "public"."invnt_onhand" from "authenticated";

revoke references on table "public"."invnt_onhand" from "service_role";

revoke trigger on table "public"."invnt_onhand" from "service_role";

revoke truncate on table "public"."invnt_onhand" from "service_role";

revoke references on table "public"."invnt_po" from "anon";

revoke trigger on table "public"."invnt_po" from "anon";

revoke truncate on table "public"."invnt_po" from "anon";

revoke references on table "public"."invnt_po" from "authenticated";

revoke trigger on table "public"."invnt_po" from "authenticated";

revoke truncate on table "public"."invnt_po" from "authenticated";

revoke references on table "public"."invnt_po" from "service_role";

revoke trigger on table "public"."invnt_po" from "service_role";

revoke truncate on table "public"."invnt_po" from "service_role";

revoke references on table "public"."invnt_po_received" from "anon";

revoke trigger on table "public"."invnt_po_received" from "anon";

revoke truncate on table "public"."invnt_po_received" from "anon";

revoke references on table "public"."invnt_po_received" from "authenticated";

revoke trigger on table "public"."invnt_po_received" from "authenticated";

revoke truncate on table "public"."invnt_po_received" from "authenticated";

revoke references on table "public"."invnt_po_received" from "service_role";

revoke trigger on table "public"."invnt_po_received" from "service_role";

revoke truncate on table "public"."invnt_po_received" from "service_role";

revoke references on table "public"."invnt_vendor" from "anon";

revoke trigger on table "public"."invnt_vendor" from "anon";

revoke truncate on table "public"."invnt_vendor" from "anon";

revoke references on table "public"."invnt_vendor" from "authenticated";

revoke trigger on table "public"."invnt_vendor" from "authenticated";

revoke truncate on table "public"."invnt_vendor" from "authenticated";

revoke references on table "public"."invnt_vendor" from "service_role";

revoke trigger on table "public"."invnt_vendor" from "service_role";

revoke truncate on table "public"."invnt_vendor" from "service_role";

revoke references on table "public"."maint_request" from "anon";

revoke trigger on table "public"."maint_request" from "anon";

revoke truncate on table "public"."maint_request" from "anon";

revoke references on table "public"."maint_request" from "authenticated";

revoke trigger on table "public"."maint_request" from "authenticated";

revoke truncate on table "public"."maint_request" from "authenticated";

revoke references on table "public"."maint_request" from "service_role";

revoke trigger on table "public"."maint_request" from "service_role";

revoke truncate on table "public"."maint_request" from "service_role";

revoke references on table "public"."maint_request_invnt_item" from "anon";

revoke trigger on table "public"."maint_request_invnt_item" from "anon";

revoke truncate on table "public"."maint_request_invnt_item" from "anon";

revoke references on table "public"."maint_request_invnt_item" from "authenticated";

revoke trigger on table "public"."maint_request_invnt_item" from "authenticated";

revoke truncate on table "public"."maint_request_invnt_item" from "authenticated";

revoke references on table "public"."maint_request_invnt_item" from "service_role";

revoke trigger on table "public"."maint_request_invnt_item" from "service_role";

revoke truncate on table "public"."maint_request_invnt_item" from "service_role";

revoke references on table "public"."maint_request_photo" from "anon";

revoke trigger on table "public"."maint_request_photo" from "anon";

revoke truncate on table "public"."maint_request_photo" from "anon";

revoke references on table "public"."maint_request_photo" from "authenticated";

revoke trigger on table "public"."maint_request_photo" from "authenticated";

revoke truncate on table "public"."maint_request_photo" from "authenticated";

revoke references on table "public"."maint_request_photo" from "service_role";

revoke trigger on table "public"."maint_request_photo" from "service_role";

revoke truncate on table "public"."maint_request_photo" from "service_role";

revoke references on table "public"."ops_corrective_action_choice" from "anon";

revoke trigger on table "public"."ops_corrective_action_choice" from "anon";

revoke truncate on table "public"."ops_corrective_action_choice" from "anon";

revoke references on table "public"."ops_corrective_action_choice" from "authenticated";

revoke trigger on table "public"."ops_corrective_action_choice" from "authenticated";

revoke truncate on table "public"."ops_corrective_action_choice" from "authenticated";

revoke references on table "public"."ops_corrective_action_choice" from "service_role";

revoke trigger on table "public"."ops_corrective_action_choice" from "service_role";

revoke truncate on table "public"."ops_corrective_action_choice" from "service_role";

revoke references on table "public"."ops_corrective_action_taken" from "anon";

revoke trigger on table "public"."ops_corrective_action_taken" from "anon";

revoke truncate on table "public"."ops_corrective_action_taken" from "anon";

revoke references on table "public"."ops_corrective_action_taken" from "authenticated";

revoke trigger on table "public"."ops_corrective_action_taken" from "authenticated";

revoke truncate on table "public"."ops_corrective_action_taken" from "authenticated";

revoke references on table "public"."ops_corrective_action_taken" from "service_role";

revoke trigger on table "public"."ops_corrective_action_taken" from "service_role";

revoke truncate on table "public"."ops_corrective_action_taken" from "service_role";

revoke references on table "public"."ops_task" from "anon";

revoke trigger on table "public"."ops_task" from "anon";

revoke truncate on table "public"."ops_task" from "anon";

revoke references on table "public"."ops_task" from "authenticated";

revoke trigger on table "public"."ops_task" from "authenticated";

revoke truncate on table "public"."ops_task" from "authenticated";

revoke references on table "public"."ops_task" from "service_role";

revoke trigger on table "public"."ops_task" from "service_role";

revoke truncate on table "public"."ops_task" from "service_role";

revoke references on table "public"."ops_task_schedule" from "anon";

revoke trigger on table "public"."ops_task_schedule" from "anon";

revoke truncate on table "public"."ops_task_schedule" from "anon";

revoke references on table "public"."ops_task_schedule" from "authenticated";

revoke trigger on table "public"."ops_task_schedule" from "authenticated";

revoke truncate on table "public"."ops_task_schedule" from "authenticated";

revoke references on table "public"."ops_task_schedule" from "service_role";

revoke trigger on table "public"."ops_task_schedule" from "service_role";

revoke truncate on table "public"."ops_task_schedule" from "service_role";

revoke references on table "public"."ops_task_template" from "anon";

revoke trigger on table "public"."ops_task_template" from "anon";

revoke truncate on table "public"."ops_task_template" from "anon";

revoke references on table "public"."ops_task_template" from "authenticated";

revoke trigger on table "public"."ops_task_template" from "authenticated";

revoke truncate on table "public"."ops_task_template" from "authenticated";

revoke references on table "public"."ops_task_template" from "service_role";

revoke trigger on table "public"."ops_task_template" from "service_role";

revoke truncate on table "public"."ops_task_template" from "service_role";

revoke references on table "public"."ops_task_tracker" from "anon";

revoke trigger on table "public"."ops_task_tracker" from "anon";

revoke truncate on table "public"."ops_task_tracker" from "anon";

revoke references on table "public"."ops_task_tracker" from "authenticated";

revoke trigger on table "public"."ops_task_tracker" from "authenticated";

revoke truncate on table "public"."ops_task_tracker" from "authenticated";

revoke references on table "public"."ops_task_tracker" from "service_role";

revoke trigger on table "public"."ops_task_tracker" from "service_role";

revoke truncate on table "public"."ops_task_tracker" from "service_role";

revoke references on table "public"."ops_template" from "anon";

revoke trigger on table "public"."ops_template" from "anon";

revoke truncate on table "public"."ops_template" from "anon";

revoke references on table "public"."ops_template" from "authenticated";

revoke trigger on table "public"."ops_template" from "authenticated";

revoke truncate on table "public"."ops_template" from "authenticated";

revoke references on table "public"."ops_template" from "service_role";

revoke trigger on table "public"."ops_template" from "service_role";

revoke truncate on table "public"."ops_template" from "service_role";

revoke references on table "public"."ops_template_question" from "anon";

revoke trigger on table "public"."ops_template_question" from "anon";

revoke truncate on table "public"."ops_template_question" from "anon";

revoke references on table "public"."ops_template_question" from "authenticated";

revoke trigger on table "public"."ops_template_question" from "authenticated";

revoke truncate on table "public"."ops_template_question" from "authenticated";

revoke references on table "public"."ops_template_question" from "service_role";

revoke trigger on table "public"."ops_template_question" from "service_role";

revoke truncate on table "public"."ops_template_question" from "service_role";

revoke references on table "public"."ops_template_result" from "anon";

revoke trigger on table "public"."ops_template_result" from "anon";

revoke truncate on table "public"."ops_template_result" from "anon";

revoke references on table "public"."ops_template_result" from "authenticated";

revoke trigger on table "public"."ops_template_result" from "authenticated";

revoke truncate on table "public"."ops_template_result" from "authenticated";

revoke references on table "public"."ops_template_result" from "service_role";

revoke trigger on table "public"."ops_template_result" from "service_role";

revoke truncate on table "public"."ops_template_result" from "service_role";

revoke references on table "public"."ops_template_result_photo" from "anon";

revoke trigger on table "public"."ops_template_result_photo" from "anon";

revoke truncate on table "public"."ops_template_result_photo" from "anon";

revoke references on table "public"."ops_template_result_photo" from "authenticated";

revoke trigger on table "public"."ops_template_result_photo" from "authenticated";

revoke truncate on table "public"."ops_template_result_photo" from "authenticated";

revoke references on table "public"."ops_template_result_photo" from "service_role";

revoke trigger on table "public"."ops_template_result_photo" from "service_role";

revoke truncate on table "public"."ops_template_result_photo" from "service_role";

revoke references on table "public"."ops_training" from "anon";

revoke trigger on table "public"."ops_training" from "anon";

revoke truncate on table "public"."ops_training" from "anon";

revoke references on table "public"."ops_training" from "authenticated";

revoke trigger on table "public"."ops_training" from "authenticated";

revoke truncate on table "public"."ops_training" from "authenticated";

revoke references on table "public"."ops_training" from "service_role";

revoke trigger on table "public"."ops_training" from "service_role";

revoke truncate on table "public"."ops_training" from "service_role";

revoke references on table "public"."ops_training_attendee" from "anon";

revoke trigger on table "public"."ops_training_attendee" from "anon";

revoke truncate on table "public"."ops_training_attendee" from "anon";

revoke references on table "public"."ops_training_attendee" from "authenticated";

revoke trigger on table "public"."ops_training_attendee" from "authenticated";

revoke truncate on table "public"."ops_training_attendee" from "authenticated";

revoke references on table "public"."ops_training_attendee" from "service_role";

revoke trigger on table "public"."ops_training_attendee" from "service_role";

revoke truncate on table "public"."ops_training_attendee" from "service_role";

revoke references on table "public"."ops_training_type" from "anon";

revoke trigger on table "public"."ops_training_type" from "anon";

revoke truncate on table "public"."ops_training_type" from "anon";

revoke references on table "public"."ops_training_type" from "authenticated";

revoke trigger on table "public"."ops_training_type" from "authenticated";

revoke truncate on table "public"."ops_training_type" from "authenticated";

revoke references on table "public"."ops_training_type" from "service_role";

revoke trigger on table "public"."ops_training_type" from "service_role";

revoke truncate on table "public"."ops_training_type" from "service_role";

revoke references on table "public"."org" from "anon";

revoke trigger on table "public"."org" from "anon";

revoke truncate on table "public"."org" from "anon";

revoke references on table "public"."org" from "authenticated";

revoke trigger on table "public"."org" from "authenticated";

revoke truncate on table "public"."org" from "authenticated";

revoke references on table "public"."org" from "service_role";

revoke trigger on table "public"."org" from "service_role";

revoke truncate on table "public"."org" from "service_role";

revoke references on table "public"."org_business_rule" from "anon";

revoke trigger on table "public"."org_business_rule" from "anon";

revoke truncate on table "public"."org_business_rule" from "anon";

revoke references on table "public"."org_business_rule" from "authenticated";

revoke trigger on table "public"."org_business_rule" from "authenticated";

revoke truncate on table "public"."org_business_rule" from "authenticated";

revoke references on table "public"."org_business_rule" from "service_role";

revoke trigger on table "public"."org_business_rule" from "service_role";

revoke truncate on table "public"."org_business_rule" from "service_role";

revoke references on table "public"."org_equipment" from "anon";

revoke trigger on table "public"."org_equipment" from "anon";

revoke truncate on table "public"."org_equipment" from "anon";

revoke references on table "public"."org_equipment" from "authenticated";

revoke trigger on table "public"."org_equipment" from "authenticated";

revoke truncate on table "public"."org_equipment" from "authenticated";

revoke references on table "public"."org_equipment" from "service_role";

revoke trigger on table "public"."org_equipment" from "service_role";

revoke truncate on table "public"."org_equipment" from "service_role";

revoke references on table "public"."org_farm" from "anon";

revoke trigger on table "public"."org_farm" from "anon";

revoke truncate on table "public"."org_farm" from "anon";

revoke references on table "public"."org_farm" from "authenticated";

revoke trigger on table "public"."org_farm" from "authenticated";

revoke truncate on table "public"."org_farm" from "authenticated";

revoke references on table "public"."org_farm" from "service_role";

revoke trigger on table "public"."org_farm" from "service_role";

revoke truncate on table "public"."org_farm" from "service_role";

revoke references on table "public"."org_module" from "anon";

revoke trigger on table "public"."org_module" from "anon";

revoke truncate on table "public"."org_module" from "anon";

revoke references on table "public"."org_module" from "authenticated";

revoke trigger on table "public"."org_module" from "authenticated";

revoke truncate on table "public"."org_module" from "authenticated";

revoke references on table "public"."org_module" from "service_role";

revoke trigger on table "public"."org_module" from "service_role";

revoke truncate on table "public"."org_module" from "service_role";

revoke references on table "public"."org_quickbooks_token" from "service_role";

revoke trigger on table "public"."org_quickbooks_token" from "service_role";

revoke truncate on table "public"."org_quickbooks_token" from "service_role";

revoke references on table "public"."org_site" from "anon";

revoke trigger on table "public"."org_site" from "anon";

revoke truncate on table "public"."org_site" from "anon";

revoke references on table "public"."org_site" from "authenticated";

revoke trigger on table "public"."org_site" from "authenticated";

revoke truncate on table "public"."org_site" from "authenticated";

revoke references on table "public"."org_site" from "service_role";

revoke trigger on table "public"."org_site" from "service_role";

revoke truncate on table "public"."org_site" from "service_role";

revoke references on table "public"."org_site_category" from "anon";

revoke trigger on table "public"."org_site_category" from "anon";

revoke truncate on table "public"."org_site_category" from "anon";

revoke references on table "public"."org_site_category" from "authenticated";

revoke trigger on table "public"."org_site_category" from "authenticated";

revoke truncate on table "public"."org_site_category" from "authenticated";

revoke references on table "public"."org_site_category" from "service_role";

revoke trigger on table "public"."org_site_category" from "service_role";

revoke truncate on table "public"."org_site_category" from "service_role";

revoke references on table "public"."org_site_cuke_gh" from "anon";

revoke trigger on table "public"."org_site_cuke_gh" from "anon";

revoke truncate on table "public"."org_site_cuke_gh" from "anon";

revoke references on table "public"."org_site_cuke_gh" from "authenticated";

revoke trigger on table "public"."org_site_cuke_gh" from "authenticated";

revoke truncate on table "public"."org_site_cuke_gh" from "authenticated";

revoke references on table "public"."org_site_cuke_gh" from "service_role";

revoke trigger on table "public"."org_site_cuke_gh" from "service_role";

revoke truncate on table "public"."org_site_cuke_gh" from "service_role";

revoke references on table "public"."org_site_cuke_gh_block" from "anon";

revoke trigger on table "public"."org_site_cuke_gh_block" from "anon";

revoke truncate on table "public"."org_site_cuke_gh_block" from "anon";

revoke references on table "public"."org_site_cuke_gh_block" from "authenticated";

revoke trigger on table "public"."org_site_cuke_gh_block" from "authenticated";

revoke truncate on table "public"."org_site_cuke_gh_block" from "authenticated";

revoke references on table "public"."org_site_cuke_gh_block" from "service_role";

revoke trigger on table "public"."org_site_cuke_gh_block" from "service_role";

revoke truncate on table "public"."org_site_cuke_gh_block" from "service_role";

revoke references on table "public"."org_site_cuke_gh_row" from "anon";

revoke trigger on table "public"."org_site_cuke_gh_row" from "anon";

revoke truncate on table "public"."org_site_cuke_gh_row" from "anon";

revoke references on table "public"."org_site_cuke_gh_row" from "authenticated";

revoke trigger on table "public"."org_site_cuke_gh_row" from "authenticated";

revoke truncate on table "public"."org_site_cuke_gh_row" from "authenticated";

revoke references on table "public"."org_site_cuke_gh_row" from "service_role";

revoke trigger on table "public"."org_site_cuke_gh_row" from "service_role";

revoke truncate on table "public"."org_site_cuke_gh_row" from "service_role";

revoke references on table "public"."org_site_housing" from "anon";

revoke trigger on table "public"."org_site_housing" from "anon";

revoke truncate on table "public"."org_site_housing" from "anon";

revoke references on table "public"."org_site_housing" from "authenticated";

revoke trigger on table "public"."org_site_housing" from "authenticated";

revoke truncate on table "public"."org_site_housing" from "authenticated";

revoke references on table "public"."org_site_housing" from "service_role";

revoke trigger on table "public"."org_site_housing" from "service_role";

revoke truncate on table "public"."org_site_housing" from "service_role";

revoke references on table "public"."org_site_housing_area" from "anon";

revoke trigger on table "public"."org_site_housing_area" from "anon";

revoke truncate on table "public"."org_site_housing_area" from "anon";

revoke references on table "public"."org_site_housing_area" from "authenticated";

revoke trigger on table "public"."org_site_housing_area" from "authenticated";

revoke truncate on table "public"."org_site_housing_area" from "authenticated";

revoke references on table "public"."org_site_housing_area" from "service_role";

revoke trigger on table "public"."org_site_housing_area" from "service_role";

revoke truncate on table "public"."org_site_housing_area" from "service_role";

revoke references on table "public"."org_sub_module" from "anon";

revoke trigger on table "public"."org_sub_module" from "anon";

revoke truncate on table "public"."org_sub_module" from "anon";

revoke references on table "public"."org_sub_module" from "authenticated";

revoke trigger on table "public"."org_sub_module" from "authenticated";

revoke truncate on table "public"."org_sub_module" from "authenticated";

revoke references on table "public"."org_sub_module" from "service_role";

revoke trigger on table "public"."org_sub_module" from "service_role";

revoke truncate on table "public"."org_sub_module" from "service_role";

revoke references on table "public"."pack_dryer_result" from "anon";

revoke trigger on table "public"."pack_dryer_result" from "anon";

revoke truncate on table "public"."pack_dryer_result" from "anon";

revoke references on table "public"."pack_dryer_result" from "authenticated";

revoke trigger on table "public"."pack_dryer_result" from "authenticated";

revoke truncate on table "public"."pack_dryer_result" from "authenticated";

revoke references on table "public"."pack_dryer_result" from "service_role";

revoke trigger on table "public"."pack_dryer_result" from "service_role";

revoke truncate on table "public"."pack_dryer_result" from "service_role";

revoke references on table "public"."pack_lot" from "anon";

revoke trigger on table "public"."pack_lot" from "anon";

revoke truncate on table "public"."pack_lot" from "anon";

revoke references on table "public"."pack_lot" from "authenticated";

revoke trigger on table "public"."pack_lot" from "authenticated";

revoke truncate on table "public"."pack_lot" from "authenticated";

revoke references on table "public"."pack_lot" from "service_role";

revoke trigger on table "public"."pack_lot" from "service_role";

revoke truncate on table "public"."pack_lot" from "service_role";

revoke references on table "public"."pack_lot_item" from "anon";

revoke trigger on table "public"."pack_lot_item" from "anon";

revoke truncate on table "public"."pack_lot_item" from "anon";

revoke references on table "public"."pack_lot_item" from "authenticated";

revoke trigger on table "public"."pack_lot_item" from "authenticated";

revoke truncate on table "public"."pack_lot_item" from "authenticated";

revoke references on table "public"."pack_lot_item" from "service_role";

revoke trigger on table "public"."pack_lot_item" from "service_role";

revoke truncate on table "public"."pack_lot_item" from "service_role";

revoke references on table "public"."pack_productivity_fail_category" from "anon";

revoke trigger on table "public"."pack_productivity_fail_category" from "anon";

revoke truncate on table "public"."pack_productivity_fail_category" from "anon";

revoke references on table "public"."pack_productivity_fail_category" from "authenticated";

revoke trigger on table "public"."pack_productivity_fail_category" from "authenticated";

revoke truncate on table "public"."pack_productivity_fail_category" from "authenticated";

revoke references on table "public"."pack_productivity_fail_category" from "service_role";

revoke trigger on table "public"."pack_productivity_fail_category" from "service_role";

revoke truncate on table "public"."pack_productivity_fail_category" from "service_role";

revoke references on table "public"."pack_productivity_hour" from "anon";

revoke trigger on table "public"."pack_productivity_hour" from "anon";

revoke truncate on table "public"."pack_productivity_hour" from "anon";

revoke references on table "public"."pack_productivity_hour" from "authenticated";

revoke trigger on table "public"."pack_productivity_hour" from "authenticated";

revoke truncate on table "public"."pack_productivity_hour" from "authenticated";

revoke references on table "public"."pack_productivity_hour" from "service_role";

revoke trigger on table "public"."pack_productivity_hour" from "service_role";

revoke truncate on table "public"."pack_productivity_hour" from "service_role";

revoke references on table "public"."pack_productivity_hour_fail" from "anon";

revoke trigger on table "public"."pack_productivity_hour_fail" from "anon";

revoke truncate on table "public"."pack_productivity_hour_fail" from "anon";

revoke references on table "public"."pack_productivity_hour_fail" from "authenticated";

revoke trigger on table "public"."pack_productivity_hour_fail" from "authenticated";

revoke truncate on table "public"."pack_productivity_hour_fail" from "authenticated";

revoke references on table "public"."pack_productivity_hour_fail" from "service_role";

revoke trigger on table "public"."pack_productivity_hour_fail" from "service_role";

revoke truncate on table "public"."pack_productivity_hour_fail" from "service_role";

revoke references on table "public"."pack_shelf_life" from "anon";

revoke trigger on table "public"."pack_shelf_life" from "anon";

revoke truncate on table "public"."pack_shelf_life" from "anon";

revoke references on table "public"."pack_shelf_life" from "authenticated";

revoke trigger on table "public"."pack_shelf_life" from "authenticated";

revoke truncate on table "public"."pack_shelf_life" from "authenticated";

revoke references on table "public"."pack_shelf_life" from "service_role";

revoke trigger on table "public"."pack_shelf_life" from "service_role";

revoke truncate on table "public"."pack_shelf_life" from "service_role";

revoke references on table "public"."pack_shelf_life_metric" from "anon";

revoke trigger on table "public"."pack_shelf_life_metric" from "anon";

revoke truncate on table "public"."pack_shelf_life_metric" from "anon";

revoke references on table "public"."pack_shelf_life_metric" from "authenticated";

revoke trigger on table "public"."pack_shelf_life_metric" from "authenticated";

revoke truncate on table "public"."pack_shelf_life_metric" from "authenticated";

revoke references on table "public"."pack_shelf_life_metric" from "service_role";

revoke trigger on table "public"."pack_shelf_life_metric" from "service_role";

revoke truncate on table "public"."pack_shelf_life_metric" from "service_role";

revoke references on table "public"."pack_shelf_life_photo" from "anon";

revoke trigger on table "public"."pack_shelf_life_photo" from "anon";

revoke truncate on table "public"."pack_shelf_life_photo" from "anon";

revoke references on table "public"."pack_shelf_life_photo" from "authenticated";

revoke trigger on table "public"."pack_shelf_life_photo" from "authenticated";

revoke truncate on table "public"."pack_shelf_life_photo" from "authenticated";

revoke references on table "public"."pack_shelf_life_photo" from "service_role";

revoke trigger on table "public"."pack_shelf_life_photo" from "service_role";

revoke truncate on table "public"."pack_shelf_life_photo" from "service_role";

revoke references on table "public"."pack_shelf_life_result" from "anon";

revoke trigger on table "public"."pack_shelf_life_result" from "anon";

revoke truncate on table "public"."pack_shelf_life_result" from "anon";

revoke references on table "public"."pack_shelf_life_result" from "authenticated";

revoke trigger on table "public"."pack_shelf_life_result" from "authenticated";

revoke truncate on table "public"."pack_shelf_life_result" from "authenticated";

revoke references on table "public"."pack_shelf_life_result" from "service_role";

revoke trigger on table "public"."pack_shelf_life_result" from "service_role";

revoke truncate on table "public"."pack_shelf_life_result" from "service_role";

revoke references on table "public"."sales_container_type" from "anon";

revoke trigger on table "public"."sales_container_type" from "anon";

revoke truncate on table "public"."sales_container_type" from "anon";

revoke references on table "public"."sales_container_type" from "authenticated";

revoke trigger on table "public"."sales_container_type" from "authenticated";

revoke truncate on table "public"."sales_container_type" from "authenticated";

revoke references on table "public"."sales_container_type" from "service_role";

revoke trigger on table "public"."sales_container_type" from "service_role";

revoke truncate on table "public"."sales_container_type" from "service_role";

revoke references on table "public"."sales_crm_external_product" from "anon";

revoke trigger on table "public"."sales_crm_external_product" from "anon";

revoke truncate on table "public"."sales_crm_external_product" from "anon";

revoke references on table "public"."sales_crm_external_product" from "authenticated";

revoke trigger on table "public"."sales_crm_external_product" from "authenticated";

revoke truncate on table "public"."sales_crm_external_product" from "authenticated";

revoke references on table "public"."sales_crm_external_product" from "service_role";

revoke trigger on table "public"."sales_crm_external_product" from "service_role";

revoke truncate on table "public"."sales_crm_external_product" from "service_role";

revoke references on table "public"."sales_crm_store" from "anon";

revoke trigger on table "public"."sales_crm_store" from "anon";

revoke truncate on table "public"."sales_crm_store" from "anon";

revoke references on table "public"."sales_crm_store" from "authenticated";

revoke trigger on table "public"."sales_crm_store" from "authenticated";

revoke truncate on table "public"."sales_crm_store" from "authenticated";

revoke references on table "public"."sales_crm_store" from "service_role";

revoke trigger on table "public"."sales_crm_store" from "service_role";

revoke truncate on table "public"."sales_crm_store" from "service_role";

revoke references on table "public"."sales_crm_store_visit" from "anon";

revoke trigger on table "public"."sales_crm_store_visit" from "anon";

revoke truncate on table "public"."sales_crm_store_visit" from "anon";

revoke references on table "public"."sales_crm_store_visit" from "authenticated";

revoke trigger on table "public"."sales_crm_store_visit" from "authenticated";

revoke truncate on table "public"."sales_crm_store_visit" from "authenticated";

revoke references on table "public"."sales_crm_store_visit" from "service_role";

revoke trigger on table "public"."sales_crm_store_visit" from "service_role";

revoke truncate on table "public"."sales_crm_store_visit" from "service_role";

revoke references on table "public"."sales_crm_store_visit_photo" from "anon";

revoke trigger on table "public"."sales_crm_store_visit_photo" from "anon";

revoke truncate on table "public"."sales_crm_store_visit_photo" from "anon";

revoke references on table "public"."sales_crm_store_visit_photo" from "authenticated";

revoke trigger on table "public"."sales_crm_store_visit_photo" from "authenticated";

revoke truncate on table "public"."sales_crm_store_visit_photo" from "authenticated";

revoke references on table "public"."sales_crm_store_visit_photo" from "service_role";

revoke trigger on table "public"."sales_crm_store_visit_photo" from "service_role";

revoke truncate on table "public"."sales_crm_store_visit_photo" from "service_role";

revoke references on table "public"."sales_crm_store_visit_result" from "anon";

revoke trigger on table "public"."sales_crm_store_visit_result" from "anon";

revoke truncate on table "public"."sales_crm_store_visit_result" from "anon";

revoke references on table "public"."sales_crm_store_visit_result" from "authenticated";

revoke trigger on table "public"."sales_crm_store_visit_result" from "authenticated";

revoke truncate on table "public"."sales_crm_store_visit_result" from "authenticated";

revoke references on table "public"."sales_crm_store_visit_result" from "service_role";

revoke trigger on table "public"."sales_crm_store_visit_result" from "service_role";

revoke truncate on table "public"."sales_crm_store_visit_result" from "service_role";

revoke references on table "public"."sales_customer" from "anon";

revoke trigger on table "public"."sales_customer" from "anon";

revoke truncate on table "public"."sales_customer" from "anon";

revoke references on table "public"."sales_customer" from "authenticated";

revoke trigger on table "public"."sales_customer" from "authenticated";

revoke truncate on table "public"."sales_customer" from "authenticated";

revoke references on table "public"."sales_customer" from "service_role";

revoke trigger on table "public"."sales_customer" from "service_role";

revoke truncate on table "public"."sales_customer" from "service_role";

revoke references on table "public"."sales_customer_group" from "anon";

revoke trigger on table "public"."sales_customer_group" from "anon";

revoke truncate on table "public"."sales_customer_group" from "anon";

revoke references on table "public"."sales_customer_group" from "authenticated";

revoke trigger on table "public"."sales_customer_group" from "authenticated";

revoke truncate on table "public"."sales_customer_group" from "authenticated";

revoke references on table "public"."sales_customer_group" from "service_role";

revoke trigger on table "public"."sales_customer_group" from "service_role";

revoke truncate on table "public"."sales_customer_group" from "service_role";

revoke references on table "public"."sales_edi_inbound_message" from "anon";

revoke trigger on table "public"."sales_edi_inbound_message" from "anon";

revoke truncate on table "public"."sales_edi_inbound_message" from "anon";

revoke references on table "public"."sales_edi_inbound_message" from "authenticated";

revoke trigger on table "public"."sales_edi_inbound_message" from "authenticated";

revoke truncate on table "public"."sales_edi_inbound_message" from "authenticated";

revoke references on table "public"."sales_edi_inbound_message" from "service_role";

revoke trigger on table "public"."sales_edi_inbound_message" from "service_role";

revoke truncate on table "public"."sales_edi_inbound_message" from "service_role";

revoke references on table "public"."sales_fob" from "anon";

revoke trigger on table "public"."sales_fob" from "anon";

revoke truncate on table "public"."sales_fob" from "anon";

revoke references on table "public"."sales_fob" from "authenticated";

revoke trigger on table "public"."sales_fob" from "authenticated";

revoke truncate on table "public"."sales_fob" from "authenticated";

revoke references on table "public"."sales_fob" from "service_role";

revoke trigger on table "public"."sales_fob" from "service_role";

revoke truncate on table "public"."sales_fob" from "service_role";

revoke references on table "public"."sales_invoice" from "anon";

revoke trigger on table "public"."sales_invoice" from "anon";

revoke truncate on table "public"."sales_invoice" from "anon";

revoke references on table "public"."sales_invoice" from "authenticated";

revoke trigger on table "public"."sales_invoice" from "authenticated";

revoke truncate on table "public"."sales_invoice" from "authenticated";

revoke references on table "public"."sales_invoice" from "service_role";

revoke trigger on table "public"."sales_invoice" from "service_role";

revoke truncate on table "public"."sales_invoice" from "service_role";

revoke references on table "public"."sales_pallet" from "anon";

revoke trigger on table "public"."sales_pallet" from "anon";

revoke truncate on table "public"."sales_pallet" from "anon";

revoke references on table "public"."sales_pallet" from "authenticated";

revoke trigger on table "public"."sales_pallet" from "authenticated";

revoke truncate on table "public"."sales_pallet" from "authenticated";

revoke references on table "public"."sales_pallet" from "service_role";

revoke trigger on table "public"."sales_pallet" from "service_role";

revoke truncate on table "public"."sales_pallet" from "service_role";

revoke references on table "public"."sales_pallet_allocation" from "anon";

revoke trigger on table "public"."sales_pallet_allocation" from "anon";

revoke truncate on table "public"."sales_pallet_allocation" from "anon";

revoke references on table "public"."sales_pallet_allocation" from "authenticated";

revoke trigger on table "public"."sales_pallet_allocation" from "authenticated";

revoke truncate on table "public"."sales_pallet_allocation" from "authenticated";

revoke references on table "public"."sales_pallet_allocation" from "service_role";

revoke trigger on table "public"."sales_pallet_allocation" from "service_role";

revoke truncate on table "public"."sales_pallet_allocation" from "service_role";

revoke references on table "public"."sales_po" from "anon";

revoke trigger on table "public"."sales_po" from "anon";

revoke truncate on table "public"."sales_po" from "anon";

revoke references on table "public"."sales_po" from "authenticated";

revoke trigger on table "public"."sales_po" from "authenticated";

revoke truncate on table "public"."sales_po" from "authenticated";

revoke references on table "public"."sales_po" from "service_role";

revoke trigger on table "public"."sales_po" from "service_role";

revoke truncate on table "public"."sales_po" from "service_role";

revoke references on table "public"."sales_po_asn" from "anon";

revoke trigger on table "public"."sales_po_asn" from "anon";

revoke truncate on table "public"."sales_po_asn" from "anon";

revoke references on table "public"."sales_po_asn" from "authenticated";

revoke trigger on table "public"."sales_po_asn" from "authenticated";

revoke truncate on table "public"."sales_po_asn" from "authenticated";

revoke references on table "public"."sales_po_asn" from "service_role";

revoke trigger on table "public"."sales_po_asn" from "service_role";

revoke truncate on table "public"."sales_po_asn" from "service_role";

revoke references on table "public"."sales_po_asn_carton" from "anon";

revoke trigger on table "public"."sales_po_asn_carton" from "anon";

revoke truncate on table "public"."sales_po_asn_carton" from "anon";

revoke references on table "public"."sales_po_asn_carton" from "authenticated";

revoke trigger on table "public"."sales_po_asn_carton" from "authenticated";

revoke truncate on table "public"."sales_po_asn_carton" from "authenticated";

revoke references on table "public"."sales_po_asn_carton" from "service_role";

revoke trigger on table "public"."sales_po_asn_carton" from "service_role";

revoke truncate on table "public"."sales_po_asn_carton" from "service_role";

revoke references on table "public"."sales_po_fulfillment" from "anon";

revoke trigger on table "public"."sales_po_fulfillment" from "anon";

revoke truncate on table "public"."sales_po_fulfillment" from "anon";

revoke references on table "public"."sales_po_fulfillment" from "authenticated";

revoke trigger on table "public"."sales_po_fulfillment" from "authenticated";

revoke truncate on table "public"."sales_po_fulfillment" from "authenticated";

revoke references on table "public"."sales_po_fulfillment" from "service_role";

revoke trigger on table "public"."sales_po_fulfillment" from "service_role";

revoke truncate on table "public"."sales_po_fulfillment" from "service_role";

revoke references on table "public"."sales_po_line" from "anon";

revoke trigger on table "public"."sales_po_line" from "anon";

revoke truncate on table "public"."sales_po_line" from "anon";

revoke references on table "public"."sales_po_line" from "authenticated";

revoke trigger on table "public"."sales_po_line" from "authenticated";

revoke truncate on table "public"."sales_po_line" from "authenticated";

revoke references on table "public"."sales_po_line" from "service_role";

revoke trigger on table "public"."sales_po_line" from "service_role";

revoke truncate on table "public"."sales_po_line" from "service_role";

revoke references on table "public"."sales_product" from "anon";

revoke trigger on table "public"."sales_product" from "anon";

revoke truncate on table "public"."sales_product" from "anon";

revoke references on table "public"."sales_product" from "authenticated";

revoke trigger on table "public"."sales_product" from "authenticated";

revoke truncate on table "public"."sales_product" from "authenticated";

revoke references on table "public"."sales_product" from "service_role";

revoke trigger on table "public"."sales_product" from "service_role";

revoke truncate on table "public"."sales_product" from "service_role";

revoke references on table "public"."sales_product_buyer_part" from "anon";

revoke trigger on table "public"."sales_product_buyer_part" from "anon";

revoke truncate on table "public"."sales_product_buyer_part" from "anon";

revoke references on table "public"."sales_product_buyer_part" from "authenticated";

revoke trigger on table "public"."sales_product_buyer_part" from "authenticated";

revoke truncate on table "public"."sales_product_buyer_part" from "authenticated";

revoke references on table "public"."sales_product_buyer_part" from "service_role";

revoke trigger on table "public"."sales_product_buyer_part" from "service_role";

revoke truncate on table "public"."sales_product_buyer_part" from "service_role";

revoke references on table "public"."sales_product_price" from "anon";

revoke trigger on table "public"."sales_product_price" from "anon";

revoke truncate on table "public"."sales_product_price" from "anon";

revoke references on table "public"."sales_product_price" from "authenticated";

revoke trigger on table "public"."sales_product_price" from "authenticated";

revoke truncate on table "public"."sales_product_price" from "authenticated";

revoke references on table "public"."sales_product_price" from "service_role";

revoke trigger on table "public"."sales_product_price" from "service_role";

revoke truncate on table "public"."sales_product_price" from "service_role";

revoke references on table "public"."sales_shipment" from "anon";

revoke trigger on table "public"."sales_shipment" from "anon";

revoke truncate on table "public"."sales_shipment" from "anon";

revoke references on table "public"."sales_shipment" from "authenticated";

revoke trigger on table "public"."sales_shipment" from "authenticated";

revoke truncate on table "public"."sales_shipment" from "authenticated";

revoke references on table "public"."sales_shipment" from "service_role";

revoke trigger on table "public"."sales_shipment" from "service_role";

revoke truncate on table "public"."sales_shipment" from "service_role";

revoke references on table "public"."sales_shipment_container" from "anon";

revoke trigger on table "public"."sales_shipment_container" from "anon";

revoke truncate on table "public"."sales_shipment_container" from "anon";

revoke references on table "public"."sales_shipment_container" from "authenticated";

revoke trigger on table "public"."sales_shipment_container" from "authenticated";

revoke truncate on table "public"."sales_shipment_container" from "authenticated";

revoke references on table "public"."sales_shipment_container" from "service_role";

revoke trigger on table "public"."sales_shipment_container" from "service_role";

revoke truncate on table "public"."sales_shipment_container" from "service_role";

revoke references on table "public"."sales_trading_partner" from "anon";

revoke trigger on table "public"."sales_trading_partner" from "anon";

revoke truncate on table "public"."sales_trading_partner" from "anon";

revoke references on table "public"."sales_trading_partner" from "authenticated";

revoke trigger on table "public"."sales_trading_partner" from "authenticated";

revoke truncate on table "public"."sales_trading_partner" from "authenticated";

revoke references on table "public"."sales_trading_partner" from "service_role";

revoke trigger on table "public"."sales_trading_partner" from "service_role";

revoke truncate on table "public"."sales_trading_partner" from "service_role";

revoke references on table "public"."sys_access_level" from "anon";

revoke trigger on table "public"."sys_access_level" from "anon";

revoke truncate on table "public"."sys_access_level" from "anon";

revoke references on table "public"."sys_access_level" from "authenticated";

revoke trigger on table "public"."sys_access_level" from "authenticated";

revoke truncate on table "public"."sys_access_level" from "authenticated";

revoke references on table "public"."sys_access_level" from "service_role";

revoke trigger on table "public"."sys_access_level" from "service_role";

revoke truncate on table "public"."sys_access_level" from "service_role";

revoke references on table "public"."sys_module" from "anon";

revoke trigger on table "public"."sys_module" from "anon";

revoke truncate on table "public"."sys_module" from "anon";

revoke references on table "public"."sys_module" from "authenticated";

revoke trigger on table "public"."sys_module" from "authenticated";

revoke truncate on table "public"."sys_module" from "authenticated";

revoke references on table "public"."sys_module" from "service_role";

revoke trigger on table "public"."sys_module" from "service_role";

revoke truncate on table "public"."sys_module" from "service_role";

revoke references on table "public"."sys_sub_module" from "anon";

revoke trigger on table "public"."sys_sub_module" from "anon";

revoke truncate on table "public"."sys_sub_module" from "anon";

revoke references on table "public"."sys_sub_module" from "authenticated";

revoke trigger on table "public"."sys_sub_module" from "authenticated";

revoke truncate on table "public"."sys_sub_module" from "authenticated";

revoke references on table "public"."sys_sub_module" from "service_role";

revoke trigger on table "public"."sys_sub_module" from "service_role";

revoke truncate on table "public"."sys_sub_module" from "service_role";

revoke references on table "public"."sys_uom" from "anon";

revoke trigger on table "public"."sys_uom" from "anon";

revoke truncate on table "public"."sys_uom" from "anon";

revoke references on table "public"."sys_uom" from "authenticated";

revoke trigger on table "public"."sys_uom" from "authenticated";

revoke truncate on table "public"."sys_uom" from "authenticated";

revoke references on table "public"."sys_uom" from "service_role";

revoke trigger on table "public"."sys_uom" from "service_role";

revoke truncate on table "public"."sys_uom" from "service_role";

alter table "public"."edi_crodeon_weather" drop constraint "edi_crodeon_weather_org_id_fkey";

alter table "public"."fsafe_result" drop constraint "fk_fsafe_result_sampled_by";

alter table "public"."fsafe_result" drop constraint "fk_fsafe_result_verified_by";

alter table "public"."grow_scout_result" drop constraint "chk_grow_scout_result_type";

alter table "public"."hr_disciplinary_warning" drop constraint "fk_hr_disciplinary_warning_employee";

alter table "public"."hr_disciplinary_warning" drop constraint "fk_hr_disciplinary_warning_reported_by";

alter table "public"."hr_disciplinary_warning" drop constraint "fk_hr_disciplinary_warning_reviewed_by";

alter table "public"."hr_employee" drop constraint "hr_employee_compensation_manager_fkey";

alter table "public"."hr_employee" drop constraint "hr_employee_team_lead_fkey";

alter table "public"."hr_employee_review" drop constraint "fk_hr_employee_review_employee";

alter table "public"."hr_employee_review" drop constraint "fk_hr_employee_review_lead";

alter table "public"."hr_time_off_request" drop constraint "fk_hr_time_off_request_employee";

alter table "public"."hr_time_off_request" drop constraint "fk_hr_time_off_request_requested_by";

alter table "public"."hr_time_off_request" drop constraint "fk_hr_time_off_request_reviewed_by";

alter table "public"."hr_travel_request" drop constraint "fk_hr_travel_request_employee";

alter table "public"."hr_travel_request" drop constraint "fk_hr_travel_request_requested_by";

alter table "public"."hr_travel_request" drop constraint "fk_hr_travel_request_reviewed_by";

alter table "public"."maint_request" drop constraint "fk_maint_request_fixer";

alter table "public"."maint_request" drop constraint "fk_maint_request_requested_by";

alter table "public"."ops_corrective_action_taken" drop constraint "fk_ops_corrective_action_taken_assigned_to";

alter table "public"."ops_corrective_action_taken" drop constraint "fk_ops_corrective_action_taken_verified_by";

alter table "public"."ops_training" drop constraint "fk_ops_training_trainer";

alter table "public"."ops_training" drop constraint "fk_ops_training_verified_by";

alter table "public"."sales_po" drop constraint "fk_sales_po_approved_by";

alter table "public"."sales_po" drop constraint "fk_sales_po_qb_uploaded_by";

alter table "public"."grow_fertigation" drop constraint "grow_fertigation_volume_uom_fkey";

alter table "public"."grow_fertigation_recipe_item" drop constraint "grow_fertigation_recipe_item_application_uom_fkey";

alter table "public"."grow_fertigation_recipe_item" drop constraint "grow_fertigation_recipe_item_burn_uom_fkey";

alter table "public"."grow_harvest_container" drop constraint "grow_harvest_container_weight_uom_fkey";

alter table "public"."grow_harvest_weight" drop constraint "grow_harvest_weight_weight_uom_fkey";

alter table "public"."grow_lettuce_seed_batch" drop constraint "grow_lettuce_seed_batch_seeding_uom_fkey";

alter table "public"."grow_monitoring_metric" drop constraint "grow_monitoring_metric_reading_uom_fkey";

alter table "public"."grow_spray_compliance" drop constraint "grow_spray_compliance_application_uom_fkey";

alter table "public"."grow_spray_compliance" drop constraint "grow_spray_compliance_burn_uom_fkey";

alter table "public"."grow_spray_equipment" drop constraint "grow_spray_equipment_water_uom_fkey";

alter table "public"."grow_spray_input" drop constraint "grow_spray_input_application_uom_fkey";

alter table "public"."invnt_item" drop constraint "invnt_item_burn_uom_fkey";

alter table "public"."invnt_item" drop constraint "invnt_item_onhand_uom_fkey";

alter table "public"."invnt_item" drop constraint "invnt_item_order_uom_fkey";

alter table "public"."invnt_onhand" drop constraint "invnt_onhand_burn_uom_fkey";

alter table "public"."invnt_onhand" drop constraint "invnt_onhand_onhand_uom_fkey";

alter table "public"."invnt_po" drop constraint "invnt_po_burn_uom_fkey";

alter table "public"."invnt_po" drop constraint "invnt_po_order_uom_fkey";

alter table "public"."invnt_po_received" drop constraint "invnt_po_received_received_uom_fkey";

alter table "public"."maint_request_invnt_item" drop constraint "maint_request_invnt_item_uom_fkey";

alter table "public"."org_farm" drop constraint "org_farm_growing_uom_fkey";

alter table "public"."org_farm" drop constraint "org_farm_volume_uom_fkey";

alter table "public"."org_farm" drop constraint "org_farm_weighing_uom_fkey";

alter table "public"."sales_product" drop constraint "sales_product_dimension_uom_fkey";

alter table "public"."sales_product" drop constraint "sales_product_item_uom_fkey";

alter table "public"."sales_product" drop constraint "sales_product_pack_uom_fkey";

drop view if exists "public"."edi_qb_expense_summary";

drop view if exists "public"."edi_qb_invoice_summary";

drop view if exists "public"."ops_task_weekly_schedule";

drop index if exists "public"."idx_edi_crodeon_weather_at";

drop index if exists "public"."idx_edi_crodeon_weather_org_at";

drop index if exists "public"."idx_hr_employee_department";

drop index if exists "public"."idx_hr_employee_team_lead";

drop index if exists "public"."idx_hr_module_access_module";

CREATE INDEX idx_grow_weather_reading_at ON public.edi_crodeon_weather USING btree (reading_at DESC);

CREATE INDEX idx_grow_weather_reading_org_at ON public.edi_crodeon_weather USING btree (org_id, reading_at DESC);

CREATE INDEX idx_hr_department_org_id ON public.hr_department USING btree (org_id);

CREATE INDEX idx_hr_employee_org_id ON public.hr_employee USING btree (org_id);

CREATE INDEX idx_hr_work_authorization_org_id ON public.hr_work_authorization USING btree (org_id);

CREATE INDEX idx_hr_employee_department ON public.hr_employee USING btree (hr_department_id);

CREATE INDEX idx_hr_employee_team_lead ON public.hr_employee USING btree (team_lead_id);

CREATE INDEX idx_hr_module_access_module ON public.hr_module_access USING btree (sys_module_id);

alter table "public"."edi_crodeon_weather" add constraint "grow_weather_reading_org_id_fkey" FOREIGN KEY (org_id) REFERENCES public.org(id) not valid;

alter table "public"."edi_crodeon_weather" validate constraint "grow_weather_reading_org_id_fkey";

alter table "public"."fsafe_result" add constraint "fsafe_result_sampled_by_emp_fkey" FOREIGN KEY (org_id, sampled_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."fsafe_result" validate constraint "fsafe_result_sampled_by_emp_fkey";

alter table "public"."fsafe_result" add constraint "fsafe_result_verified_by_emp_fkey" FOREIGN KEY (org_id, verified_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."fsafe_result" validate constraint "fsafe_result_verified_by_emp_fkey";

alter table "public"."hr_disciplinary_warning" add constraint "hr_disciplinary_warning_hr_employee_id_emp_fkey" FOREIGN KEY (org_id, hr_employee_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_disciplinary_warning" validate constraint "hr_disciplinary_warning_hr_employee_id_emp_fkey";

alter table "public"."hr_disciplinary_warning" add constraint "hr_disciplinary_warning_reported_by_emp_fkey" FOREIGN KEY (org_id, reported_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_disciplinary_warning" validate constraint "hr_disciplinary_warning_reported_by_emp_fkey";

alter table "public"."hr_disciplinary_warning" add constraint "hr_disciplinary_warning_reviewed_by_emp_fkey" FOREIGN KEY (org_id, reviewed_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_disciplinary_warning" validate constraint "hr_disciplinary_warning_reviewed_by_emp_fkey";

alter table "public"."hr_employee" add constraint "hr_employee_compensation_manager_id_emp_fkey" FOREIGN KEY (org_id, compensation_manager_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_employee" validate constraint "hr_employee_compensation_manager_id_emp_fkey";

alter table "public"."hr_employee" add constraint "hr_employee_team_lead_id_emp_fkey" FOREIGN KEY (org_id, team_lead_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_employee" validate constraint "hr_employee_team_lead_id_emp_fkey";

alter table "public"."hr_employee_review" add constraint "hr_employee_review_hr_employee_id_emp_fkey" FOREIGN KEY (org_id, hr_employee_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_employee_review" validate constraint "hr_employee_review_hr_employee_id_emp_fkey";

alter table "public"."hr_employee_review" add constraint "hr_employee_review_lead_id_emp_fkey" FOREIGN KEY (org_id, lead_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_employee_review" validate constraint "hr_employee_review_lead_id_emp_fkey";

alter table "public"."hr_time_off_request" add constraint "hr_time_off_request_hr_employee_id_emp_fkey" FOREIGN KEY (org_id, hr_employee_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_time_off_request" validate constraint "hr_time_off_request_hr_employee_id_emp_fkey";

alter table "public"."hr_time_off_request" add constraint "hr_time_off_request_requested_by_emp_fkey" FOREIGN KEY (org_id, requested_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_time_off_request" validate constraint "hr_time_off_request_requested_by_emp_fkey";

alter table "public"."hr_time_off_request" add constraint "hr_time_off_request_reviewed_by_emp_fkey" FOREIGN KEY (org_id, reviewed_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_time_off_request" validate constraint "hr_time_off_request_reviewed_by_emp_fkey";

alter table "public"."hr_travel_request" add constraint "hr_travel_request_hr_employee_id_emp_fkey" FOREIGN KEY (org_id, hr_employee_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_travel_request" validate constraint "hr_travel_request_hr_employee_id_emp_fkey";

alter table "public"."hr_travel_request" add constraint "hr_travel_request_requested_by_emp_fkey" FOREIGN KEY (org_id, requested_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_travel_request" validate constraint "hr_travel_request_requested_by_emp_fkey";

alter table "public"."hr_travel_request" add constraint "hr_travel_request_reviewed_by_emp_fkey" FOREIGN KEY (org_id, reviewed_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."hr_travel_request" validate constraint "hr_travel_request_reviewed_by_emp_fkey";

alter table "public"."maint_request" add constraint "maint_request_fixer_id_emp_fkey" FOREIGN KEY (org_id, fixer_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."maint_request" validate constraint "maint_request_fixer_id_emp_fkey";

alter table "public"."maint_request" add constraint "maint_request_requested_by_emp_fkey" FOREIGN KEY (org_id, requested_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."maint_request" validate constraint "maint_request_requested_by_emp_fkey";

alter table "public"."ops_corrective_action_taken" add constraint "ops_corrective_action_taken_assigned_to_emp_fkey" FOREIGN KEY (org_id, assigned_to) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."ops_corrective_action_taken" validate constraint "ops_corrective_action_taken_assigned_to_emp_fkey";

alter table "public"."ops_corrective_action_taken" add constraint "ops_corrective_action_taken_verified_by_emp_fkey" FOREIGN KEY (org_id, verified_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."ops_corrective_action_taken" validate constraint "ops_corrective_action_taken_verified_by_emp_fkey";

alter table "public"."ops_training" add constraint "ops_training_trainer_id_emp_fkey" FOREIGN KEY (org_id, trainer_id) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."ops_training" validate constraint "ops_training_trainer_id_emp_fkey";

alter table "public"."ops_training" add constraint "ops_training_verified_by_emp_fkey" FOREIGN KEY (org_id, verified_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."ops_training" validate constraint "ops_training_verified_by_emp_fkey";

alter table "public"."sales_po" add constraint "sales_po_approved_by_emp_fkey" FOREIGN KEY (org_id, approved_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."sales_po" validate constraint "sales_po_approved_by_emp_fkey";

alter table "public"."sales_po" add constraint "sales_po_qb_uploaded_by_emp_fkey" FOREIGN KEY (org_id, qb_uploaded_by) REFERENCES public.hr_employee(org_id, id) not valid;

alter table "public"."sales_po" validate constraint "sales_po_qb_uploaded_by_emp_fkey";

alter table "public"."grow_fertigation" add constraint "grow_fertigation_volume_uom_fkey" FOREIGN KEY (volume_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_fertigation" validate constraint "grow_fertigation_volume_uom_fkey";

alter table "public"."grow_fertigation_recipe_item" add constraint "grow_fertigation_recipe_item_application_uom_fkey" FOREIGN KEY (application_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_fertigation_recipe_item" validate constraint "grow_fertigation_recipe_item_application_uom_fkey";

alter table "public"."grow_fertigation_recipe_item" add constraint "grow_fertigation_recipe_item_burn_uom_fkey" FOREIGN KEY (burn_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_fertigation_recipe_item" validate constraint "grow_fertigation_recipe_item_burn_uom_fkey";

alter table "public"."grow_harvest_container" add constraint "grow_harvest_container_weight_uom_fkey" FOREIGN KEY (weight_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_harvest_container" validate constraint "grow_harvest_container_weight_uom_fkey";

alter table "public"."grow_harvest_weight" add constraint "grow_harvest_weight_weight_uom_fkey" FOREIGN KEY (weight_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_harvest_weight" validate constraint "grow_harvest_weight_weight_uom_fkey";

alter table "public"."grow_lettuce_seed_batch" add constraint "grow_lettuce_seed_batch_seeding_uom_fkey" FOREIGN KEY (seeding_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_lettuce_seed_batch" validate constraint "grow_lettuce_seed_batch_seeding_uom_fkey";

alter table "public"."grow_monitoring_metric" add constraint "grow_monitoring_metric_reading_uom_fkey" FOREIGN KEY (reading_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_monitoring_metric" validate constraint "grow_monitoring_metric_reading_uom_fkey";

alter table "public"."grow_spray_compliance" add constraint "grow_spray_compliance_application_uom_fkey" FOREIGN KEY (application_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_spray_compliance" validate constraint "grow_spray_compliance_application_uom_fkey";

alter table "public"."grow_spray_compliance" add constraint "grow_spray_compliance_burn_uom_fkey" FOREIGN KEY (burn_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_spray_compliance" validate constraint "grow_spray_compliance_burn_uom_fkey";

alter table "public"."grow_spray_equipment" add constraint "grow_spray_equipment_water_uom_fkey" FOREIGN KEY (water_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_spray_equipment" validate constraint "grow_spray_equipment_water_uom_fkey";

alter table "public"."grow_spray_input" add constraint "grow_spray_input_application_uom_fkey" FOREIGN KEY (application_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."grow_spray_input" validate constraint "grow_spray_input_application_uom_fkey";

alter table "public"."invnt_item" add constraint "invnt_item_burn_uom_fkey" FOREIGN KEY (burn_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_item" validate constraint "invnt_item_burn_uom_fkey";

alter table "public"."invnt_item" add constraint "invnt_item_onhand_uom_fkey" FOREIGN KEY (onhand_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_item" validate constraint "invnt_item_onhand_uom_fkey";

alter table "public"."invnt_item" add constraint "invnt_item_order_uom_fkey" FOREIGN KEY (order_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_item" validate constraint "invnt_item_order_uom_fkey";

alter table "public"."invnt_onhand" add constraint "invnt_onhand_burn_uom_fkey" FOREIGN KEY (burn_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_onhand" validate constraint "invnt_onhand_burn_uom_fkey";

alter table "public"."invnt_onhand" add constraint "invnt_onhand_onhand_uom_fkey" FOREIGN KEY (onhand_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_onhand" validate constraint "invnt_onhand_onhand_uom_fkey";

alter table "public"."invnt_po" add constraint "invnt_po_burn_uom_fkey" FOREIGN KEY (burn_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_po" validate constraint "invnt_po_burn_uom_fkey";

alter table "public"."invnt_po" add constraint "invnt_po_order_uom_fkey" FOREIGN KEY (order_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_po" validate constraint "invnt_po_order_uom_fkey";

alter table "public"."invnt_po_received" add constraint "invnt_po_received_received_uom_fkey" FOREIGN KEY (received_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."invnt_po_received" validate constraint "invnt_po_received_received_uom_fkey";

alter table "public"."maint_request_invnt_item" add constraint "maint_request_invnt_item_uom_fkey" FOREIGN KEY (uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."maint_request_invnt_item" validate constraint "maint_request_invnt_item_uom_fkey";

alter table "public"."org_farm" add constraint "org_farm_growing_uom_fkey" FOREIGN KEY (growing_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."org_farm" validate constraint "org_farm_growing_uom_fkey";

alter table "public"."org_farm" add constraint "org_farm_volume_uom_fkey" FOREIGN KEY (volume_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."org_farm" validate constraint "org_farm_volume_uom_fkey";

alter table "public"."org_farm" add constraint "org_farm_weighing_uom_fkey" FOREIGN KEY (weighing_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."org_farm" validate constraint "org_farm_weighing_uom_fkey";

alter table "public"."sales_product" add constraint "sales_product_dimension_uom_fkey" FOREIGN KEY (dimension_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."sales_product" validate constraint "sales_product_dimension_uom_fkey";

alter table "public"."sales_product" add constraint "sales_product_item_uom_fkey" FOREIGN KEY (item_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."sales_product" validate constraint "sales_product_item_uom_fkey";

alter table "public"."sales_product" add constraint "sales_product_pack_uom_fkey" FOREIGN KEY (pack_uom) REFERENCES public.sys_uom(id) ON UPDATE CASCADE not valid;

alter table "public"."sales_product" validate constraint "sales_product_pack_uom_fkey";

create or replace view "public"."edi_qb_expense_summary" as  SELECT h.org_id,
    h.payee_name,
    h.account_name AS funding_account,
    h.is_credit,
    h.transaction_date,
    l.line_num,
    l.account_name AS expense_account,
    l.class_name,
    l.description,
    l.amount
   FROM (public.edi_qb_expense h
     LEFT JOIN public.edi_qb_expense_line l ON (((l.org_id = h.org_id) AND (l.expense_id = h.id))));


create or replace view "public"."edi_qb_invoice_summary" as  SELECT h.org_id,
    h.customer_name,
    sc.sales_customer_group_id AS customer_group,
    h.invoice_number,
    h.invoice_date,
    l.line_num,
    l.service_date,
    l.item_name,
    sp.farm_id AS farm,
    l.cases,
    l.amount,
    (l.cases * sp.case_net_weight) AS pounds
   FROM (((public.edi_qb_invoice h
     LEFT JOIN public.edi_qb_invoice_line l ON (((l.org_id = h.org_id) AND (l.invoice_id = h.id))))
     LEFT JOIN public.sales_customer sc ON (((sc.org_id = h.org_id) AND (sc.id = h.customer_name))))
     LEFT JOIN public.sales_product sp ON (((sp.org_id = h.org_id) AND (sp.id = l.item_name))));


create or replace view "public"."ops_task_weekly_schedule" as  WITH schedule_base AS (
         SELECT s.hr_employee_id,
            s.ops_task_id,
            s.org_id,
            s.farm_id,
            s.start_time AS schedule_start,
            s.stop_time AS schedule_stop,
            s.total_hours AS schedule_total_hours,
            (s.start_time)::date AS task_date,
            (EXTRACT(dow FROM s.start_time))::integer AS day_of_week,
            ((s.start_time)::date - (EXTRACT(dow FROM s.start_time))::integer) AS week_start_date
           FROM public.ops_task_schedule s
          WHERE ((s.ops_task_tracker_id IS NULL) AND (s.start_time IS NOT NULL) AND (s.is_deleted = false))
        ), per_task AS (
         SELECT sb.org_id,
            sb.week_start_date,
            e.id AS hr_employee_id,
            TRIM(BOTH FROM ((e.first_name || ' '::text) || e.last_name)) AS full_name,
            e.profile_photo_url,
            e.overtime_threshold,
            t.id AS task,
            max(
                CASE
                    WHEN (sb.day_of_week = 0) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS sunday,
            max(
                CASE
                    WHEN (sb.day_of_week = 1) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS monday,
            max(
                CASE
                    WHEN (sb.day_of_week = 2) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS tuesday,
            max(
                CASE
                    WHEN (sb.day_of_week = 3) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS wednesday,
            max(
                CASE
                    WHEN (sb.day_of_week = 4) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS thursday,
            max(
                CASE
                    WHEN (sb.day_of_week = 5) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS friday,
            max(
                CASE
                    WHEN (sb.day_of_week = 6) THEN (to_char((sb.schedule_start AT TIME ZONE 'UTC'::text), 'HH24:MI'::text) ||
                    CASE
                        WHEN (sb.schedule_stop IS NOT NULL) THEN (' - '::text || to_char((sb.schedule_stop AT TIME ZONE 'UTC'::text), 'HH24:MI'::text))
                        ELSE ''::text
                    END)
                    ELSE NULL::text
                END) AS saturday,
            round(sum(COALESCE(sb.schedule_total_hours,
                CASE
                    WHEN (sb.schedule_stop IS NOT NULL) THEN (EXTRACT(epoch FROM (sb.schedule_stop - sb.schedule_start)) / 3600.0)
                    ELSE (0)::numeric
                END))) AS total_hours
           FROM ((schedule_base sb
             JOIN public.hr_employee e ON ((e.id = sb.hr_employee_id)))
             JOIN public.ops_task t ON ((t.id = sb.ops_task_id)))
          GROUP BY sb.week_start_date, sb.org_id, sb.farm_id, e.id, e.first_name, e.last_name, e.profile_photo_url, e.overtime_threshold, t.id
        )
 SELECT org_id,
    week_start_date,
    hr_employee_id,
    full_name,
    profile_photo_url,
    task,
    sunday,
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    total_hours,
        CASE
            WHEN (overtime_threshold IS NOT NULL) THEN round((overtime_threshold / 2.0))
            ELSE NULL::numeric
        END AS ot_threshold_weekly,
        CASE
            WHEN (overtime_threshold IS NULL) THEN NULL::text
            WHEN (round(sum(total_hours) OVER (PARTITION BY hr_employee_id, week_start_date)) > round((overtime_threshold / 2.0))) THEN 'above'::text
            WHEN (round(sum(total_hours) OVER (PARTITION BY hr_employee_id, week_start_date)) = round((overtime_threshold / 2.0))) THEN 'at'::text
            ELSE 'below'::text
        END AS ot_status
   FROM per_task
  ORDER BY week_start_date, full_name;



  create policy "grow_weather_reading_delete"
  on "public"."edi_crodeon_weather"
  as permissive
  for delete
  to authenticated
using ((org_id IN ( SELECT public.get_user_org_ids() AS get_user_org_ids)));



  create policy "grow_weather_reading_insert"
  on "public"."edi_crodeon_weather"
  as permissive
  for insert
  to authenticated
with check ((org_id IN ( SELECT public.get_user_org_ids() AS get_user_org_ids)));



  create policy "grow_weather_reading_update"
  on "public"."edi_crodeon_weather"
  as permissive
  for update
  to authenticated
using ((org_id IN ( SELECT public.get_user_org_ids() AS get_user_org_ids)))
with check ((org_id IN ( SELECT public.get_user_org_ids() AS get_user_org_ids)));



