# Grow Cuke Harvest Migration Design

## Overview

Migrate the `grow_C_harvest` Google Sheet tab (~4,872 rows) into `grow_harvest_weight`, linking each weigh-in back to its seed batch. Also introduces formula-based tare calculation on `grow_harvest_container`, following the same pattern as `grow_monitoring_metric.formula`.

**Source:** https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM (tab: `grow_C_harvest`)

**Target tables:**
- `grow_harvest_container` (6 upserted rows — pallet per variety+grade)
- `grow_harvest_weight` (~4,872 inserted rows)

## Part 1: Schema Change (aloha-app)

Add formula support to `grow_harvest_container` so tare weight can be dynamically calculated from gross weight at weigh-in time, rather than being a single fixed value.

### Columns to add

```sql
is_tare_calculated   BOOLEAN NOT NULL DEFAULT false,
tare_formula         TEXT,
tare_formula_inputs  JSONB,
```

### Column to alter

```sql
tare_weight  NUMERIC  -- change from NOT NULL to nullable (NULL when formula-based)
```

### Rationale

The legacy tare calculation uses a linear regression per variety+grade combination where tare depends on gross weight. The existing fixed `tare_weight` column cannot express this. Adding `tare_formula` follows the established `grow_monitoring_metric` pattern where formulas are stored as text and evaluated by the app layer.

### Where

Edit the existing `grow_harvest_container` migration file in `aloha-app/supabase/migrations/` (pre-production, so edit in place per workflow). Then sync schema-reference.

## Part 2: Container Setup (6 rows)

Upsert 6 `grow_harvest_container` rows — one pallet definition per variety+grade combination. Each stores its tare regression formula.

| id | name | grow_variety_id | grow_grade_id | weight_uom | tare_weight | is_tare_calculated | tare_formula |
|---|---|---|---|---|---|---|---|
| `pallet_k1` | Pallet | k | on_grade | pound | NULL | true | `ROUND(0.0316203631692461 * gross_weight + -0.835015982812408) * 3 + 48` |
| `pallet_k2` | Pallet | k | off_grade | pound | NULL | true | `ROUND(0.0285084470508113 * gross_weight + 0.38656882092243) * 3` |
| `pallet_e1` | Pallet | e | on_grade | pound | NULL | true | `ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48` |
| `pallet_e2` | Pallet | e | off_grade | pound | NULL | true | `ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3` |
| `pallet_j1` | Pallet | j | on_grade | pound | NULL | true | `ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48` |
| `pallet_j2` | Pallet | j | off_grade | pound | NULL | true | `ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3` |

Note: J1/E1 share identical coefficients, as do J2/E2.

## Part 3: Data Migration

### Source sheet columns

| Column | Used | Notes |
|---|---|---|
| `HarvestDate` | yes | Parsed as date |
| `Year`, `Month`, `ISOYear`, `ISOWeek` | no | Derivable from HarvestDate |
| `HarvestDay` | no | Days into cycle, not needed |
| `Greenhouse` | yes | Normalized to site_id (`"1"` -> `"01"`, `"HI"` -> `"hi"`) |
| `Variety` | yes | `E`, `K`, `J` — used for container + batch lookup |
| `Grade` | yes | `1` -> `on_grade`, `2` -> `off_grade` |
| `SeedingCycle` | yes | Links to grow_seed_batch via batch_code |
| `PalletWeight` | yes | gross_weight; `-1` sentinel when empty |
| `GreenhouseNetWeight` | yes | net_weight |
| `is_trial` | yes | Determines `P` vs `T` batch_code suffix |
| `trial_seed_name_lot` | no | Not needed for harvest weight records |
| `ReportedDateTime` | no | Not mapped (no timestamp column on target) |
| `ReportedBy` | yes | Used for created_by / updated_by |

### Column mapping

| Target column | Source / transform |
|---|---|
| `org_id` | `ORG_ID` constant |
| `farm_id` | `"cuke"` |
| `site_id` | `normalize_gh(Greenhouse)` |
| `ops_task_tracker_id` | `NULL` |
| `grow_seed_batch_id` | Lookup: `batch_code = SeedingCycle + "P"` (or `"T"` when `is_trial = TRUE`) -> UUID |
| `grow_grade_id` | `"on_grade"` if Grade=1, `"off_grade"` if Grade=2 |
| `harvest_date` | `parse_date(HarvestDate)` |
| `grow_harvest_container_id` | `"pallet_{variety_lower}{grade}"` (e.g., `pallet_k1`) |
| `number_of_containers` | `1` |
| `weight_uom` | `"pound"` |
| `gross_weight` | `parse_numeric(PalletWeight)`, or `-1` if empty |
| `net_weight` | `parse_numeric(GreenhouseNetWeight)` |
| `created_by` | `ReportedBy` email (or `AUDIT_USER` if not an email) |
| `updated_by` | same as created_by |

### Seed batch lookup

Build a dict of `batch_code -> id` from `grow_seed_batch` where `farm_id = 'cuke'`. For each harvest row:
- If `is_trial` is FALSE: look up `{SeedingCycle}P`
- If `is_trial` is TRUE: look up `{SeedingCycle}T` (fall back to `{SeedingCycle}T2`, `{SeedingCycle}T3` if needed)

Rows with no matching seed batch are skipped and reported.

### Rerunnability

Delete all `grow_harvest_weight` rows where `farm_id = 'cuke'` before reinserting.

### Skip conditions

- No parseable `HarvestDate`
- No `GreenhouseNetWeight` (or zero)
- Unknown greenhouse (not in `org_site`)
- Unmatched seed batch (no batch_code found)

### Execution order

1. Schema change in aloha-app (Part 1)
2. Sync schema-reference
3. Run `20260401000025_grow_cuke_seeding.py` (seed batches must exist)
4. Run `20260401000026_grow_cuke_harvest.py` (this migration)

### File

`migrations/20260401000026_grow_cuke_harvest.py`

Follows the same structure as `20260401000025_grow_cuke_seeding.py`:
- Shared helpers from `_config.py` + common functions (audit, insert_rows, get_sheets, parse_date, parse_int, normalize_gh)
- Constants: FARM_ID, GRADE_MAP, CONTAINER_MAP
- Setup phase: upsert containers
- Clear phase: delete existing harvest weights
- Load phase: read sheet, build batch lookup
- Transform phase: map rows, skip invalids
- Insert phase: batch 100 at a time
- Report phase: skipped rows, unmatched batches, totals

### Expected output

- ~4,872 `grow_harvest_weight` rows
- 6 `grow_harvest_container` rows (upserted)
- Skipped rows reported (no date, no weight, unknown site, unmatched batch)
