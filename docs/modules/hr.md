# HR Module — Frontend Data Source Brief

**Status:** HR is the only enabled module right now; all others are provisioned but disabled. Seven HR sub-modules are enabled: Register, Scheduler, Time Off, Payroll Comp, Payroll Data, Employee Review, Housing.

**Module gate:** query `hr_rba_navigation` once per session; only rows with `module_slug = 'human_resources'` appear. `can_edit` / `can_delete` / `can_verify` flags ride on each row.

---

## Sub-module data sources

### 1. Register (`register`)
- **Data sits in:** `hr_employee`
- **Read from:** `hr_employee` directly
- **Write to:** `hr_employee` (server-side)
- **Embed:** `hr_department`, `hr_title`, `hr_work_authorization`, `sys_access_level`, `org_site` (housing), self-FKs `fk_hr_employee_team_lead` and `fk_hr_employee_compensation_manager`

### 2. Scheduler (`scheduler`)
- **Data sits in:** `ops_task_schedule` (+ `ops_task` catalog)
- **Read from:** `ops_task_weekly_schedule` — Sunday-anchored rows, day columns as `"HH:MM - HH:MM"` strings, `total_hours` lunch-adjusted
- **Write to:** `ops_task_schedule` with `ops_task_tracker_id = NULL` (planned entries)

### 3. Time Off (`time_off`)
- **Data sits in:** `hr_time_off_request`
- **Read from:** `hr_time_off_request` directly
- **Write to:** `hr_time_off_request`
- **Embed:** `hr_employee` via named FKs `fk_hr_time_off_request_employee`, `fk_hr_time_off_request_requested_by`, `fk_hr_time_off_request_reviewed_by`

### 4. Payroll Comp (`payroll_comp`)
- **Data sits in:** `hr_payroll` + `ops_task_schedule` + `ops_task` (allocated through `hr_payroll_by_task`)
- **Read from:** `hr_payroll_employee_comparison` — one row per `(employee, task)` for the most recent `is_standard=TRUE` HRB `check_date`, with deltas vs the prior `is_standard=TRUE` check_date. Off-cycle / adjustment runs (`is_standard=FALSE`) do not advance the period. Previous-period values are inferable as `current − delta`; previous date is fixed by the pay cadence
- **Write to:** read-only (derived). To influence output, mutate `hr_payroll` (payroll imports), `ops_task_schedule` (schedule edits), or `ops_task.qb_account` (account mapping)
- **Visibility rules (enforce in the loader / server route):**

  | Access level | Rows visible | Columns visible |
  |---|---|---|
  | `employee`, `team_lead` | all employees in the org | hours and delta-hours columns only (`scheduled_hours`, `total_hours`, `discretionary_overtime_hours`, `hours_delta`) — **redact the dollar columns** (`total_cost`, `regular_pay`, `discretionary_overtime_pay`, `total_cost_delta`, `regular_pay_delta`, `discretionary_overtime_pay_delta`, `other_pay_delta`) |
  | `manager` | only rows where `compensation_manager_id` equals this user's `hr_employee.id` | hours **and** dollars |
  | `admin`, `owner` | all rows | hours and dollars |

  The view itself does not apply these filters — it returns everything. The module loader (server-side) must (a) resolve the current user's access level and employee id, (b) add the `compensation_manager_id` filter for managers, and (c) project away the dollar columns for employees and team leads before the payload reaches the client.

### 5. Payroll Data (`payroll_data`)
- **Data sits in:** `hr_payroll`
- **Read from:** `hr_payroll` directly
- **Write to:** `hr_payroll` (normally only the payroll import process)
- **Embed:** `hr_employee`, `hr_department`, `hr_work_authorization`

### 6. Employee Review (`employee_review`)
- **Data sits in:** `hr_employee_review`
- **Read from:** `hr_employee_review` directly
- **Write to:** `hr_employee_review` (the `average` column auto-computes from the four scores; format `quarter_label` client-side)
- **Embed:** `hr_employee` via `fk_hr_employee_review_employee` and `fk_hr_employee_review_lead`

### 7. Housing (`housing`)
- **Data sits in:** `org_site` (category = `housing`) + `hr_employee.site_id`
- **Read from:** `app_hr_housing` — adds `tenant_count`, `available_beds`, `parent_name`
- **Write to:** `org_site` (house create/edit), `hr_employee.site_id` (assign/unassign tenant)
- **Tenant list:** `hr_employee?site_id=eq.$house_id`

---

## Key insights

- **Always pass `org_id = $workspace_org`** — RLS enforces it, but be explicit for query-plan stability and multi-org users.
- **Soft deletes everywhere:** filter `is_deleted = false` on every HR table.
- **Named FKs matter:** `hr_time_off_request` and `hr_employee_review` each have multiple FKs to `hr_employee`. Embeds must use the FK alias (`!fk_…_…`) or PostgREST returns a 400.
- **Writes are server-only:** no INSERT/UPDATE/DELETE RLS on most HR tables. Mutations go through a server route using the service_role key; `can_edit` / `can_delete` / `can_verify` from `hr_module_access` are enforced in application code.
- **Lunch break convention:** `ops_task_weekly_schedule` and the schedule allocation feeding `hr_payroll_by_task` (and therefore `hr_payroll_employee_comparison`) subtract 0.5 hr when a shift crosses noon (start `<` 12:00 AND stop `>` 12:00). Do not re-apply client-side.
- **RBAC current state:** 6 of 7 enabled HR sub-modules require `manager` or `admin`. The exception is **Payroll Comp**, which needs to be opened up to `employee` and `team_lead` with column-level redaction (see section 4). Without that change, employees and team leads still see an empty sidebar.
