"""
One-shot fix: delete cuke seed-batch stubs created by the old
ensure_stub_batches() path of 20260401000026_grow_cuke_harvest.py.

Background
----------
An earlier version of the cuke harvest migration created "stub" seed
batches in grow_cuke_seed_batch whenever a harvest row referenced a cycle
that wasn't yet in the seeding source-of-truth. Stubs were created with
seeding_date = "{YY}{MM}-01" parsed from the harvest sheet's cycle code,
even though that YYMM often doesn't equal the real seed month (the code
is a rotation slot label, not a date). 114 stubs ended up in prod (all
with `notes LIKE 'Stub batch backfilled%'`). They mis-link harvest rows
and skew the days-since-seed math on the cuke yield dashboard.

The stub-creation path was removed from 026 in 2026-05-09; this script
deletes the residual stub rows. After this runs, the next nightly invocation
of 026 will (a) wipe grow_harvest_weight for farm_id='Cuke' and (b)
re-insert from the harvest sheet, matching each row against derived
cycle codes from REAL seed batches only. CYCLE_CODE_REMAP in 026 handles
the 5 cases where the harvest sheet's slot label doesn't match the real
seed month.

Categories of stubs being deleted (see audit/cuke_seed_batch_stubs.csv
in the dash repo for the full per-row list):

  - 92 'S-' stubs from 2019-2022 pre-seeding-sheet era. No source-of-truth
    seeding records exist. Harvest data for these cycles will be dropped
    on the next nightly run (the harvest sheet's S- rows will fail to
    match any real batch). ~6,500 rows / mostly old data.

  - 4 off-month K/J stubs (250203, 250308, 250505, 250604). Real K/J
    batches already exist at the correct seed dates. After this delete
    + CYCLE_CODE_REMAP, the ~787 harvest rows re-link cleanly.

  - 11 Cumlaude (E) stubs where the seeding sheet logged only K/J for
    those cycles (no E seeding event). E harvest rows (~136 total, mostly
    1-3 rows per cycle) will be skipped — there's no real E batch to
    attach them to and zero E seed count to justify creating one.

  - 3 '2508WA*' stubs. No 2508WA seeding existed in Waimea — the rows
    belong to the 2509WA cycle. CYCLE_CODE_REMAP rewrites the lookup so
    after this delete, the 41 harvest rows re-link to real 2509WA K/J/E
    batches.

Idempotent: only deletes rows matching the stub-notes prefix.

Usage:
    python gsheets/migrations/20260515000000_fix_cuke_stub_batches.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from supabase import create_client

from _config import SUPABASE_URL, require_supabase_key

STUB_NOTES_PREFIX = "Stub batch backfilled from grow_C_harvest cycle code"


def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())

    print(f"Looking up stub batches (notes LIKE '{STUB_NOTES_PREFIX}%')...")
    res = (
        supabase.table("grow_cuke_seed_batch")
        .select("id,site_id,seeding_date,invnt_item_id,notes")
        .like("notes", f"{STUB_NOTES_PREFIX}%")
        .execute()
    )
    rows = res.data or []
    print(f"  Found {len(rows)} stub batches")

    if not rows:
        print("Nothing to do.")
        return

    # Summarize before deleting so the log is useful.
    s_prefix = [r for r in rows if "S-" in (r["notes"] or "")]
    print(f"    {len(s_prefix)} S- pre-2022 stubs")
    print(f"    {len(rows) - len(s_prefix)} non-S- stubs")

    ids = [r["id"] for r in rows]

    # FK grow_harvest_weight.grow_cuke_seed_batch_id is ON DELETE NO ACTION,
    # so we must clear dependent harvest rows before deleting the stubs.
    # The next nightly run of 20260401000026_grow_cuke_harvest.py will
    # rebuild grow_harvest_weight from the sheet anyway, so this delete is
    # safe and idempotent.
    print("\nDeleting dependent grow_harvest_weight rows (will be rebuilt nightly)...")
    deleted_hw = 0
    for i in range(0, len(ids), 100):
        batch = ids[i:i + 100]
        del_res = (
            supabase.table("grow_harvest_weight")
            .delete()
            .in_("grow_cuke_seed_batch_id", batch)
            .execute()
        )
        deleted_hw += len(del_res.data or [])
    print(f"  Deleted {deleted_hw} grow_harvest_weight rows")

    print("\nDeleting stub seed batches...")
    deleted_total = 0
    for i in range(0, len(ids), 100):
        batch = ids[i:i + 100]
        supabase.table("grow_cuke_seed_batch").delete().in_("id", batch).execute()
        deleted_total += len(batch)
        print(f"  Deleted {deleted_total}/{len(ids)}")

    print("\nDone. Next nightly run of 20260401000026_grow_cuke_harvest.py")
    print("will rebuild grow_harvest_weight against real seed batches only.")


if __name__ == "__main__":
    main()
