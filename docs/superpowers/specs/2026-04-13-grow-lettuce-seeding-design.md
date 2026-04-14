# Grow Lettuce Seeding Migration Design

## Overview

Migrate `grow_L_seeding` Google Sheet tab (~5,000 rows, Feb 2024 through Mar 2026) into `grow_seed_batch` and `grow_harvest_weight`. Unlike cuke (which split seeding and harvest across tabs), each lettuce sheet row contains a complete cycle — seed + pond + harvest — in one row.

**Source:** https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM (tab: `grow_L_seeding`)

**Target:**
- `grow_seed_batch` (~5,000 inserted)
- `grow_harvest_weight` (~(5000 minus in-progress) inserted)
- Setup tables upserted: `grow_harvest_container` (1 row), `grow_trial_type` (few), `grow_cycle_pattern` (few), `invnt_item` (auto-created), `invnt_lot` (auto-created)

**File:** `migrations/20260401000028_grow_lettuce_seeding.py`

## Setup Phase (upserted)

### grow_harvest_container — "board"

One row, used for all lettuce harvests:

| Field | Value |
|---|---|
| id | `board` |
| farm_id | `lettuce` |
| name | `Board` |
| weight_uom | `pound` |
| tare_weight | `0` |
| is_tare_calculated | `false` |
| grow_variety_id | NULL |
| grow_grade_id | NULL |

### grow_trial_type — per unique `trialtype`

One row per unique value in the sheet's `trialtype` column, e.g. `lettuce_new_varieties`.

### grow_cycle_pattern — per unique `harvestdayspattern`

One row per unique value in `harvestdayspattern` (mostly empty currently).

### invnt_item — auto-create missing seeds

For each unique `seedname` in the sheet:
1. Skip if name matches an existing `grow_seed_mix.name` (mix handled separately)
2. Lookup in `invnt_item` by case-insensitive exact match on `name` (farm=lettuce, category=seeds)
3. If not found, auto-create with:
   - `id`: slug of seedname
   - `name`: seedname
   - `grow_variety_id`: from sheet's `variety` column (gb/gl/rl/ga)
   - `farm_id`: `lettuce`, `invnt_category_id`: `seeds`
   - Standard boilerplate (seed/pack UOMs, burn per order, not palletized)

### invnt_lot — auto-create missing lots

For each unique `(seedname, seedlot)` pair where `seedlot` is non-blank:
1. Lookup by `(invnt_item_id, lot_number)`
2. If not found, auto-create with:
   - `id`: slug of `{seedname}_{seedlot}` (dots/spaces → underscores)
   - `lot_number`: raw `seedlot` value
   - `invnt_item_id`: looked up item
   - `farm_id`: `lettuce`

## Per-row Mapping

### grow_seed_batch

| Target | Source | Transform |
|---|---|---|
| `id` | pre-generated `uuid.uuid4()` | for linking to harvest_weight |
| `org_id` | — | `hawaii_farming` |
| `farm_id` | — | `lettuce` |
| `site_id` | `pond` | lowercase (`P1` → `p1`) |
| `batch_code` | `seedingcycle` | verbatim |
| `invnt_item_id` **XOR** `grow_seed_mix_id` | `seedname` | if name matches a mix → `grow_seed_mix_id`; else → `invnt_item_id` |
| `invnt_lot_id` | `(seedname, seedlot)` | NULL if seedlot blank or mix |
| `grow_trial_type_id` | `trialtype` if `istrial=true` | NULL otherwise |
| `grow_cycle_pattern_id` | `harvestdayspattern` | NULL if empty |
| `seeding_uom` | — | `"board"` |
| `number_of_units` | `boardsperpond` | int, `-1` if empty |
| `seeds_per_unit` | `seedsperboard` | int, `-1` if empty |
| `number_of_rows` | `rowspercycle` | int, `-1` if empty |
| `seeding_date` | `seedingdate` | required |
| `transplant_date` | `ponddate` | fallback: `seedingdate + 2 days` |
| `estimated_harvest_date` | `expectedharvestdate` | fallback: `seedingdate + 21 days` |
| `status` | `cyclestatus` | map: `Harvested` → `harvested`; `Harvesting` → `harvesting`; `Pre-harvesting` → `transplanted`; default `harvested` |
| `notes` | `notes` | appended with marker: `"Legacy lettuce migration"` (used for rerun cleanup) |
| `created_by` / `updated_by` | `reportedby` | email or AUDIT_USER |

### grow_harvest_weight (only when harvestdate AND greenhousenetweight both populated)

| Target | Source | Transform |
|---|---|---|
| `org_id` | — | `hawaii_farming` |
| `farm_id` | — | `lettuce` |
| `site_id` | `pond` | same as seed_batch |
| `grow_seed_batch_id` | seed_batch.id | pre-generated UUID from the batch above |
| `harvest_date` | `harvestdate` | |
| `grow_harvest_container_id` | — | `"board"` |
| `number_of_containers` | — | `1` (representative board) |
| `weight_uom` | — | `"pound"` |
| `net_weight` | `greenhousenetweight` | |
| `gross_weight` | `greenhousenetweight` | same value — tare is 0 |
| `grow_grade_id` | — | NULL (no grade split) |
| `ops_task_tracker_id` | — | NULL |
| `created_by` / `updated_by` | `reportedby` | |

## Skip Conditions (seed_batch)

- No parseable `seedingdate`
- No `pond` (or not in `org_site`)
- No `seedname`
- No `seedingcycle` (batch_code)

No skip on missing `harvestdate` — cycle just gets a seed_batch without harvest_weight.

## Rerunnability

Identify our rows by notes marker `"Legacy lettuce migration"`. Via psycopg2 in one transaction:

1. `DELETE grow_harvest_weight WHERE grow_seed_batch_id IN (SELECT id FROM grow_seed_batch WHERE notes LIKE '%Legacy lettuce migration%' AND farm_id='lettuce')`
2. `DELETE grow_seed_batch WHERE notes LIKE '%Legacy lettuce migration%' AND farm_id='lettuce'`

## Performance

Use `_pg.py` helpers:
- `paginate_select` for `invnt_item` (186 rows, near cap)
- `pg_bulk_insert` for ~5k seed_batch + ~5k harvest_weight in single transaction

## Expected Output

- 1 harvest_container row (board)
- 1-3 trial type rows
- 0-few cycle pattern rows
- Few dozen auto-created invnt_item + invnt_lot rows
- ~5,000 grow_seed_batch rows
- ~4,500-5,000 grow_harvest_weight rows (minus any in-progress cycles)
- Runtime: <1 min

Idempotent on re-run.
