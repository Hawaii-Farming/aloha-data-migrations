# Cuke Plant-Map Data Incident — 2026-04-18

Audience: Michael. Written by Lenny + Claude after working the issue end-to-end.

---

## What happened

Lenny opened the dev plant-map dashboard and it rendered empty: `0 greenhouses, 0 rows, 0 plants`. Sheets-mode rendered fine. That surfaced a much bigger problem: most of the grow-related transactional tables in dev Supabase were empty too.

## Root cause

A chain of three things compounding:

1. **`_clear_transactional.py` was truncating static tables with no re-populator.** The TABLES list included `grow_cuke_gh_row_planting` and `grow_cuke_seed_batch`. These are populated by the one-time `20260417000001_cuke_plantmap.py` seeder and have no nightly repopulator. The nightly TRUNCATE wiped them clean.

2. **Migration 025 (`grow_cuke_harvest`) depends on `grow_cuke_seed_batch` for its cycle-code → batch-uuid lookup.** With an empty `grow_cuke_seed_batch`, 025's `build_batch_lookup()` returns an empty map, every harvest row hits "unmatched_batch", and the migration inserts zero rows.

3. **`_run_nightly.py` fail-fast stops the chain.** After 025 silently produces nothing, 026-034 still run, but 025's empty state cascaded through the dashboard-critical tables: `grow_harvest_weight` (0 rows), `grow_lettuce_seed_batch` (0, via 027), `grow_fertigation*` (0, via 028), `grow_monitoring_result` (0, via 032), `grow_scout_result`, `grow_spray_*`, `fin_expense`. Some of these were 025's own deletes running before 025 failed to re-insert; some were nightly scripts silently skipping because of missing dependencies. Either way, every table that had been populated from sheets the night before was empty the next morning.

Had the fix not landed today, this would have recurred on every subsequent nightly run.

## Fixes applied (dev only; prod is untouched)

### `dcf789f` — first pass

1. **`_clear_transactional.py`** — removed `grow_cuke_gh_row_planting` and `grow_cuke_seed_batch` from the TABLES list. Added a comment explaining why.
2. **`sql/schema/20260418000001_grow_cuke_rotation.sql`** — new canonical table for the cuke seeding rotation (12 slots, one anchor). Replaces the hardcoded `SIM_ORDER` array in `dash/plant-map/index.html`. Schema:
   - 12 rows, one per rotation slot
   - `site_id` FK to `org_site(id)` (HK pair uses one row, site_id='hk')
   - `is_anchor` boolean, exactly one row must have it true (CHECK constraint)
   - `anchor_week_start` date, required on anchor row, forbidden otherwise
3. **`migrations/20260418000001_rebuild_cuke_seed_batch_and_planting.py`** — disaster-recovery rebuilder. Upserts `grow_cuke_rotation`, rebuilds `grow_cuke_gh_row_planting` (1320 rows) and `grow_cuke_seed_batch` (historical from sheet + forward 156 from rotation math). NOT in `_run_nightly.py` DEFAULT_SET.

### Why the first pass wasn't sufficient

`grow_cuke_seed_batch` still has FKs to parents that are in the TRUNCATE list:

| FK from `grow_cuke_seed_batch` | → references | In TRUNCATE list? |
|---|---|---|
| `ops_task_tracker_id` | ops_task_tracker | yes |
| `grow_trial_type_id` | grow_trial_type | yes |
| `invnt_lot_id` | invnt_lot | yes |

PostgreSQL `TRUNCATE ... CASCADE` wipes every child table with an FK to a truncated parent, **regardless of the FK's ON DELETE rule and regardless of whether any rows actually reference it**. So removing `grow_cuke_seed_batch` from the TABLES list doesn't help — it gets reached transitively through these three parents.

### Second pass — break the CASCADE chain

1. **`sql/schema/20260418000002_drop_cuke_seed_batch_cascade_fks.sql`** — drops the FKs from `grow_cuke_seed_batch.ops_task_tracker_id` and `grow_cuke_seed_batch.invnt_lot_id`. Both columns remain (nullable), but no longer carry FK enforcement. No cuke seed-batch row populates either column today, so the FK was cosmetic. This severs the CASCADE path from those two parents.
2. **`_clear_transactional.py`** — also removed `grow_trial_type` from the TRUNCATE list. It's reference data (13 historical cuke trial batch rows reference it), retired migration 024 was the only thing reseeding `'legacy_trial'`, and truncating it CASCADE-wipes grow_cuke_seed_batch via the trial-type FK.
3. **`sql/schema/20260418000003_seed_legacy_trial_type.sql`** — inserts the `legacy_trial` row into `grow_trial_type` (idempotent `on conflict do nothing`). This is the row that retired migration 024 used to recreate nightly via `ensure_trial_type()`; now it's a one-time seed that survives because `grow_trial_type` is no longer in the TRUNCATE list.

After these passes, the CASCADE path into `grow_cuke_seed_batch` is broken, `legacy_trial` exists and persists, and the `dcf789f` exclusion actually protects the data.

### Data rebuilt in dev (via MCP + a local urllib-based variant of the rebuilder)

- `grow_cuke_rotation` — 12 slots populated, GH2 anchor at 2026-03-15
- `grow_cuke_gh_row_planting` — 1,320 rows rebuilt from Plant-Map sheet
- `grow_cuke_seed_batch` — 695 rows rebuilt (539 historical from grow_C_seeding + 156 forward from rotation + plant-map-planned-scenario)

All downstream tables (`grow_harvest_weight`, `grow_lettuce_seed_batch`, `grow_fertigation*`, `grow_monitoring_result`, etc.) are populated by tonight's scheduled nightly, or by a `workflow_dispatch` run with `skip_clear=false` that Lenny can fire on demand.

## Items to resolve — discussion (not session-blocking)

**1. Migration 007 uses raw INSERT on `ops_template`.** Hit duplicate-key errors when run with `skip_clear=true`. Should be `upsert(on_conflict=id)`. Audit other ref-data migrations (012-017, 019, 020, 031) for the same pattern.

**2. Nightly fail-fast turns one bug into a full grow-table wipe.** Consider `--continue-on-error` as default, or isolate the cuke-dependent chain from lettuce-only migrations (027, 028, 029, 030, 032) so a cuke issue doesn't take down lettuce data. This is what happened yesterday.

**3. Seed batch stub policy.** Yesterday's seed batch count was 660 historical; today's rebuild produces 539. The ~120-row delta is pre-2026-04-17 auto-generated stub rows from old 025 (`ensure_stub_batches()` with sentinel values `number_of_units = -1`, back-derived dates, note = "Stub: auto-created by harvest migration"). We killed this path on 2026-04-17 and Lenny is glad we did. He'd rather not copy them over — prefer fixing the seeding sheet to match harvest data upfront so unmatched cycles become loggable discrepancies, not invented data.

**4. Why are `grow_harvest_container` rows defined the way they are?** Currently hardcoded pallet types like `pallet_k1`, `pallet_j2`, etc. per variety+grade combo. Worth discussing why we're not porting over `# boards` (or the cuke-side equivalent metric) as first-class data on each harvest record. What's the rationale for the current shape?

**5. Does Lenny need the Supabase DB password?** Today he was limited to service-key writes through the REST API. For the rebuild that meant generating SQL files locally and pasting each 150-row batch into MCP's `execute_sql` one at a time. With direct psycopg2 access, the rebuild is one command: `python migrations/20260418000001_rebuild_cuke_seed_batch_and_planting.py`. The `/tmp` batch-file scratch directory only exists because of this limitation. What's the right way to get direct DB access?

**6. Migration code duplication between `aloha-data-migrations` and `aloha-app`.** Lenny emailed Michael and Jean about pulling this out of `aloha-app` — in the spirit of "everything we do is Claude-first," the migration code shouldn't have two homes. The duplication is confusing Claude and complicating the work; it probably complicates Michael's work too. What's the path to making `aloha-data-migrations` the single source of truth?

## Files added or changed today

```
migrations/_clear_transactional.py                                       (modified — two passes)
migrations/20260418000001_rebuild_cuke_seed_batch_and_planting.py        (new)
migrations/20260401000025_grow_cuke_harvest.py                           (modified — missing `pg_select_all` import)
sql/schema/20260418000001_grow_cuke_rotation.sql                         (new)
sql/schema/20260418000002_drop_cuke_seed_batch_cascade_fks.sql           (new)
sql/schema/20260418000003_seed_legacy_trial_type.sql                     (new)
```
