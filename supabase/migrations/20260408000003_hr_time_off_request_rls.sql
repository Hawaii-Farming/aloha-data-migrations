ALTER TABLE hr_time_off_request ENABLE ROW LEVEL SECURITY;

-- Read: org employees only
CREATE POLICY "hr_time_off_request_read" ON public.hr_time_off_request
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.hr_employee e
    WHERE e.org_id = hr_time_off_request.org_id
      AND e.user_id = auth.uid()
      AND e.is_deleted = false
  ));

-- Write: org employees only (CRUD permissions enforced in app layer via hr_module_access)
CREATE POLICY "hr_time_off_request_write" ON public.hr_time_off_request
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.hr_employee e
    WHERE e.org_id = hr_time_off_request.org_id
      AND e.user_id = auth.uid()
      AND e.is_deleted = false
  ));

-- Update: org employees only
CREATE POLICY "hr_time_off_request_update" ON public.hr_time_off_request
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.hr_employee e
    WHERE e.org_id = hr_time_off_request.org_id
      AND e.user_id = auth.uid()
      AND e.is_deleted = false
  ));

-- No DELETE grant -- use soft delete (is_deleted = true)
GRANT SELECT, INSERT, UPDATE ON public.hr_time_off_request TO authenticated;
