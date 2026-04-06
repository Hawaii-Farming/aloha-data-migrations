# Migration Script Conventions

These rules apply to every Python migration script in `scripts/migrations/`. All contributors must follow them.

---

## 1. File Structure

Every migration script follows this structure:

```
docstring → imports → env vars → constants → helpers → migration functions → main → __name__ guard
```

### Docstring

Every script begins with a docstring containing:
- Title (e.g. "Migrate Pack Data")
- One-line summary of what tables are migrated
- **Source:** Google Sheets URLs with tab names and row counts
- **Usage:** `python scripts/migrations/<filename>.py`
- **Rerunnable:** statement confirming clear-before-insert behavior

### File naming

Files use the same date prefix as SQL migrations: `YYYYMMDD000NNN_<module>.py`. The number places each script in dependency order relative to other migration scripts.

---

## 2. Boilerplate

Every script imports shared configuration from `scripts/migrations/_config.py` rather than redeclaring connection details, audit user, and org_id. The `_config.py` module loads `.env`, validates the service key, and exposes a single source of truth for sheet IDs.

```python
import re
import sys
from pathlib import Path

# Add this script's directory to sys.path so we can import _config regardless
# of where the script is invoked from (repo root vs scripts/migrations).
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

MY_SHEET_ID = SHEET_IDS["my_sheet_key"]
```

**Adding a new sheet** — register it in `_config.py` under `SHEET_IDS`, with an environment variable override so it can be pointed at a sandbox copy:

```python
SHEET_IDS = {
    "my_sheet_key": os.environ.get("SHEET_MY_KEY", "1XEwjbU_NKNmoUED4w5iuaGV_..."),
}
```

**Never hardcode** `AUDIT_USER`, `ORG_ID`, `SUPABASE_URL`, or sheet IDs directly in a migration script. Always pull them from `_config.py`. This keeps the values consistent across all scripts and makes them overridable for testing.

In `main()`, validate the service key once:

```python
def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())
    ...
```

`require_supabase_key()` raises `SystemExit` with a helpful message if `SUPABASE_SERVICE_KEY` is missing.

---

## 3. Standard Helper Functions

Every script includes these helper functions. They must be implemented identically across all scripts.

### to_id

Converts a display name to a TEXT primary key (lowercase, underscores, no special characters).

```python
def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""
```

### proper_case

Normalizes free-text display values to title case. Applied to all short display-name fields imported from Google Sheets (names, titles, categories, locations, methods). **Not** applied to IDs, codes, emails, enums, URLs, paragraph-length text, or JSONB arrays.

```python
def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()
```

### audit

Stamps `created_by` and `updated_by` with the migration service account email.

```python
def audit(row: dict) -> dict:
    """Add audit fields to a row."""
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row
```

### insert_rows

Inserts rows in batches of 100 to avoid Supabase payload limits. Always returns inserted data for downstream FK resolution. **Each batch is wrapped in try/except** so a failure prints which batch failed and how many rows were already committed before re-raising.

PostgREST does not support multi-statement transactions: each batch is committed independently, and a partial failure leaves earlier batches in the database. Recovery is via re-running the script — every script must be idempotent (clear-and-reinsert).

```python
def insert_rows(supabase, table: str, rows: list, upsert=False):
    """Insert (or upsert) rows in batches of 100.

    NOTE: PostgREST does not support multi-statement transactions, so each
    batch is committed independently. If a batch fails mid-way through, all
    earlier batches remain in the database. This script is rerunnable —
    re-running clears and reinserts all data, so partial failures recover by
    fixing the underlying issue and running the script again.

    On a batch failure this function prints which batch failed and how many
    rows were committed before re-raising the exception so the user knows
    exactly where things went wrong.
    """
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
```

### Date and timestamp parsing

```python
def parse_date(date_str):
    """Parse date string to YYYY-MM-DD or None."""
    if not date_str or not str(date_str).strip():
        return None
    from datetime import datetime
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def parse_timestamp(ts_str):
    """Parse timestamp to ISO format or None."""
    if not ts_str or not str(ts_str).strip():
        return None
    from datetime import datetime
    for fmt in ("%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%m/%d/%Y"):
        try:
            return datetime.strptime(str(ts_str).strip(), fmt).isoformat()
        except ValueError:
            continue
    return None
```

### Numeric parsing

```python
def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def safe_int(val, default=None):
    """Parse an integer value or return default."""
    try:
        v = str(val).strip().replace(",", "")
        return int(float(v)) if v else default
    except (ValueError, TypeError):
        return default
```

### Boolean parsing

```python
def parse_bool(val):
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")
```

### Google Sheets connection

```python
def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)
```

---

## 4. Data Cleaning Rules

### Text fields

| Field type | Treatment | Example |
|---|---|---|
| **Short display names** (name, title, category, location, method, person name) | `proper_case(val)` | "COOLER" → "Cooler" |
| **IDs and codes** (id, code, product codes) | `to_id(val)` or preserve original | Must stay lowercase |
| **Emails** | `.strip().lower()` | Must stay lowercase |
| **Enum/status values** (used in CHECK constraints) | `.strip().lower()` | "pending", "approved" |
| **Paragraph text** (description, notes, comments) | `.strip()` only | Leave casing as-is |
| **URLs and photo paths** | `.strip()` only | Leave as-is |
| **UOM codes** | Map through `uom_map` dict to sys_uom codes | "US Pounds" → "pound" |

### NULL handling

Empty strings from Google Sheets should be converted to `None` before insert:

```python
str(r.get("FieldName", "")).strip() or None
```

For `proper_case` fields, the function returns `None`-safe values — if the input is empty, it returns the original falsy value.

### Deduplication

When building lookup tables from sheet data, deduplicate by tracking seen IDs:

```python
seen = set()
for record in records:
    key = to_id(name)
    if key in seen:
        continue
    seen.add(key)
```

When multiple sheet rows map to the same record (e.g., same lot number), merge them by aggregating values rather than skipping duplicates.

---

## 5. Audit Fields

### Lookup/reference tables

For tables that are seeded once and not user-created (sys_*, org_*, hr_department, hr_title, hr_work_authorization, invnt_vendor, invnt_category, sales_product, etc.), use the `audit()` helper with `AUDIT_USER`:

```python
AUDIT_USER = "data@hawaiifarming.com"
rows.append(audit({
    "id": to_id(name),
    "org_id": ORG_ID,
    "name": proper_case(name),
}))
```

### Transactional tables

For tables that represent records originally created by real users (hr_employee, hr_time_off_request, invnt_po, maint_request, pack_lot, pack_lot_item, ops_task_tracker, etc.), **preserve the original email** from the sheet in `created_by` / `updated_by`. Fall back to `AUDIT_USER` only when the sheet has no email:

```python
reported_by = str(row.get("ReportedBy", "")).strip().lower() or AUDIT_USER
rows.append({
    "org_id": ORG_ID,
    # ... business fields ...
    "created_by": reported_by,
    "updated_by": reported_by,
})
```

Do **not** use `audit()` on transactional rows — set the emails explicitly.

### Workflow fields vs audit fields

Workflow fields (`requested_by`, `reviewed_by`, `ordered_by`, `fixer_id`, etc.) are **FK references to `hr_employee(id)`** and represent the person who performed a business action. They are resolved from sheet email addresses via lookup maps:

```python
email_to_emp = {emp["company_email"]: emp["id"] for emp in employees}
requested_by = email_to_emp.get(sheet_email.lower())
```

Audit fields (`created_by`, `updated_by`) are plain TEXT (no FK). For lookup tables they use `AUDIT_USER`; for transactional tables they preserve the original reporter's email from the source data.

---

## 6. Clear and Rerun

Every script is **rerunnable**: it clears existing data and reinserts from scratch on each run.

### FK dependency ordering

When clearing, delete child tables before parent tables (reverse FK order):

```python
# Clear children first
supabase.table("pack_lot_item").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
# Then parents
supabase.table("pack_lot").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
# Then referenced lookups
supabase.table("sales_product").delete().neq("id", "__none__").execute()
```

### Delete pattern

Supabase requires a filter on delete. Use a never-matching filter to delete all rows:

```python
# For UUID PK tables:
supabase.table("table").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()

# For TEXT PK tables:
supabase.table("table").delete().neq("id", "__none__").execute()
```

### Schema changes during migration

When adding or reordering columns on a table during the migration process, **drop and recreate** the table (and all its child tables) in Supabase so that the column order matches the `.sql` file exactly. Do not use `ALTER TABLE ADD COLUMN` — it appends the column at the end, breaking the intended column order.

1. Drop child tables first (FK order), then the parent
2. Recreate from the `.sql` migration files in order
3. Rerun the migration script to repopulate data

### Farm-scoped clearing

When a script only migrates data for a specific farm, clear only that farm's rows:

```python
supabase.table("pack_lot").delete().eq("farm_id", "lettuce").execute()
```

---

## 7. FK Resolution Strategies

### By ID derivation (deterministic)

When the PK is a TEXT derived from the name, compute it directly:

```python
farm_id = to_id(farm_name)  # "Lettuce" → "lettuce"
```

### By name/email lookup map

Build a dict from previously inserted data, then look up during insert:

```python
# Build map
item_by_name = {it["name"].lower(): it for it in item_result.data}

# Resolve
item = item_by_name.get(item_name.lower(), {})
item_id = item.get("id")
```

### By inserted data (UUID tables)

When parent rows have UUID PKs, capture inserted data from `insert_rows` return value:

```python
inserted_lots = insert_rows(supabase, "pack_lot", lot_rows)
lot_id = inserted_lots[idx]["id"]
```

### Two-pass pattern for self-referencing FKs

When a table references itself (e.g., `hr_employee.team_lead_id → hr_employee.id`):

1. First pass: insert all rows without the self-referencing FK
2. Second pass: update the self-referencing FK via individual updates

---

## 8. Google Sheets Access

- **Credentials:** Service account from `credentials.json` with `spreadsheets.readonly` scope
- **Library:** `gspread` with `google.oauth2.service_account.Credentials`
- **Data access:** `ws.get_all_records()` returns a list of dicts (header row becomes keys)
- **Single column:** `ws.col_values(n)[1:]` to skip header

When reading from multiple tabs in the same workbook, open the workbook once and access tabs individually:

```python
wb = gc.open_by_key(SHEET_ID)
ws1 = wb.worksheet("tab_one")
ws2 = wb.worksheet("tab_two")
```

---

## 9. Function Naming

| Pattern | Purpose | Example |
|---|---|---|
| `migrate_[table]` | Main migration function per table | `migrate_pack_lettuce` |
| `parse_[type]` | Parse raw values to typed output | `parse_date`, `parse_bool` |
| `safe_[type]` | Defensive numeric parsing | `safe_numeric`, `safe_int` |
| `get_[resource]` | Fetch data from external source | `get_sheets`, `get_sheet_records` |
| `to_[format]` | Convert between formats | `to_id` |
| `build_[structure]` | Construct complex values | `build_description`, `build_photos` |
| `map_[thing]` | Map legacy values to new codes | `map_uom` |

---

## 10. Main Function

```python
def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("=" * 60)
    print("MODULE NAME MIGRATION")
    print("=" * 60)

    # Step 1: Prerequisite lookups/inserts
    # Step 2: Main data migration
    # Step 3: Dependent data

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
```

---

## 11. Error Handling

### Never silently swallow exceptions

`except Exception: pass` is **forbidden**. If an operation might legitimately fail (e.g. clearing a table that has FK references from existing rows), catch the specific exception, **log what happened**, and explain why the script proceeds anyway.

```python
# WRONG — silent failure, hides real bugs
try:
    supabase.table("fsafe_lab_test").delete().neq("id", "__none__").execute()
except Exception:
    pass

# RIGHT — log the reason, make it visible
try:
    supabase.table("fsafe_lab_test").delete().neq("id", "__none__").execute()
    print("  Cleared fsafe_lab_test")
except Exception as e:
    # Table may have FK references from existing results; we fall through to
    # the upsert path below. Log so it's visible if something else is wrong.
    print(f"  Skipped clearing fsafe_lab_test (will upsert): {type(e).__name__}: {e}")
```

This rule applies to **every** `try/except` in a migration script. Catching narrow exception types (`ValueError`, `TypeError`, `FileNotFoundError`) for parsing helpers is fine — those have a known recovery path. Catching `Exception` is only acceptable when you log it.

### Partial failure recovery

Because PostgREST has no multi-statement transactions, a script can fail halfway through and leave the database with some batches committed. The recovery contract is:

1. The failing batch is logged with batch number, row range, and exception
2. The script re-raises so the user sees the error
3. The user fixes the underlying issue (bad data, schema drift, FK violation)
4. The user re-runs the script — the clear-and-reinsert pattern handles cleanup

This contract requires every script to be **strictly rerunnable**. If a script appends instead of clearing, partial-failure recovery breaks.

### Inline batch inserts

If a script does inline batch inserts (not using `insert_rows`, e.g. `012_business_rule.py`), it must apply the same try/except + batch logging pattern:

```python
total_batches = (len(RULES) + 99) // 100
inserted = 0
for i in range(0, len(RULES), 100):
    batch = RULES[i:i + 100]
    batch_num = (i // 100) + 1
    try:
        supabase.table("org_business_rule").insert(batch).execute()
        inserted += len(batch)
    except Exception as e:
        print(
            f"  ERROR on batch {batch_num}/{total_batches} "
            f"(rows {i + 1}-{i + len(batch)}): {type(e).__name__}: {e}"
        )
        print(f"  {inserted} rows committed before failure")
        print(f"  Re-run the script to retry — it is idempotent.")
        raise
```

---

## 12. Checklist for New Migration Scripts

Before writing a new migration script, verify:

- [ ] Docstring includes title, source URLs, usage, and rerunnable note
- [ ] All helper functions match the canonical implementations in this document
- [ ] All short display-name fields use `proper_case()`
- [ ] All rows pass through `audit()` before insert
- [ ] `insert_rows` batches at 100 rows, wraps each batch in try/except, and returns inserted data
- [ ] No `except Exception: pass` blocks — every caught exception is logged with `type(e).__name__: {e}`
- [ ] Inline batch inserts (not using `insert_rows`) follow the same try/except + batch logging pattern (Section 11)
- [ ] Clear logic follows FK dependency order (children before parents)
- [ ] FK resolution uses lookup maps, not hardcoded values
- [ ] Emails are lowercased; IDs use `to_id()`; enums are lowercase
- [ ] Sheet IDs come from `SHEET_IDS` in `_config.py`, not hardcoded inline
- [ ] `AUDIT_USER`, `ORG_ID`, `SUPABASE_URL` imported from `_config.py` (never redeclared)
- [ ] `main()` calls `create_client(SUPABASE_URL, require_supabase_key())`
- [ ] `get_sheets()` is used for Google Sheets connection (not inline credential loading)
