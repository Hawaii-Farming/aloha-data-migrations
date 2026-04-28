# Grow Monitoring Workflow

This document describes the environmental monitoring activity flow using `ops_task_tracker` directly as the header. Monitoring points are configurable per farm and site category, with support for direct readings and calculated values.

> **Prerequisite:** The "Monitoring" task must be provisioned in `ops_task`. See [01_org_provisioning.md](20260408000001_org_provisioning.md) for setup steps.

---

## Tables Involved

| Table | Purpose |
|-------|---------|
| `ops_task_tracker` | Activity header — captures org, farm, site, date, start/stop time, notes |
| `grow_monitoring_metric` | Defines what to measure per farm + site category with UOM, thresholds, and formulas |
| `grow_monitoring_result` | Individual measurement per point per station per event |
| `grow_task_seed_batch` | Snapshot of seedings present during the event |
| `grow_task_photo` | Photos taken during monitoring with optional caption |
| `org_site` | Site where monitoring is performed |
| `ops_task_schedule` | Employees assigned to this activity with individual start/stop times |

---

## Setup: Monitoring Points

Before monitoring can begin, an admin creates `grow_monitoring_metric` records scoped to farm + site category:

UOM values are `sys_uom.id` — Proper Case display names like `Milliliter`, `Percent`, `PPM`, `pH`, `Inch`, `Millisiemens`, `Celsius`, `Fahrenheit`.

### Example: Cuke Farm — Greenhouse

| Point | Type | UOM | Min | Max |
|-------|------|-----|-----|-----|
| Drip mL | direct | Milliliter | — | — |
| Drain mL | direct | Milliliter | — | — |
| Drippers | direct | Count | — | — |
| Drain % | calculated | Percent | 20 | 40 |
| Drip EC | direct | Millisiemens | 2.0 | 3.5 |
| Drain EC | direct | Millisiemens | — | — |
| Drip pH | direct | pH | 5.5 | 6.5 |
| Drain pH | direct | pH | — | — |

### Example: Cuke Farm — Nursery

| Point | Type | UOM | Min | Max |
|-------|------|-----|-----|-----|
| High EC | direct | Millisiemens | — | — |
| Low EC | direct | Millisiemens | — | — |
| High pH | direct | pH | — | — |
| Low pH | direct | pH | — | — |
| Water EC | direct | Millisiemens | — | — |
| Water pH | direct | pH | — | — |
| Crop Height | direct | Inch | — | — |
| Substrate | direct | — | — | — |

### Example: Lettuce Farm — Pond

| Point | Type | UOM | Min | Max |
|-------|------|-----|-----|-----|
| Pond EC | direct | Millisiemens | 1.0 | 2.5 |
| Pond pH | direct | pH | 5.8 | 6.2 |
| Dissolved Oxygen | direct | PPM | 5.0 | — |
| Temperature | direct | Fahrenheit | 65 | 75 |
| Water Level Gap | direct | Centimeter | — | 5.0 |

### Calculated Points

A calculated point references other points via `input_point_ids` and evaluates a `formula`:

```
Point: Drain %
point_type: calculated
formula: (drain_ml / (drip_ml * drippers)) * 100
input_point_ids: ["drip_ml", "drain_ml", "drippers"]
minimum_value: 20
maximum_value: 40
```

**Frontend behavior for calculated points:**
- The field is **read-only** — the user cannot type in it
- `input_point_ids` tells the frontend which other metric fields to watch
- When ALL input fields have values, the frontend evaluates the formula and auto-fills the result
- The result is saved to `grow_monitoring_result.reading` for historical record
- The frontend must use a safe expression evaluator (e.g. `mathjs`) — never `eval()`

**How admins create formulas:**

| Approach | Description | Target |
|----------|-------------|--------|
| **Formula builder (recommended)** | Admin selects input metrics from a dropdown and chains them with operators (+, -, ×, ÷, parentheses). The UI generates the formula string. No syntax knowledge required. | MVP target |
| **Direct text entry (fallback)** | Admin types the expression directly (e.g. `(drain_ml / (drip_ml * drippers)) * 100`). Simpler to build but requires the admin to know the metric IDs. | Interim option |

Both approaches store the same `formula` TEXT in the database — the UI method is a frontend decision.

---

## Flow

1. Create an `ops_task_tracker` activity with task = "Monitoring"
   - If templates are linked to the "Monitoring" task via `ops_task_template`, they are presented for completion
2. Assign employees working on this monitoring via `ops_task_schedule` (one row per employee)
3. Select the site — the app loads monitoring points matching `farm_name` + `site.category`
4. Enter the monitoring station name (free-text `grow_monitoring_result.monitoring_station`)
5. For each monitoring point, enter the reading based on its `response_type`:
   - **Numeric**: user enters a number (e.g. EC, pH, mL, temperature)
   - **Boolean**: user toggles yes/no (e.g. Is Injection)
   - **Enum**: user selects from dropdown populated by `enum_options` (e.g. Substrate type)
   - **Calculated points**: app computes the value from the formula once all input readings are entered (read-only field)
6. The app auto-flags `is_out_of_range = true` when:
   - **Numeric**: reading is below `minimum_value` or above `maximum_value`
   - **Enum**: selected value is not in `enum_pass_options`
7. App snapshots active seedings in the site via `grow_task_seed_batch` (`status IN ('transplanted', 'harvesting')`)
8. Upload photos via `grow_task_photo` (one row per photo with optional caption)
9. Complete the activity

---

## Notes

- Monitoring snapshots which seedings are present in the site at the time of the event via `grow_task_seed_batch`.
- Monitoring station is a free-text field on `grow_monitoring_result.monitoring_station`.
- Each reading row stores the computed result for calculated points, providing a historical record even if the formula changes later.
- Out-of-range detection is automatic based on the point's thresholds. The frontend can highlight flagged readings.

---

## Flow Diagram

```mermaid
flowchart TD
    A[Create ops_task_tracker\nTask = Monitoring] --> A1[Assign employees\nvia ops_task_schedule]
    A1 --> B[Select site]
    B --> C[App loads monitoring points\nfor farm + site category]
    C --> D[Enter monitoring station name]
    D --> E[Enter readings per point]
    E --> F[App calculates derived values\nfrom formulas]
    F --> G[App flags out-of-range readings]
    G --> H{More stations?}
    H -->|Yes| D
    H -->|No| I[Snapshot active seedings\nvia grow_task_seed_batch]
    I --> J[Upload photos\nvia grow_task_photo]
    J --> K[Complete activity]
```
