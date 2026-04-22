# Cuke Schema Split — 2026-04-17 Update for Michael

Status: **deployed to dev (`kfwqtaazdankxmdlqdak`).** Not deployed to prod yet.

---

## What changed

### Why we did this

`grow_seed_batch` had been a shared table for both lettuce and cuke, but the two
farms have genuinely different seeding workflows:

- **Lettuce** seeds in boards/flats/trays with optional seed mixes, has 19 trial
  types, and needs a transplant date and estimated harvest date for every cycle.
- **Cuke** seeds in bags (always), never mixes, has one catch-all trial type,
  and its seeding workflow is tied to a physical plant-map (every cycle fills
  specific greenhouse rows at 4 or 5 plants per bag).

Seven of the 25 columns on `grow_seed_batch` were null or forced sentinel values
for every cuke row. More importantly, cuke needed three new fields
(`rows_4_per_bag`, `rows_5_per_bag`, `seeds`) that snapshot the plant-map state
at seeding time — and these would have been dead weight on lettuce. Plus the
plant-map itself had no DB representation at all, so we added four new tables to
hold it.

### New tables (all live in dev)

| Table | Purpose | Rows |
|---|---|---|
| `org_site_gh` | Per-greenhouse display config (orientation, sidewalk side, where on the dashboard grid it lives). One row per physical GH | 12 |
| `org_site_gh_block` | How a greenhouse is divided into visible blocks (North/Middle/South, Hamakua/Kohala, etc.). Holds row-range + display name per block | 23 |
| `org_site_gh_row` | Every physical GH row — pure identity (site_id, row_num). Crop-agnostic and rendering-agnostic; any row-level activity (scouting, spraying, monitoring) can reference it by UUID. Bag count now lives on `grow_cuke_gh_row_planting` (per scenario) | 660 |
| `grow_cuke_seed_batch` | Cuke seeding events — replaces the cuke subset of `grow_seed_batch`. Holds both historical cycles and forward plans | 660 historical + 159 forward = 819 |
| `grow_cuke_gh_row_planting` | What variety is planted in each physical row. Two scenarios per row: `current` (live layout the transplant crew follows) and `planned` (proposed future layout) | 1,320 (660 current + 660 planned) |

### Renames

`grow_seed_batch` → **`grow_lettuce_seed_batch`** (5,731 rows, 100% lettuce now).

### FK column splits on two downstream tables

Because a harvest weigh-in or a grow-activity task might link to either a
lettuce or a cuke seed batch — and each batch lives in a different table now —
we split the old single `grow_seed_batch_id` FK into two nullable columns per
table, with a CHECK that exactly one is populated:

- `grow_harvest_weight`: `grow_lettuce_seed_batch_id` + `grow_cuke_seed_batch_id`
- `grow_task_seed_batch`: same pair

**FK migration verification in dev:**
- `grow_harvest_weight`: 4,957 lettuce-linked + 62,181 cuke-linked, 0 orphans
- `grow_task_seed_batch`: 51,313 lettuce-linked + 34,972 cuke-linked, 0 orphans

### Cuke seed batch — what changed from the old shared table

| Field | Before | After |
|---|---|---|
| `batch_code` | stored as `YYMM{GH}{V}{P\|T}` | **removed** — derived on the fly from seeding_date + site_id + invnt_item.grow_variety_id when matching |
| `grow_variety_id` | absent | **still absent** — derivable via `invnt_item.grow_variety_id`; variety only lives on `grow_cuke_gh_row_planting` |
| `grow_cycle_pattern_id` | null for all cuke | **dropped** |
| `grow_seed_mix_id` | null for all cuke | **dropped** (cuke never mixes) |
| `seeding_uom` | always `'bag'` for cuke | **dropped** |
| `number_of_units × seeds_per_unit` | two columns | **rolled into one `seeds` column** |
| `number_of_rows` | always `-1` sentinel | **dropped** |
| `estimated_harvest_date` | required but dummy-valued | **dropped** |
| — | — | `rows_4_per_bag`, `rows_5_per_bag` (snapshot fields, frozen at seeding time from the plant-map) |
| — | — | `next_bag_change_date` |

### Plant-map → Supabase (one-time seed)

The plant-map Google Sheet was the only existing source for the layout tables.
We did a one-time import that populated:

- `org_site_gh` from the `GH_CONFIG` constant in `dash/plant-map/index.html`
- `org_site_gh_row` + `org_site_gh_block` from the plant-map sheet
- `grow_cuke_gh_row_planting` from the sheet's `Variety` / `Variety2` columns
  (current and planned scenarios, one row per `(physical_row, scenario)`)
- `grow_cuke_seed_batch` from the 660 cuke rows in `grow_seed_batch`, preserving
  UUIDs so the FK splits above found matching references

### Forward cuke seeding plan — 159 new rows

Populated `grow_cuke_seed_batch` with planned cycles for the next 52 weeks using
SIM_ORDER from the plant-map dashboard (12-week rotation, one GH per week).

- Anchor: GH2 seeds week of 2026-03-15
- Variety allocation: `planned` scenario in `grow_cuke_gh_row_planting`
- Per-GH per-variety `seeds` computed from `SUM(bag_contribution × plants_per_bag)`
- `rows_4_per_bag` / `rows_5_per_bag` snapshotted from the planned layout
- `next_bag_change_date` per cycle: earliest future bag-change date ≥ seeding_date
  (from the sheet's `bag_changes` tab)
- `transplant_date` = seeding_date + 14 days
- Status = `planned`
- Default `invnt_item_id` per variety: k→`delta_star_minis_rz`, j→`f1_tsx_cu235jp_tokita`, e→`english`
- HK gets one row per variety per cycle (not two), stored under `site_id='hk'`
- 12 GHs × 3 varieties × 4–5 cycles each → 159 rows

### Nightly sync changes

| Script | Status | Reason |
|---|---|---|
| `024_grow_cuke_seeding.py` | **Removed from nightly** | Cuke seed batches are now static/forward-planned; the grow_C_seeding sheet is no longer the source of truth for cuke cycles |
| `025_grow_cuke_harvest.py` | Kept in nightly, rewritten | Derives cycle code `{YY}{MM}{GH}{VARIETY}` + is_trial to find cuke batch. **Stub-creation path removed** — see Q1 below |
| `026_grow_cuke_harvest_sched.py` | Kept in nightly | No seed-batch linkage; no code changes needed |
| `027_grow_lettuce_seeding.py` | Updated | Targets renamed `grow_lettuce_seed_batch` + `grow_lettuce_seed_batch_id` |
| `028/029/030/032` | Updated | Write to the correct `*_seed_batch_id` column based on `farm_id` |
| `033_business_rule.py` | Updated | Text references for rule targets |

### Commits

- `aloha-data-migrations@c60d004` — initial cuke split (schema, seeder, script edits)
- `aloha-data-migrations@3619997` — derived cycle code, un-retired 025/026, HK via block name
- `aloha-data-migrations@1eb0f93` — this update doc
- `dash@cea8c15` — retired the design doc `docs/cuke-seeding-schema.md`

---

## HK handling (FYI — decided, not a question)

`org_site.id = 'hk'` represents both Hamakua and Kohala greenhouses. The
plant-map sheet has them as two separate GHs with overlapping row numbers
(Hamakua 1–40, Kohala 1–24). Because all of Supabase outside the plant-map
treats HK as one GH, we chose to solve this on the plant-map side rather than
splitting `hk` in `org_site`:

- `org_site_gh`: one row for `hk`
- `org_site_gh_row`: Hamakua rows keep their row_num (1–40). Kohala rows are
  offset by +100 (stored as 101–124) to avoid collision on the unique
  `(site_id, row_num)` constraint
- `org_site_gh_block`: two blocks under `hk` — `name='Hamakua'` (row_num 1–40)
  and `name='Kohala'` (row_num 101–124). The plant-map UI uses the block name
  to render each as a labelled section and subtracts 100 when displaying
  Kohala row numbers

Clean, reversible, and nothing external depends on the `hk` identity beyond
historical references that migrated cleanly.

---

## Open questions

### 1. Cuke harvest — stub seed batches (please confirm)

**Background.** The cuke harvest script (`025_grow_cuke_harvest.py`) reads the
`grow_C_harvest` Google Sheet nightly. Each harvest row carries a
`SeedingCycle` value that should match a seed batch in `grow_cuke_seed_batch`.
When a match is found, the harvest row is inserted into `grow_harvest_weight`
with a FK to that seed batch. When no match is found, the previous version of
025 did one of two things depending on the case:

1. Most harvest rows match a seeding cycle that already exists in
   `grow_cuke_seed_batch` (because that cycle came through the seeding sheet
   earlier). These link cleanly — no issue.
2. Some harvest rows referenced cycles that had never been logged as seedings
   in the sheet. For those, the old script **auto-created a "stub"
   seed batch row** via a helper called `ensure_stub_batches`, with sentinel
   values in most columns (`number_of_units = -1`, back-derived dates, etc.)
   and a note saying "Stub: auto-created by harvest migration (no seeding
   sheet data)". The harvest row then linked to that stub.

**What we changed.** We removed the stub-creation path entirely. Now, if a
harvest record references a seeding cycle that doesn't exist in
`grow_cuke_seed_batch`, the cycle code is logged and the harvest weigh-in is
skipped — no row inserted.

**Why.** Inventing a seeding event from a harvest record gets the accounting
backwards: the physical reality is that someone seeded, then harvested. If the
seeding isn't in the system, the fix belongs at the seeding step (correct the
seeding source, add the missing cycle), not downstream. Auto-stubs masked
data-entry errors and produced seed batches whose numbers
(`number_of_units = -1`) weren't usable for any calculation.

With the stubs path gone, any unmatched harvest row is visibly missing a
seeding parent, which surfaces as a loggable discrepancy rather than a hidden
rubber-stamp. Going forward, if the legitimate business case exists for a
harvest without a matching seeding cycle — e.g., a surprise harvest at a new
GH that predates the seeding tracker — we should add a proper "orphan harvest"
workflow rather than fabricate seed batches. Please confirm removing the stub
path is the right call.

### 2. Forward-seeding needs an editable UI

159 forward seeding rows are now in `grow_cuke_seed_batch` with status
`'planned'`. These are projections, not commitments — the schedule assumes a
perfectly regular 12-week rotation with no shifts, but the real world will have
slips (crew availability, weather, a GH needs an extra week, etc.).

We'll need a view/page that lets ops staff:

- See the forward seeding schedule per GH and per variety
- **Make micro-edits** to individual row's `seeding_date` and `transplant_date`
  when a specific cycle shifts (e.g., push this Kona cycle by one week, pull
  that GH5 transplant forward by 3 days)
- Optionally update `seeds`, `rows_4_per_bag`, `rows_5_per_bag` if the planned
  layout changes for a specific cycle
- Mark a cycle as confirmed (status transitioning from `planned` to `seeded`
  once it actually happens — this already auto-advances based on dates, but
  edits from the view should be able to force-set too)

Scope likely lives in dash (next to plant-map) or as a new admin page.
Design + build is a separate workstream; flagging now so it's on your radar
since the forward schedule is only useful if it can be corrected as reality
diverges from the rotation model.

### 3. Production deploy

Dev (`kfwqtaazdankxmdlqdak`) is fully deployed and verified. Prod
(`zdvpqygiqavwpxljpvqw`) is untouched. Repeating the same sequence there
when you're ready is safe — same SQL files in
`aloha-data-migrations/sql/schema/`, same Python seeder logic (this time
runnable locally once credentials are set up, or we repeat the MCP-driven flow
we used for dev).

### 4. Minor cosmetic cleanup

After the rename, `pack_dryer_result.grow_seed_batch_id` column still bears
the old name but now FKs to `grow_lettuce_seed_batch(id)` (PostgreSQL
auto-followed the table rename). Column value is correct, column name is stale.
Harmless. Would rename to `grow_lettuce_seed_batch_id` in a future tidy-up if
you want.

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
20260417000001_cuke_plantmap.py          (one-time, layout + cuke seed batch copy)
_run_nightly.py                          (024 removed; 025/026/027 configured)
_clear_transactional.py                  (new cuke tables + renamed lettuce table)
20260401000025_grow_cuke_harvest.py      (rewritten matching, stubs removed)
20260401000027_grow_lettuce_seeding.py   (target table + column rename)
20260401000032_grow_monitoring.py        (farm_id-aware writes)
20260401000033_business_rule.py          (text references)
```

---

## Suggested next steps

1. **Answer open questions** — especially Q1 (stub policy) and Q2 (forward-seed editing UI scope)
2. **Test nightly on dev** — let 025/026/027/028/029/030/032 run once end-to-end and verify no errors
3. **Plan prod deployment** — same SQL sequence against `zdvpqygiqavwpxljpvqw`
4. **Scope the forward-seed editing view** (Q2) — this is the missing piece that makes the forward schedule operationally useful
