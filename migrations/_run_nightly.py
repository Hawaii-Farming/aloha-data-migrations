"""
Run a configurable set of migrations in order, with timing and fail-fast.

Used by the nightly GitHub Actions workflow. Can also be run locally for
ad-hoc full refreshes.

Usage:
    python migrations/_run_nightly.py                    # run default set
    python migrations/_run_nightly.py --all              # run 004-033
    python migrations/_run_nightly.py --from 011 --to 023 # range
    python migrations/_run_nightly.py --only 024,025,026  # specific

Exit code:
    0 — all migrations ran successfully
    non-0 — first failure; run stops immediately
"""

import argparse
import glob
import os
import re
import subprocess
import sys
import time
from pathlib import Path

MIGRATIONS_DIR = Path(__file__).parent
SCRIPT_GLOB = "20260401*.py"
# Exclude helper/utility modules
HELPERS = {"_config", "_pg", "_clear_transactional", "_run_nightly", "_upload_images"}

# Default set for nightly runs. Excludes 001-003 and 006 (foundation/reference
# data that changes rarely and is upserted idempotently). Users who want those
# too can pass --all or edit this list.
# 004 (hr_schedule) and 005 (hr_payroll) are included because schedules +
# payroll must never fall out of sync — and _clear_transactional wipes
# ops_task_schedule every night, so 004 is required to repopulate it.
DEFAULT_SET = [
    "004",  # hr_schedule (ops_task_schedule planned entries)
    "005",  # hr_payroll
    "007",  # maint
    "008",  # fsafe (lab, lab_test)
    "009",  # pack (sales_product + pack_lot)
    "010",  # pack_productivity
    "011",  # fsafe_results
    "012", "013", "014", "015", "016", "017",  # fsafe checklists
    "018",  # fsafe_pest_log
    "019",  # ops_training
    "020",  # fsafe_corrective_actions
    "021", "022", "023",  # sales
    # 024 (grow_cuke_seeding) retired: cuke seed batches are now static,
    # populated once by 20260417000001_cuke_plantmap.py.
    "025",  # grow_cuke_harvest — re-enabled with derived batch code matching
    "026",  # grow_cuke_harvest_sched
    "027",  # grow_lettuce_seeding
    "028",  # grow_fertigation
    "029",  # grow_spraying
    "030",  # grow_scouting
    "031",  # grow_spray_pre_check
    "032",  # grow_monitoring
    "033",  # business_rule
    "034",  # fin_expense + sales_invoice (nightly QB sheet sync)
]

ALL_SET = [f"{i:03d}" for i in range(1, 35)]


def discover_scripts():
    """Return {3-digit-prefix: absolute_path} for every data migration script."""
    scripts = {}
    for p in sorted(MIGRATIONS_DIR.glob(SCRIPT_GLOB)):
        name = p.stem  # e.g. 20260401000024_grow_cuke_seeding
        if any(name.endswith(h) for h in HELPERS):
            continue
        m = re.match(r"^20260401(\d{6})_", name)
        if not m:
            continue
        prefix = m.group(1)[-3:]  # last 3 digits (e.g. "024")
        scripts[prefix] = p
    return scripts


def run_one(prefix, path):
    """Run a single migration script. Returns (ok, duration_seconds).

    Preloads _config before running the script so every migration picks up
    the postgrest retry patch defined there — even the older migrations
    that don't import _config themselves.
    """
    print(f"\n{'=' * 70}")
    print(f"[{prefix}] {path.name}")
    print('=' * 70)
    t0 = time.time()
    bootstrap = (
        f"import sys; sys.path.insert(0, {str(path.parent)!r}); "
        f"import _config; "
        f"import runpy; runpy.run_path({str(path)!r}, run_name='__main__')"
    )
    result = subprocess.run([sys.executable, "-c", bootstrap])
    dur = time.time() - t0
    ok = result.returncode == 0
    print(f"\n[{prefix}] {'OK' if ok else 'FAIL'} ({dur:.1f}s)")
    return ok, dur


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = parser.add_mutually_exclusive_group()
    g.add_argument("--all", action="store_true", help="Run all data migrations (001-033)")
    g.add_argument("--only", help="Comma-separated 3-digit prefixes (e.g. '024,025,026')")
    parser.add_argument("--from", dest="from_", help="Lower bound prefix (inclusive)")
    parser.add_argument("--to", help="Upper bound prefix (inclusive)")
    parser.add_argument("--continue-on-error", action="store_true",
                        help="Keep running subsequent migrations after a failure")
    args = parser.parse_args()

    scripts = discover_scripts()
    print(f"Discovered {len(scripts)} migration scripts")

    # Pick the target set
    if args.only:
        wanted = [p.strip() for p in args.only.split(",") if p.strip()]
    elif args.all:
        wanted = list(ALL_SET)
    else:
        wanted = list(DEFAULT_SET)

    # Apply --from / --to range
    if args.from_:
        wanted = [p for p in wanted if p >= args.from_]
    if args.to:
        wanted = [p for p in wanted if p <= args.to]

    # Keep deterministic order
    wanted = sorted(set(wanted))

    # Filter out any that don't exist on disk
    missing = [p for p in wanted if p not in scripts]
    if missing:
        print(f"WARNING: missing scripts for prefixes: {missing}")
    wanted = [p for p in wanted if p in scripts]

    print(f"\nWill run {len(wanted)} migrations:")
    for p in wanted:
        print(f"  {p}  {scripts[p].name}")

    if not wanted:
        print("Nothing to do.")
        return 0

    results = []
    total_start = time.time()
    for prefix in wanted:
        ok, dur = run_one(prefix, scripts[prefix])
        results.append((prefix, ok, dur))
        if not ok and not args.continue_on_error:
            print(f"\n*** STOPPING after {prefix} failed ***")
            break

    total = time.time() - total_start
    print(f"\n{'=' * 70}")
    print(f"SUMMARY — total runtime {total:.1f}s ({total / 60:.1f} min)")
    print('=' * 70)
    for prefix, ok, dur in results:
        status = "OK   " if ok else "FAIL "
        print(f"  [{prefix}] {status} {dur:6.1f}s  {scripts[prefix].name}")
    failures = [p for p, ok, _ in results if not ok]
    print(f"\n{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
