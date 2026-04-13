# Grow Cuke Harvest Schedule Migration Design

## Overview

Migrate the `grow_C_harvest_sched` Google Sheet tab (~8,644 rows, Nov 30 2023 through Apr 13 2026) into `ops_task_tracker`. Each sheet row is one harvest crew session at one greenhouse on one date. After creating trackers, link them to the already-migrated `grow_harvest_weight` rows via the `ops_task_tracker_id` FK so queries can join labor to production.

**Source:** https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM (tab: `grow_C_harvest_sched`)

**Target:**
- `ops_task_tracker` (~8,644 inserted rows)
- `grow_harvest_weight` (UPDATE: set `ops_task_tracker_id` on matching rows)

## Prerequisites

- `ops_task` row with id `"harvesting"` exists (already seeded by `migrations/20260401000002_org.py`)
- `grow_harvest_weight` rows exist with `farm_id = 'cuke'` (migrated by `migrations/20260401000026_grow_cuke_harvest.py`)
- `ops_task_tracker.number_of_people` column exists (schema change already applied to `aloha-app/supabase/migrations/20260408000036_ops_task_tracker.sql`)

## Column Mapping

| Sheet column | Target column | Transform |
|---|---|---|
| `HarvestDate` + `ClockInTime` | `start_time` | Combine into timestamp |
| `HarvestDate` + `ClockOutTime` | `stop_time` | Combine into timestamp |
| `Greenhouse` | `site_id` | `normalize_gh` (`"1"` -> `"01"`, `"HI"` -> `"hi"`) |
| `NumberOfPeople` | `number_of_people` | Nullable int; many rows are empty |
| `ReportedBy` | `created_by` / `updated_by` | Email or `AUDIT_USER` fallback |
| — | `org_id` | `ORG_ID` |
| — | `farm_id` | `"cuke"` |
| — | `ops_task_id` | `"harvesting"` |
| — | `is_completed` | `true` |
| — | `notes` | `"Legacy harvest schedule migration"` (marker for rerun identification) |

**Columns not stored:**
- `Year`, `Month`, `ISOYear`, `ISOWeek`: derivable from `start_time`
- `Hours`: derivable from `stop_time - start_time`
- `GreenhouseNetWeight`, `GradeOneNetWeight`: derivable from `SUM(grow_harvest_weight.net_weight)` grouped by (date, site_id)
- `GreenhousePoundsPerHour`, `GradeOnePoundsPerHour`: derivable from net_weight / hours
- `EntryID`: not needed (UUID is the PK)

These will be surfaced via a view in a separate task.

## Timestamp Construction

The sheet has dates like `"11/30/2023"` and times like `"7:00:00 AM"` or `"3:23:34 PM"` without timezone. We store as UTC timestamps. Combination:

```
start_time = parse_date(HarvestDate) + parse_time(ClockInTime)
stop_time  = parse_date(HarvestDate) + parse_time(ClockOutTime)
```

If `stop_time < start_time` (clock out on next day, rare), skip the row as malformed.

## Linking to grow_harvest_weight

After all trackers are inserted, for each tracker:

```sql
UPDATE grow_harvest_weight
SET ops_task_tracker_id = :tracker_id
WHERE farm_id = 'cuke'
  AND harvest_date = :tracker_start_date
  AND site_id = :tracker_site_id
  AND ops_task_tracker_id IS NULL;  -- don't overwrite earlier links
```

The `IS NULL` guard ensures the **earliest tracker wins** when multiple schedule sessions share the same (date, greenhouse) — sort the updates by `start_time` ASC so the first session claims the weigh-ins, and subsequent sessions at the same site find no unlinked rows to update.

## Skip Conditions

A sheet row is skipped and counted when:
- No parseable `HarvestDate`
- No parseable `ClockInTime`
- No `ClockOutTime` OR `stop_time < start_time` (malformed)
- Unknown `Greenhouse` (not in `org_site`)

The `NumberOfPeople` being empty is NOT a skip condition — it's stored as `NULL`.

## Rerunnability

**Clear phase:** identify our trackers by the marker:
- `ops_task_id = 'harvesting'`
- `farm_id = 'cuke'`
- `notes = 'Legacy harvest schedule migration'`

Process:
1. Query our tracker UUIDs
2. `UPDATE grow_harvest_weight SET ops_task_tracker_id = NULL WHERE ops_task_tracker_id IN (:our_tracker_ids)`
3. `DELETE FROM ops_task_tracker WHERE id IN (:our_tracker_ids)`

This preserves any non-migration harvesting trackers (e.g., future app-created ones).

## Execution Order

1. Run this migration: `python migrations/20260401000027_grow_cuke_harvest_sched.py`
2. No other ordering dependencies (harvest_weight already migrated; ops_task already seeded)

## File

`migrations/20260401000027_grow_cuke_harvest_sched.py`

Structure follows `20260401000026_grow_cuke_harvest.py`:
- Shared helpers from `_config.py` + local helpers (`audit`, `insert_rows`, `get_sheets`, `parse_date`, `normalize_gh`, new `parse_time`, new `combine_datetime`)
- Constants: `FARM_ID`, `OPS_TASK_ID`, `TRACKER_NOTE_MARKER`
- Clear phase: unlink + delete our trackers
- Load phase: read sheet, get known_sites, build tracker rows
- Insert phase: batch insert 100 at a time
- Link phase: update grow_harvest_weight in batches, earliest-first
- Report: skipped counts, link counts

## Expected Output

- ~8,644 `ops_task_tracker` rows inserted
- Some weigh-ins from Nov 2023 onward get `ops_task_tracker_id` populated
- Pre-Nov 2023 weigh-ins remain `ops_task_tracker_id = NULL` (no schedule data exists)
- Idempotent on re-run
