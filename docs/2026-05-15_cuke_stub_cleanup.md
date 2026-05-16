# Cuke seed-batch stub cleanup (2026-05-15)

## Problem

`grow_cuke_seed_batch` in prod had 114 stub rows
(`notes LIKE 'Stub batch backfilled from grow_C_harvest cycle code%'`)
left over from an earlier `ensure_stub_batches()` path in the cuke
harvest migration. The stubs:

- Have `seeding_date` set to `"{YY}{MM}-01"` parsed from the harvest
  sheet's `SeedingCycle` cycle code.
- Have `seeds = 0`, `rows_4_per_bag = -1`, `rows_5_per_bag = -1`.
- Currently anchor ~1,500 `grow_harvest_weight` rows that should be
  pointing at real seed batches (or be dropped).

`days_since_seed` on the cuke yield dashboard is wrong for any stub-linked
cycle. The 250604 GH4 cycle, for example, is shown harvesting starting at
week 7.6 in greenhouse — the real first-harvest week is 3.0 (off by 32d).

## Why the bug fired

The migration matches harvest rows to seed batches by the derived code
`{YY}{MM}{GH}{VARIETY}`, where `YY/MM` are pulled from the seed batch's
`seeding_date`. For ~5 cycles, the harvest sheet's `SeedingCycle` uses a
rotation-slot label whose `YYMM` doesn't match the actual seed month
(e.g. cycle `250604` was actually seeded 2025-07-03 → derived code
`250704K`). When the migration's lookup failed, the old path created a
stub with `seeding_date = "{YYMM}-01"` (e.g. 2025-06-01) and linked the
harvest row to it.

Separately, ~92 harvest-sheet rows from 2019-11 → 2022-06 carry an `S-`
cycle prefix and have no counterpart in the seeding sheet (pre-seeding-sheet
era data backfilled into the harvest sheet only). The migration created
stubs for those too.

## Categories (114 stubs)

| Group | Count | Disposition |
|---|--:|---|
| `S-*` pre-seeding-sheet (2019–2022) | 92 | Drop. No seeding source-of-truth. ~6,500 harvest rows from this era get dropped on next nightly. |
| Off-month K/J stubs (cycles 250203, 250308, 250505, 250604) | 8 | Real K/J batches already exist at the correct seed dates. Apply remap; ~787 harvest rows re-link. |
| Cumlaude (E) stubs with no E seeding event | 11 | Drop. seeds=0 everywhere; only 136 harvest rows total, mostly 1-3 per cycle. |
| 2508WA* stubs (no Aug Waimea seeding) | 3 | Apply remap (`2508WA→2509WA`); 41 harvest rows re-link to real 2509WA K/J/E batches. |

## Fix in this PR

### 1. `gsheets/migrations/20260401000026_grow_cuke_harvest.py`

Adds a `CYCLE_CODE_REMAP` constant applied at lookup time:

```python
CYCLE_CODE_REMAP = {
    "250203": "250303",
    "250308": "250208",
    "250505": "250705",
    "250604": "250704",
    "2508WA": "2509WA",
}
```

The remap rewrites the cycle code's prefix (everything before the
variety letter) before the batch lookup. Source sheets remain untouched.

E cycles with no real E seed batch will now fail the lookup naturally
and be logged as `unmatched_batch` — no special exclusion needed.

### 2. `gsheets/migrations/20260515000000_fix_cuke_stub_batches.py`

One-shot script: deletes the 114 stub rows from `grow_cuke_seed_batch`
in prod (and any dependent `grow_harvest_weight` rows, which the next
nightly run of 026 will rebuild from sheet).

```bash
python gsheets/migrations/20260515000000_fix_cuke_stub_batches.py
```

Idempotent: only matches `notes LIKE 'Stub batch backfilled%'`. Safe to
re-run.

## Order of operations

1. Merge this PR.
2. Run `20260515000000_fix_cuke_stub_batches.py` once against prod.
3. Wait for the next nightly run of `_run_nightly.py` (or trigger it
   manually): `python gsheets/migrations/_run_nightly.py --only 026`.
4. Verify (queries below).

## Verification

After step 3:

```sql
-- Should return 0:
SELECT COUNT(*) FROM grow_cuke_seed_batch
WHERE notes LIKE 'Stub batch backfilled%';

-- 250604 GH4 cycle: should show seed_date = 2025-07-03 and first
-- harvest day = 35 (week 3.0 in GH after the 14-day transplant).
SELECT b.seeding_date,
       MIN(h.harvest_date) AS first_harvest,
       MIN(h.harvest_date - b.seeding_date) AS first_day
FROM grow_cuke_seed_batch b
JOIN grow_harvest_weight h ON h.grow_cuke_seed_batch_id = b.id
WHERE b.site_id = '04' AND b.seeding_date = '2025-07-03'
GROUP BY b.seeding_date;

-- 2508WA harvest rows should now link to 2025-09-18 batches:
SELECT b.seeding_date, b.invnt_item_id, COUNT(*)
FROM grow_harvest_weight h
JOIN grow_cuke_seed_batch b ON b.id = h.grow_cuke_seed_batch_id
WHERE h.site_id = 'wa'
  AND h.harvest_date BETWEEN '2025-10-23' AND '2025-11-03'
GROUP BY b.seeding_date, b.invnt_item_id;
```

## Reference

- Per-row stub audit: `audit/cuke_seed_batch_stubs.csv` in the dash repo
  (114 rows, cycle_code / supabase_seed_date / sheet_actual_seed_date /
  days_off_from_yymm / harvest_rows).
- Original investigation thread: Lenny + Claude session 2026-05-15.
