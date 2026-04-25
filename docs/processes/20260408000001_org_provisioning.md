# Organization Provisioning

This document lists everything that must be provisioned when a new organization is onboarded. Each section describes what is created, the source data, and the target table.

---

## 1. Provisioning Order

Steps must be executed in this order due to FK dependencies:

1. Create `org` record
2. Copy system modules → `org_module`
3. Copy system sub-modules → `org_sub_module`
4. Provision default site categories → `org_site_category`
5. Create admin `hr_employee` record (manual)
6. Copy org modules → `hr_module_access` for admin
7. Provision default `ops_task` records

---

## 2. Organization Record

| Target | Source | Notes |
|--------|--------|-------|
| `org` | Manual input | Name, address, currency |

---

## 3. Module & Sub-Module Configuration

| Target | Source | Notes |
|--------|--------|-------|
| `org_module` | `sys_module` | One row per system module; all `is_enabled = true`; `display_name` and `display_order` inherited from system |
| `org_sub_module` | `sys_sub_module` | One row per system sub-module; all `is_enabled = true`; `sys_access_level_name`, `display_name`, and `display_order` inherited from system |

---

## 4. Default Site Categories

| Target | Source | Notes |
|--------|--------|-------|
| `org_site_category` | Hardcoded defaults | Two-level hierarchy for classifying sites |

Default categories and subcategories:

| category_name | sub_category_name |
|---|---|
| growing | *(top-level)* |
| growing | greenhouse |
| growing | nursery |
| growing | pond |
| growing | row |
| growing | room |
| packing | *(top-level)* |
| packing | room |
| housing | *(top-level)* |
| housing | room |
| food_safety | *(top-level)* |
| pest_trap | *(top-level)* |
| storage | *(top-level)* |
| storage | warehouse |
| storage | chemical_storage |
| storage | cold_storage |
| other | *(top-level)* |

---

## 5. Default Inventory Categories

| Target | Source | Notes |
|--------|--------|-------|
| `invnt_category` | Hardcoded defaults | Standard inventory categories provisioned for every org |

Default categories and subcategories:

| category_name | sub_category_name |
|---|---|
| chemicals_pesticides | *(top-level)* |
| fertilizers | *(top-level)* |
| seeds | *(top-level)* |
| seeds | trial |
| growing | *(top-level)* |
| packing | *(top-level)* |
| maintenance | *(top-level)* |
| food_safety | *(top-level)* |

---

## 6. Admin Employee

| Target | Source | Notes |
|--------|--------|-------|
| `hr_employee` | Manual input | Created manually with `sys_access_level_name = admin` and a linked `user_id` |

---

## 7. Admin Module Access

| Target | Source | Notes |
|--------|--------|-------|
| `hr_module_access` | `org_module` | One row per enabled org module; all permissions set to `true` (`is_enabled`, `can_edit`, `can_delete`, `can_verify`) |

---

## 8. Default Operations Tasks

| Target | Source | Notes |
|--------|--------|-------|
| `ops_task` | Hardcoded defaults | Required for grow, pack, and food safety activity flows |

Default tasks:

| id | name | Description |
|---|---|---|
| seeding | Seeding | Required by grow_seeding_workflow |
| harvesting | Harvesting | Required by grow_harvesting_workflow |
| scouting | Scouting | Required by grow_scouting_workflow |
| spraying | Spraying | Required by grow_spraying_workflow |
| fertigation | Fertigation | Required by grow_fertigation_workflow |
| monitoring | Monitoring | Required by grow_monitoring_workflow |
| packing | Packing | Required by pack_productivity_workflow |
| pest_trap_inspection | Pest Trap Inspection | Required by fsafe_pest_result |

---

## 9. New Employee Provisioning

When a new employee is added with a `user_id` (app access):

| Target | Source | Notes |
|--------|--------|-------|
| `hr_module_access` | `org_module` | One row per enabled org module; permissions use defaults: `is_enabled = true`, `can_edit = true`, `can_delete = false`, `can_verify = false` |

---

## 10. Future Provisions

As the system grows, additional default data may be required:

- **Grow lookups** — default pest types, disease types, trial types per farm
- **Ops templates** — default checklist templates (e.g. pre-spray safety check)
- **Food safety** — default lab test definitions per org
- **UOM** — standard units of measure (system-level, provisioned once globally)
