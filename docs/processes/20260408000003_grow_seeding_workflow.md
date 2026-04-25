# Grow Seeding Workflow

This document describes the seeding activity flow using `ops_task_tracker` as the activity header and `grow_seed_batch` as the domain-specific record.

> **Prerequisite:** The "Seeding" task must be provisioned in `ops_task`. See [01_org_provisioning.md](20260408000001_org_provisioning.md) for setup steps.

---

## Tables Involved

| Table | Purpose |
|-------|---------|
| `ops_task_tracker` | Activity header — captures who, when, where |
| `grow_seed_batch` | Seeding-specific data — batch code, seed item/mix, UOM, units, dates, status |
| `grow_lettuce_seed_mix` | Named seed blend recipe (if seeding a mix) |
| `grow_lettuce_seed_mix_item` | Individual seeds within a mix with percentages |
| `grow_trial_type` | Optional trial classification |
| `ops_task_schedule` | Employees assigned to this activity with individual start/stop times |

---

## Flow

1. Create an `ops_task_tracker` activity with task = "Seeding"
   - If templates are linked to the "Seeding" task via `ops_task_template`, they are presented for completion
2. Assign employees working on this seeding via `ops_task_schedule` (one row per employee)
3. Create a `grow_seed_batch` record linked to the activity via `ops_task_tracker_id`
4. Select either a single seed item (`invnt_item_name`) or a seed mix (`grow_lettuce_seed_mix_name`) — never both (enforced by CHECK constraint)
5. Enter batch code (system-generated, editable), seeding UOM, number of units, seeds per unit, number of rows
6. Enter seeding date, transplant date, and estimated harvest date
7. Optionally link to a trial type (`grow_trial_type_name`)
8. Update status through lifecycle: `planned` → `seeded` → `transplanted` → `harvesting` → `harvested`

---

## Notes

- A seeding activity can produce multiple batches if different varieties or mixes are seeded in the same session. Each batch gets its own `grow_seed_batch` row linked to the same `ops_task_tracker`.
- The `grow_seed_batch` header is required because it carries business fields (batch code, seed item/mix, UOM, units, dates, status) that do not exist on `ops_task_tracker`.

---

## Flow Diagram

```mermaid
flowchart TD
    A[Create ops_task_tracker\nTask = Seeding] --> A1[Assign employees\nvia ops_task_schedule]
    A1 --> B[Create grow_seed_batch record]
    B --> C{Single variety or mix?}
    C -->|Single| D[Select invnt_item_name]
    C -->|Mix| E[Select grow_lettuce_seed_mix_name]
    D --> F[Enter batch code, seeding UOM,\nnumber of units, seeds per unit, rows]
    E --> F
    F --> G[Enter seeding date, transplant date,\nestimated harvest date]
    G --> H[Optionally link trial type]
    H --> I[Status: planned → seeded →\ntransplanted → harvesting → harvested]
```
