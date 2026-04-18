# Cuke Plant-Map Data Incident — 2026-04-18

Dev plant-map rendered empty this morning and most grow-related tables in dev Supabase were 0 rows. I had added `grow_cuke_gh_row_planting` and `grow_cuke_seed_batch` to `_clear_transactional.py` when they should have been excluded — they're static (no nightly repopulator). The nightly TRUNCATE wiped them; 025's cycle-code → batch-uuid lookup returned empty; downstream grow tables cascaded to empty.

## What I changed

- **`_clear_transactional.py`** — removed `grow_cuke_gh_row_planting`, `grow_cuke_seed_batch`, and `grow_trial_type` from the TRUNCATE list (the last two are reference data, `legacy_trial` in particular was the FK target for 13 historical trial batches)
- **`sql/schema/20260418000001_grow_cuke_rotation.sql`** — new canonical rotation table (12 slots + 1 anchor) replacing the hardcoded `SIM_ORDER` in the plant-map dashboard
- **`sql/schema/20260418000002_drop_cuke_seed_batch_cascade_fks.sql`** — dropped the `ops_task_tracker_id` and `invnt_lot_id` FKs from `grow_cuke_seed_batch`. Removing the table from the TRUNCATE list wasn't enough; PG `TRUNCATE ... CASCADE` wipes every child of a truncated parent regardless of ON DELETE rules or actual row values. Columns stay nullable; no cuke data populates either
- **`sql/schema/20260418000003_seed_legacy_trial_type.sql`** — idempotent insert for `legacy_trial` so it exists and survives (retired 024 was reseeding it nightly)
- **`migrations/20260418000001_rebuild_cuke_seed_batch_and_planting.py`** — disaster-recovery rebuilder for the three static cuke tables. NOT in `DEFAULT_SET`
- **`migrations/20260401000025_grow_cuke_harvest.py`** — missing `pg_select_all` import (was failing nightly)

## Open items

1. **Migration 007 uses raw INSERT on `ops_template`.** Hits duplicate-key errors on re-run with `skip_clear=true`. Should be `upsert(on_conflict=id)`. Worth auditing 012-017, 019, 020, 031 for the same pattern.

2. **Nightly fail-fast amplifies one bug into a full grow wipe.** Consider `--continue-on-error` as default, or splitting cuke-dependent from lettuce-only migrations (027, 028, 030, 032) so a cuke issue doesn't take down lettuce data.

3. **Seed batch stub policy.** Yesterday's `grow_cuke_seed_batch` had 660 rows; today's rebuild produces 539. The ~120-row delta is pre-2026-04-17 auto-stub rows from old 025 (`ensure_stub_batches()`, sentinel `number_of_units=-1`). We killed that path on 2026-04-17. Good call — I'd rather fix the seeding sheet upfront than invent data.

4. **Should I have the Supabase DB password?** Today's rebuild required batching SQL via MCP's `execute_sql` because I only had service-key REST access. With psycopg2 access, the rebuilder is one command.

5. **Migration code duplication between `aloha-data-migrations` and `aloha-app`.** Already emailed you + Jean. Let's consolidate to this repo so Claude has one source of truth.
