# Cuke Schema Split — 2026-04-17 Update for Michael

Status: **deployed to dev (`kfwqtaazdankxmdlqdak`).** Not deployed to prod yet.

---

## What changed

### Schema

Separated cuke from lettuce in `grow_seed_batch`. The old shared table is now **lettuce-only**, and cuke gets its own table plus four layout tables for the plant-map.

**New tables (all in dev):**

| Table | Purpose | Rows in dev |
|---|---|---|
| `org_site_gh` | Per-greenhouse display config (orientation, sidewalk, grid layout) | 12 |
| `org_site_gh_block` | Block definitions per GH (row ranges + display name like North/Middle/South/Hamakua/Kohala) | 23 |
| `org_site_gh_row` | Every physical GH row with bag capacity | 660 |
| `grow_cuke_seed_batch` | Cuke seeding events — replaces the cuke subset of `grow_seed_batch` | 660 (historical migrated) |
| `grow_cuke_gh_row_planting` | Which variety is in each row (current + planned scenarios) | 1,320 (660 current + 660 planned) |

**Renamed:** `grow_seed_batch` → `grow_lettuce_seed_batch` (5,731 rows, all lettuce).

**FK splits** (on `grow_harvest_weight` and `grow_task_seed_batch`):
- Dropped the single `grow_seed_batch_id` column
- Added `grow_lettuce_seed_batch_id` and `grow_cuke_seed_batch_id` (each nullable)
- CHECK constraint enforces exactly one populated
- Cuke harvests/tasks now FK to `grow_cuke_seed_batch`; lettuce stays on the renamed lettuce table

**FK verification:**
- `grow_harvest_weight`: 4,957 lettuce + 62,181 cuke, 0 orphans
- `grow_task_seed_batch`: 51,313 lettuce + 34,972 cuke, 0 orphans

### Cuke seed batch — what changed from the old shared table

| Field | Before | After |
|---|---|---|
| `batch_code` | stored as `YYMM{GH}{V}{P\|T}` | **removed** — derived on the fly from other fields when matching |
| `grow_variety_id` | absent (had to infer from `invnt_item_id`) | **not stored here either** — kept derivable via `invnt_item.grow_variety_id`; variety only lives on `grow_cuke_gh_row_planting` |
| `grow_cycle_pattern_id` | null for all cuke | **dropped** |
| `grow_seed_mix_id` | null for all cuke (cuke never mixes) | **dropped** |
| `seeding_uom` | always `'bag'` for cuke | **dropped** |
| `number_of_units × seeds_per_unit` | two columns | **rolled into one `seeds` column** |
| `number_of_rows` | always `-1` sentinel for cuke | **dropped** |
| `estimated_harvest_date` | required but dummy-valued for cuke | **dropped** |
| — | | `rows_4_per_bag`, `rows_5_per_bag` snapshot fields (fixed at seeding time from plant-map) |
| — | | `next_bag_change_date` |

### Nightly sync changes

| Script | Status | Reason |
|---|---|---|
| `024_grow_cuke_seeding.py` | **Removed from nightly** | Cuke seed batches are now static-ish; sheet no longer source of truth for cuke cycles |
| `025_grow_cuke_harvest.py` | Kept in nightly, rewritten | Derives cycle code `{YY}{MM}{GH}{VARIETY}` + is_trial to find cuke batch. **Stub-creation path removed** — see question below |
| `026_grow_cuke_harvest_sched.py` | Kept in nightly | No seed-batch linkage; no changes needed |
| `027_grow_lettuce_seeding.py` | Updated | Targets renamed `grow_lettuce_seed_batch` + `grow_lettuce_seed_batch_id` |
| `028/029/030/032` | Updated | Write to the correct `*_seed_batch_id` column based on `farm_id` |
| `033_business_rule.py` | Updated | Text references for rule targets |

### Data fixes applied during migration

- **GH5 row 43**: appeared under both Middle and South in the sheet. Kept in South (per migration plan); dropped from Middle. Middle now 23–42, South 43–63.
- **3 "Mixed" rows** (GH3 South row 40, GH3 South row 49, Kona West row 55): interpreted as Keiki + Japanese 50/50 split in the current scenario, per your direction.
- **HK**: handled via row-num offset (see open question #1).

### Commits

- `aloha-data-migrations@c60d004` — initial cuke split (schema, seeder, script edits)
- `aloha-data-migrations@3619997` — derived cycle code, un-retire 025/026, HK dual-structure via block name
- `dash@cea8c15` — retired the design doc `docs/cuke-seeding-schema.md`

---

## Open questions for you

### 1. HK — one `org_site` with two physical structures

**Current situation.** `org_site.id = 'hk'` represents both Hamakua and Kohala greenhouses. Plant-map sheet has them as two separate GHs with overlapping row numbers (Hamakua 1–40, Kohala 1–24).

**Our workaround:**
- `org_site_gh`: one row for `hk`
- `org_site_gh_row`: Hamakua rows keep their row_num (1–40). Kohala rows are offset by +100 (stored as 101–124) to avoid collision on the unique `(site_id, row_num)` constraint.
- `org_site_gh_block`: two blocks under `hk` — `name='Hamakua'` (1–40) and `name='Kohala'` (101–124). Plant-map UI will read the block name to render each as a labelled section.

**Do you want to make HK into two separate `org_site` rows** (`hamakua` and `kohala`)? If yes, we'd do a cleanup migration later: create the two new sites, move rows/blocks/planting under them, update historical `grow_seed_batch` and downstream FKs. Not urgent but cleaner long-term.

### 2. 025 cuke harvest — stub seed batches

The previous version of the cuke-harvest script (`20260401000025_grow_cuke_harvest.py`) auto-created stub rows in `grow_seed_batch` whenever a harvest record referenced an unknown seeding cycle (function `ensure_stub_batches`). **We removed that path.** Unmatched cycles are now just logged and the harvest weigh-in is skipped.

The rationale: a harvest record referencing an unknown cycle usually means the seeding source is incomplete, not that a real seeding happened that we didn't know about. Inventing seed-batch rows from harvest data masked data-entry errors.

**Please confirm** this is the right call, or if there's a legitimate case where harvests exist without a corresponding seeding event we should track.

### 3. Plant-map dashboard still reads from the Sheet

`dash/plant-map/index.html` still fetches via gviz from the plant-map Google Sheet. Separate workstream to point it at Supabase (new `dash/lib/data-source.js`, toggle UI, write path via edge function). Schema is now ready for it — just not wired up.

Until the UI points at Supabase, any edits made in the plant-map dashboard write to the sheet, not to `grow_cuke_gh_row_planting`. **Don't rely on the Supabase layout tables being accurate until the UI rewrite is done** — they reflect a one-time snapshot at 2026-04-17.

### 4. Future cuke seedings — just started

You asked us to forward-load 52 weeks of cuke seedings into `grow_cuke_seed_batch`. This is in progress but not yet inserted.

Approach (per your direction):
- Rotation per `SIM_ORDER` in plant-map (12-week cycle, one GH per week)
- Anchor: GH2 seeds week of 2026-03-15
- Variety allocation uses the `planned` scenario in `grow_cuke_gh_row_planting`
- Skip past dates
- HK gets one row per variety per cycle (not two)
- Status = `'planned'`
- `next_bag_change_date` from the sheet's bag_changes tab per GH
- `invnt_item_id` defaults: k→`delta_star_minis_rz`, j→`f1_tsx_cu235jp_tokita`, e→`english`

Will produce ~140 new rows (12 GHs × 3 varieties × ~4 cycles in a year).

### 5. Production deploy

Dev is deployed and verified. Prod (`zdvpqygiqavwpxljpvqw`) is untouched. Repeating the same sequence there when you're ready is safe — same SQL files in `aloha-data-migrations/sql/schema/`, same Python seeder logic (this time runnable locally once credentials are set up, or we repeat the MCP-driven flow we used for dev).

### 6. Minor cosmetic cleanup

After the rename, `pack_dryer_result.grow_seed_batch_id` column still bears the old name but now FKs to `grow_lettuce_seed_batch(id)` (PostgreSQL auto-followed the table rename). Column is correct, name is stale. Harmless. Would rename to `grow_lettuce_seed_batch_id` in a future tidy-up if you want.

---

## Files and locations

**Schema SQL** (`aloha-data-migrations/sql/schema/`):
```
20260417000001_org_site_gh.sql
20260417000002_org_site_gh_block.sql
20260417000003_org_site_gh_row.sql
20260417000004_grow_cuke_seed_batch.sql
20260417000005_grow_cuke_gh_row_planting.sql
20260417000006_rename_grow_seed_batch.sql
20260417000007_split_grow_harvest_weight_batch_fk.sql
20260417000008_split_grow_task_seed_batch_fk.sql
20260417000009_delete_cuke_from_grow_lettuce_seed_batch.sql
```

**Module schema docs** (`aloha-data-migrations/docs/schemas/`):
```
20260401000002_org.md        (3 new org_site_gh* table sections appended)
20260401000006_grow.md       (grow_seed_batch renamed, 2 new cuke sections, Notes for Michael section)
```

**Python seeder + edits** (`aloha-data-migrations/migrations/`):
```
20260417000001_cuke_plantmap.py   (one-time, layout + cuke seed batch copy)
_run_nightly.py                   (024 removed; 025/026/027 configured)
_clear_transactional.py           (new cuke tables + renamed lettuce table)
20260401000025_grow_cuke_harvest.py  (rewritten matching)
20260401000027_grow_lettuce_seeding.py  (target table + column rename)
20260401000032_grow_monitoring.py  (farm_id-aware writes)
20260401000033_business_rule.py    (text references)
```

---

## Suggested next steps

1. **Answer the open questions** above — especially #1 (HK split) and #2 (stub policy)
2. **Finish forward seedings** — I can proceed once you confirm the approach in Q4
3. **Test nightly on dev** — let 025/026/027/028/029/030/032 run once and verify no errors
4. **Plan prod deployment** — same SQL sequence against `zdvpqygiqavwpxljpvqw`
5. **Plant-map UI rewrite** — separate workstream, depends on design decisions around the toggle, edge function for variety edits, etc.
