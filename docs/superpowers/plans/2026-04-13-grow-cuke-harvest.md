# Grow Cuke Harvest Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate ~4,872 harvest weigh-in rows from the legacy `grow_C_harvest` Google Sheet tab into `grow_harvest_weight`, with formula-based tare support on `grow_harvest_container`.

**Architecture:** Schema change adds formula columns to `grow_harvest_container` (matching `grow_monitoring_metric` pattern). Migration script reads the sheet, links each harvest row to its seed batch via `SeedingCycle` + `P`/`T` suffix, and inserts into `grow_harvest_weight` with 6 variety+grade-specific pallet containers.

**Tech Stack:** Python 3, gspread, supabase-py, PostgreSQL (Supabase)

**Spec:** `docs/superpowers/specs/2026-04-13-grow-cuke-harvest-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `c:/Users/micha/Desktop/aloha-app/supabase/migrations/20260408000053_grow_harvest_container.sql` | Modify | Add formula columns, relax tare_weight to nullable |
| `schema-reference/sql/` | Sync | Re-sync from aloha-app via `sync-schema-reference.sh` |
| `migrations/20260401000026_grow_cuke_harvest.py` | Create | Full harvest migration script |

---

### Task 1: Schema change — add formula columns to grow_harvest_container

**Files:**
- Modify: `c:/Users/micha/Desktop/aloha-app/supabase/migrations/20260408000053_grow_harvest_container.sql`

- [ ] **Step 1: Edit the grow_harvest_container migration in aloha-app**

Replace the current file contents with the updated schema that adds formula support. Changes from the original:
- `tare_weight` changed from `NUMERIC NOT NULL` to `NUMERIC` (nullable for formula-based containers)
- Added `is_tare_calculated BOOLEAN NOT NULL DEFAULT false`
- Added `tare_formula TEXT`
- Added `tare_formula_inputs JSONB`
- Added comments for new columns

```sql
CREATE TABLE IF NOT EXISTS grow_harvest_container (
    id              TEXT PRIMARY KEY,
    org_id          TEXT NOT NULL REFERENCES org(id),
    farm_id         TEXT NOT NULL REFERENCES org_farm(id),
    name            TEXT NOT NULL,
    grow_variety_id TEXT REFERENCES grow_variety(id),
    grow_grade_id   TEXT REFERENCES grow_grade(id),
    weight_uom      TEXT NOT NULL REFERENCES sys_uom(code),
    tare_weight     NUMERIC,
    is_tare_calculated  BOOLEAN NOT NULL DEFAULT false,
    tare_formula        TEXT,
    tare_formula_inputs JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by      TEXT,
    is_deleted      BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_grow_harvest_container UNIQUE (org_id, farm_id, name, grow_variety_id, grow_grade_id)
);

COMMENT ON TABLE grow_harvest_container IS 'Harvest container definitions with tare weight per container type, optionally specific to variety and grade. Used to auto-calculate tare during weigh-ins.';

COMMENT ON COLUMN grow_harvest_container.grow_variety_id IS 'Tare weight can vary by variety; null means any variety';
COMMENT ON COLUMN grow_harvest_container.grow_grade_id IS 'Tare weight can vary by grade; null means any grade';
COMMENT ON COLUMN grow_harvest_container.tare_weight IS 'Fixed tare weight of one empty container; used when is_tare_calculated = false. Multiplied by number_of_containers in grow_harvest_weight';
COMMENT ON COLUMN grow_harvest_container.is_tare_calculated IS 'When true, tare is computed from tare_formula instead of using the fixed tare_weight value';
COMMENT ON COLUMN grow_harvest_container.tare_formula IS 'Text expression evaluated by the app layer to compute tare from gross_weight (e.g. ROUND(0.0316 * gross_weight + -0.835) * 3 + 48). Same pattern as grow_monitoring_metric.formula';
COMMENT ON COLUMN grow_harvest_container.tare_formula_inputs IS 'JSON metadata for the formula inputs, following the grow_monitoring_metric.input_point_ids pattern';
```

- [ ] **Step 2: Verify the file was written correctly**

Run: `cat "c:/Users/micha/Desktop/aloha-app/supabase/migrations/20260408000053_grow_harvest_container.sql" | head -20`

Expected: Should show `tare_weight NUMERIC,` (no NOT NULL) and `is_tare_calculated` column.

- [ ] **Step 3: Commit the schema change in aloha-app**

```bash
cd c:/Users/micha/Desktop/aloha-app
git add supabase/migrations/20260408000053_grow_harvest_container.sql
git commit -m "Add formula-based tare support to grow_harvest_container

Adds is_tare_calculated, tare_formula, tare_formula_inputs columns.
Relaxes tare_weight to nullable for formula-based containers.
Same pattern as grow_monitoring_metric.formula."
```

---

### Task 2: Sync schema-reference

**Files:**
- Sync: `schema-reference/sql/` and `schema-reference/docs/`

- [ ] **Step 1: Run the sync script**

```bash
cd c:/Users/micha/Desktop/aloha-data-migrations
ALOHA_APP_DIR="c:/Users/micha/Desktop/aloha-app" bash sync-schema-reference.sh
```

Expected: `109 SQL migration files` (or more if new files were added), `10 markdown docs`.

- [ ] **Step 2: Verify the container schema was updated**

Run: `grep "is_tare_calculated" schema-reference/sql/20260408000053_grow_harvest_container.sql`

Expected: Shows the `is_tare_calculated` column definition.

- [ ] **Step 3: Commit the sync**

```bash
git add schema-reference/
git commit -m "Sync schema-reference after grow_harvest_container formula columns"
```

---

### Task 3: Write migration script — docstring, imports, constants

**Files:**
- Create: `migrations/20260401000026_grow_cuke_harvest.py`

- [ ] **Step 1: Create the migration file with the module docstring, imports, and constants**

```python
"""
Migrate Cuke Harvest Data
=========================
Migrates grow_C_harvest into grow_harvest_weight with one row per
weigh-in record. Each sheet row is a single pallet weigh-in tied to
a seed batch via SeedingCycle + variety suffix.

Source: https://docs.google.com/spreadsheets/d/1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM
  - grow_C_harvest: ~4,872 rows -> ~4,872 grow_harvest_weight rows

Seed batch linkage:
  - Production harvests: batch_code = SeedingCycle + "P"
  - Trial harvests:      batch_code = SeedingCycle + "T" (or "T2", "T3")

Grade mapping (sheet grade -> grow_grade.id):
  1 -> on_grade
  2 -> off_grade

Container mapping (variety + grade -> grow_harvest_container.id):
  K1 -> pallet_k1     K2 -> pallet_k2
  E1 -> pallet_e1     E2 -> pallet_e2
  J1 -> pallet_j1     J2 -> pallet_j2

Weight columns:
  - PalletWeight         -> gross_weight (-1 sentinel when empty)
  - GreenhouseNetWeight  -> net_weight
  - weight_uom           hardcoded to 'pound'
  - number_of_containers hardcoded to 1

Also upserts 6 grow_harvest_container rows (one pallet per
variety+grade) with tare regression formulas from the legacy sheet.

Usage:
    python migrations/20260401000026_grow_cuke_harvest.py

Rerunnable: deletes all grow_harvest_weight rows for farm_id='cuke',
then reinserts.
"""

import re
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

from _config import (
    AUDIT_USER,
    ORG_ID,
    SHEET_IDS,
    SUPABASE_URL,
    require_supabase_key,
)

GROW_SHEET_ID = SHEET_IDS.get("grow") or "1VtEecYn-W1pbnIU1hRHfxIpkH2DtK7hj0CpcpiLoziM"
FARM_ID = "cuke"

GRADE_MAP = {
    "1": "on_grade",
    "2": "off_grade",
}

VARIETY_MAP = {
    "K": "k",
    "J": "j",
    "E": "e",
}

# Container ID = pallet_{variety_lower}{grade_number}
# e.g. Variety=K, Grade=1 -> pallet_k1
CONTAINERS = [
    {
        "id": "pallet_k1",
        "name": "Pallet",
        "grow_variety_id": "k",
        "grow_grade_id": "on_grade",
        "tare_formula": "ROUND(0.0316203631692461 * gross_weight + -0.835015982812408) * 3 + 48",
    },
    {
        "id": "pallet_k2",
        "name": "Pallet",
        "grow_variety_id": "k",
        "grow_grade_id": "off_grade",
        "tare_formula": "ROUND(0.0285084470508113 * gross_weight + 0.38656882092243) * 3",
    },
    {
        "id": "pallet_e1",
        "name": "Pallet",
        "grow_variety_id": "e",
        "grow_grade_id": "on_grade",
        "tare_formula": "ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48",
    },
    {
        "id": "pallet_e2",
        "name": "Pallet",
        "grow_variety_id": "e",
        "grow_grade_id": "off_grade",
        "tare_formula": "ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3",
    },
    {
        "id": "pallet_j1",
        "name": "Pallet",
        "grow_variety_id": "j",
        "grow_grade_id": "on_grade",
        "tare_formula": "ROUND(0.0376641999102221 * gross_weight + -1.33687101211549) * 3 + 48",
    },
    {
        "id": "pallet_j2",
        "name": "Pallet",
        "grow_variety_id": "j",
        "grow_grade_id": "off_grade",
        "tare_formula": "ROUND(0.0318958967501081 * gross_weight + 0.50064774427244) * 3",
    },
]
```

- [ ] **Step 2: Verify file was created**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000026_grow_cuke_harvest.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 4: Write migration script — helper functions

**Files:**
- Modify: `migrations/20260401000026_grow_cuke_harvest.py`

- [ ] **Step 1: Add the standard helpers after the CONTAINERS constant**

These are the same helpers used in the seeding migration (audit, insert_rows, get_sheets, parse_date, parse_int, normalize_gh) plus a `parse_numeric` for weight values:

```python
# ---------------------------------------------------------------------------
# Standard helpers
# ---------------------------------------------------------------------------

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list, upsert=False):
    print(f"\n--- {table} ---")
    all_data = []
    if not rows:
        return all_data
    total_batches = (len(rows) + 99) // 100
    for i in range(0, len(rows), 100):
        batch = rows[i:i + 100]
        batch_num = (i // 100) + 1
        try:
            if upsert:
                result = supabase.table(table).upsert(batch).execute()
            else:
                result = supabase.table(table).insert(batch).execute()
            all_data.extend(result.data)
        except Exception as e:
            print(
                f"  ERROR on batch {batch_num}/{total_batches} "
                f"(rows {i + 1}-{i + len(batch)}): {type(e).__name__}: {e}"
            )
            print(f"  {len(all_data)} rows committed before failure")
            print(f"  Re-run the script to retry — it is idempotent.")
            raise
    action = "Upserted" if upsert else "Inserted"
    print(f"  {action} {len(rows)} rows")
    return all_data


def get_sheets():
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def parse_date(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parse_numeric(val, default=None):
    if val is None:
        return default
    s = str(val).strip().replace(",", "")
    if not s:
        return default
    try:
        return float(s)
    except ValueError:
        return default


def normalize_gh(raw):
    """'1' -> '01', 'HI' -> 'hi'."""
    s = str(raw).strip().lower()
    if not s:
        return None
    if s.isdigit() and len(s) == 1:
        s = s.zfill(2)
    return s
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000026_grow_cuke_harvest.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 5: Write migration script — setup and clear functions

**Files:**
- Modify: `migrations/20260401000026_grow_cuke_harvest.py`

- [ ] **Step 1: Add the container setup and clear functions after the helpers**

```python
# ---------------------------------------------------------------------------
# Setup: harvest containers
# ---------------------------------------------------------------------------

def ensure_containers(supabase):
    """Upsert 6 pallet container rows (one per variety+grade) with tare formulas."""
    print("\n--- grow_harvest_container ---")
    rows = []
    for spec in CONTAINERS:
        rows.append(audit({
            "id": spec["id"],
            "org_id": ORG_ID,
            "farm_id": FARM_ID,
            "name": spec["name"],
            "grow_variety_id": spec["grow_variety_id"],
            "grow_grade_id": spec["grow_grade_id"],
            "weight_uom": "pound",
            "tare_weight": None,
            "is_tare_calculated": True,
            "tare_formula": spec["tare_formula"],
            "tare_formula_inputs": None,
        }))
    supabase.table("grow_harvest_container").upsert(rows).execute()
    print(f"  Upserted {len(rows)} rows: {[r['id'] for r in rows]}")


# ---------------------------------------------------------------------------
# Seed batch lookup
# ---------------------------------------------------------------------------

def build_batch_lookup(supabase):
    """Build a dict of batch_code -> id from grow_seed_batch for cuke farm."""
    batches = (
        supabase.table("grow_seed_batch")
        .select("id,batch_code")
        .eq("farm_id", FARM_ID)
        .execute()
        .data
    )
    return {b["batch_code"]: b["id"] for b in batches}


# ---------------------------------------------------------------------------
# Clear existing data for rerun
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    """Delete all cuke harvest weight rows so the migration is rerunnable."""
    print("\nClearing existing cuke harvest weights...")
    supabase.table("grow_harvest_weight").delete().eq(
        "farm_id", FARM_ID
    ).execute()
    print("  Cleared")
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000026_grow_cuke_harvest.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 6: Write migration script — row transform function

**Files:**
- Modify: `migrations/20260401000026_grow_cuke_harvest.py`

- [ ] **Step 1: Add the row transform function after clear_existing**

```python
# ---------------------------------------------------------------------------
# Row transform
# ---------------------------------------------------------------------------

def build_harvest_row(sheet_row, batch_lookup, known_sites):
    """Transform one sheet row into a grow_harvest_weight dict.

    Returns the row dict on success, or a dict with '_skip' key and reason on failure.
    """
    harvest_date = parse_date(sheet_row.get("HarvestDate"))
    if not harvest_date:
        return {"_skip": "no_date"}

    net_weight = parse_numeric(sheet_row.get("GreenhouseNetWeight"))
    if not net_weight:
        return {"_skip": "no_weight"}

    gh = normalize_gh(sheet_row.get("Greenhouse"))
    if not gh or gh not in known_sites:
        return {"_skip": "unknown_site", "_detail": gh}

    variety = str(sheet_row.get("Variety", "")).strip().upper()
    if variety not in VARIETY_MAP:
        return {"_skip": "unknown_variety", "_detail": variety}

    grade = str(sheet_row.get("Grade", "")).strip()
    if grade not in GRADE_MAP:
        return {"_skip": "unknown_grade", "_detail": grade}

    cycle = str(sheet_row.get("SeedingCycle", "")).strip()
    if not cycle:
        return {"_skip": "no_cycle"}

    is_trial = str(sheet_row.get("is_trial", "")).strip().upper() == "TRUE"
    suffix = "T" if is_trial else "P"
    batch_code = f"{cycle}{suffix}"
    batch_id = batch_lookup.get(batch_code)

    # For trials, try disambiguation suffixes T2, T3
    if not batch_id and is_trial:
        for n in range(2, 5):
            batch_id = batch_lookup.get(f"{cycle}T{n}")
            if batch_id:
                break

    if not batch_id:
        return {"_skip": "unmatched_batch", "_detail": batch_code}

    gross_weight = parse_numeric(sheet_row.get("PalletWeight"), default=-1)

    variety_lower = VARIETY_MAP[variety]
    container_id = f"pallet_{variety_lower}{grade}"
    grade_id = GRADE_MAP[grade]

    reported_by_raw = str(sheet_row.get("ReportedBy", "")).strip().lower()
    reported_by = reported_by_raw if "@" in reported_by_raw else AUDIT_USER

    return {
        "org_id": ORG_ID,
        "farm_id": FARM_ID,
        "site_id": gh,
        "ops_task_tracker_id": None,
        "grow_seed_batch_id": batch_id,
        "grow_grade_id": grade_id,
        "harvest_date": harvest_date.isoformat(),
        "grow_harvest_container_id": container_id,
        "number_of_containers": 1,
        "weight_uom": "pound",
        "gross_weight": gross_weight,
        "net_weight": net_weight,
        "created_by": reported_by,
        "updated_by": reported_by,
    }
```

- [ ] **Step 2: Verify syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000026_grow_cuke_harvest.py').read()); print('syntax OK')"`

Expected: `syntax OK`

---

### Task 7: Write migration script — main function

**Files:**
- Modify: `migrations/20260401000026_grow_cuke_harvest.py`

- [ ] **Step 1: Add the main function and entry point after build_harvest_row**

```python
# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    gc = get_sheets()

    print("=" * 60)
    print("GROW CUKE HARVEST MIGRATION")
    print("=" * 60)

    clear_existing(supabase)
    ensure_containers(supabase)
    batch_lookup = build_batch_lookup(supabase)
    print(f"\n  Loaded {len(batch_lookup)} seed batch codes for lookup")

    # Load known cuke greenhouse site IDs for validation
    sites = (
        supabase.table("org_site")
        .select("id")
        .eq("farm_id", FARM_ID)
        .eq("org_site_subcategory_id", "greenhouse")
        .execute()
        .data
    )
    known_sites = {s["id"] for s in sites}

    print("\nReading grow_C_harvest...")
    ws = gc.open_by_key(GROW_SHEET_ID).worksheet("grow_C_harvest")
    records = ws.get_all_records()
    print(f"  {len(records)} sheet rows")

    rows = []
    skip_counts = {}
    unmatched_batches = set()

    for r in records:
        result = build_harvest_row(r, batch_lookup, known_sites)
        if "_skip" in result:
            reason = result["_skip"]
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            if reason == "unmatched_batch":
                unmatched_batches.add(result["_detail"])
            continue
        rows.append(result)

    print(f"\n  Built {len(rows)} harvest weight rows")
    for reason, count in sorted(skip_counts.items()):
        print(f"  Skipped {count} rows: {reason}")
    if unmatched_batches:
        print(f"  Unmatched batch codes ({len(unmatched_batches)}): {sorted(unmatched_batches)}")

    insert_rows(supabase, "grow_harvest_weight", rows)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify full script syntax**

Run: `python -c "import ast; ast.parse(open('migrations/20260401000026_grow_cuke_harvest.py').read()); print('syntax OK')"`

Expected: `syntax OK`

- [ ] **Step 3: Commit the migration script**

```bash
cd c:/Users/micha/Desktop/aloha-data-migrations
git add migrations/20260401000026_grow_cuke_harvest.py
git commit -m "Add grow_C_harvest migration script

Migrates ~4,872 harvest weigh-ins from legacy Google Sheet into
grow_harvest_weight. Upserts 6 pallet containers with tare regression
formulas per variety+grade. Links each harvest to its seed batch via
SeedingCycle + P/T suffix."
```

---

### Task 8: Run migration and verify

- [ ] **Step 1: Ensure the seeding migration has been run**

The harvest migration depends on `grow_seed_batch` rows existing. If not already run:

```bash
cd c:/Users/micha/Desktop/aloha-data-migrations
python migrations/20260401000025_grow_cuke_seeding.py
```

- [ ] **Step 2: Run the harvest migration**

```bash
python migrations/20260401000026_grow_cuke_harvest.py
```

Expected output:
```
============================================================
GROW CUKE HARVEST MIGRATION
============================================================

Clearing existing cuke harvest weights...
  Cleared

--- grow_harvest_container ---
  Upserted 6 rows: ['pallet_k1', 'pallet_k2', 'pallet_e1', 'pallet_e2', 'pallet_j1', 'pallet_j2']

  Loaded N seed batch codes for lookup

Reading grow_C_harvest...
  ~4872 sheet rows

  Built NNNN harvest weight rows
  Skipped N rows: ...

--- grow_harvest_weight ---
  Inserted NNNN rows

============================================================
DONE
============================================================
```

- [ ] **Step 3: Check for high skip/unmatched counts**

If `unmatched_batch` count is high (>100), investigate whether the SeedingCycle format in the harvest sheet doesn't match the batch_code format from the seeding migration. Common issues:
- Extra whitespace or case differences
- Missing `S-` prefix in one sheet but not the other
- Variety letter already embedded vs. not

- [ ] **Step 4: Re-run to verify idempotency**

```bash
python migrations/20260401000026_grow_cuke_harvest.py
```

Expected: Same output, same row counts. No duplicate key errors.
