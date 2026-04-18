# Cuke Plant-Map Data Incident — 2026-04-18

The nightly migration failed for some tables. Part was my own issues — fixed, notes below. The rest seems unrelated to my recent changes. Can you address these?

## What I changed (fixed)

- **`_clear_transactional.py`** — removed `grow_cuke_gh_row_planting`, `grow_cuke_seed_batch`, and `grow_trial_type` from the TRUNCATE list. The last two are reference data; `legacy_trial` in particular is the FK target for 13 historical trial batches.
- **`sql/schema/20260418000001_grow_cuke_rotation.sql`** — new canonical rotation table (12 slots + 1 anchor) replacing the hardcoded `SIM_ORDER` in the plant-map dashboard.
- **`sql/schema/20260418000002_drop_cuke_seed_batch_cascade_fks.sql`** — dropped the `ops_task_tracker_id` and `invnt_lot_id` FKs from `grow_cuke_seed_batch`. They were pulling the table into TRUNCATE CASCADE from parents in the TRUNCATE list, wiping 695 rows every nightly. Columns stay nullable; no cuke data populates either.
- **`sql/schema/20260418000003_seed_legacy_trial_type.sql`** — idempotent insert for `legacy_trial` so it exists once and survives (retired 024 was reseeding it).
- **`migrations/20260418000001_rebuild_cuke_seed_batch_and_planting.py`** — disaster-recovery rebuilder for the three static cuke tables. NOT in `DEFAULT_SET`.
- **`migrations/20260401000025_grow_cuke_harvest.py`** — two fixes: missing `pg_select_all` import, and double-appending variety to `SeedingCycle` (the cycle in the harvest sheet already carries `YYMM{GH}{V}`, so appending `V` again produced unmatched keys like `2602HKJJ`).
- **`migrations/20260401000032_grow_monitoring.py`** — skip unmatched seed_batch_ids before insert; they were violating `chk_grow_task_seed_batch_exactly_one`.

## Can you address these?

1. **Migration 007 uses raw `INSERT` on `ops_template`.** Pre-existing. Hits duplicate-key errors on re-run with `skip_clear=true`. Should be `upsert(on_conflict=id)`. Worth auditing 012-017, 019, 020, 031 for the same pattern.

2. **Nightly fail-fast turns one bug into a full grow wipe.** Pre-existing in `_run_nightly.py`. When one migration fails, every downstream one is skipped entirely — today that meant a bug in 032 (monitoring) prevented 033 and 034 from ever running. Consider `--continue-on-error` as default, or splitting cuke-dependent from lettuce-only migrations so a cuke issue doesn't take down lettuce data.

3. **Migration code duplication between `aloha-data-migrations` and `aloha-app`.** I emailed you and Jean earlier — following up here. In the Claude-first workflow, the migration code should have one home so Claude isn't confused by two sources of truth.
