-- Rename "Human Resources" module to "HR"
UPDATE sys_module
SET name = 'HR'
WHERE id = 'human_resources';
