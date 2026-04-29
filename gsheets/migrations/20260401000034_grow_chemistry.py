"""
Sync external-lab chemistry results
====================================
Nightly load of the external chemistry lab spreadsheet into
`grow_chemistry_result`. Long-format readings — one row per
(sample_date, site_name, nutrient).

Source (https://docs.google.com/spreadsheets/d/1XwavjRPi3xMJClslOjuC_4ONrbdl8l_qw0_JallE2c0):
  Sheet1 (default tab) — columns: sample_date, site_name, nutrient, result

The sheet is treated as the single source of truth: every run wipes the
org-scoped rows and reinserts everything. No upsert/merge logic; if a
row in the DB diverges from the sheet, the sheet wins on the next run.

Usage:
    python gsheets/migrations/20260401000034_grow_chemistry.py

Rerunnable: clears org_id rows and reloads from the sheet.
"""

import csv
import io
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from supabase import create_client

from gsheets.migrations._config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)


SHEET_ID = SHEET_IDS["chemistry"]
SHEET_TAB = "Sheet1"

# Lab samples are pulled from the lettuce ponds and the lettuce farm
# water source — both belong to the lettuce farm.
FARM_ID = "Lettuce"


# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, batch_size: int = 500):
    if not rows:
        print(f"  {table}: no rows")
        return
    total_batches = (len(rows) + batch_size - 1) // batch_size
    inserted = 0
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        batch_num = (i // batch_size) + 1
        try:
            supabase.table(table).insert(batch).execute()
            inserted += len(batch)
        except Exception as e:
            print(
                f"  ERROR on batch {batch_num}/{total_batches} "
                f"(rows {i + 1}-{i + len(batch)}): {type(e).__name__}: {e}"
            )
            print(f"  {inserted} rows committed before failure")
            print(f"  Re-run the script to retry — it is idempotent.")
            raise
        if batch_num % 10 == 0 or batch_num == total_batches:
            print(f"  {table}: batch {batch_num}/{total_batches} ({inserted} rows)")
    print(f"  {table}: inserted {inserted} rows")


def fetch_gviz_csv(sheet_id: str, tab: str) -> list[dict]:
    """Fetch one tab as list of dicts via gviz CSV (no auth required)."""
    from urllib.parse import quote
    url = (
        f"https://docs.google.com/spreadsheets/d/{sheet_id}"
        f"/gviz/tq?tqx=out:csv&sheet={quote(tab)}"
    )
    with urllib.request.urlopen(url) as resp:
        raw = resp.read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(raw)))


def parse_date(s):
    if s is None:
        return None
    s = str(s).strip()
    if not s:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parse_number(s):
    if s is None:
        return None
    s = str(s).strip().replace(",", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def clean(s):
    if s is None:
        return None
    s = str(s).strip()
    return s if s else None


# ---------------------------------------------------------------------------
# Clear
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    print("\nClearing existing rows for this org (sheet is truth)...")
    supabase.table("grow_chemistry_result").delete().eq("org_id", ORG_ID).execute()
    print("  Cleared grow_chemistry_result")


# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------

def transform(r: dict) -> dict | None:
    sample_date = parse_date(r.get("sample_date"))
    site_name   = clean(r.get("site_name"))
    nutrient    = clean(r.get("nutrient"))
    result      = parse_number(r.get("result"))

    if not sample_date or not site_name or not nutrient or result is None:
        return None

    return audit({
        "org_id":      ORG_ID,
        "farm_id":     FARM_ID,
        "sample_date": sample_date.isoformat(),
        "site_name":   site_name,
        "nutrient":    nutrient,
        "result":      result,
    })


def sync(records) -> list[dict]:
    rows = []
    skipped = 0
    for r in records:
        out = transform(r)
        if out:
            rows.append(out)
        else:
            skipped += 1
    print(f"  {len(records)} sheet rows -> {len(rows)} kept, {skipped} skipped")
    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())

    print("=" * 60)
    print("GROW CHEMISTRY MIGRATION")
    print("=" * 60)

    print(f"\nFetching {SHEET_TAB} from sheet {SHEET_ID}...")
    records = fetch_gviz_csv(SHEET_ID, SHEET_TAB)
    print(f"  {len(records)} sheet rows loaded")

    rows = sync(records)

    clear_existing(supabase)

    print(f"\nInserting {len(rows)} chemistry rows...")
    insert_rows(supabase, "grow_chemistry_result", rows)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
