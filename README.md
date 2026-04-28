# aloha-data-migrations

Owns both the **database schema** and the **Python data migration scripts** for
the Aloha agricultural ERP's Supabase project. `aloha-app` consumes this
database but no longer carries any schema of its own.

## What's in here

| Folder | Purpose |
|---|---|
| `supabase/migrations/` | **Authoritative DDL.** Tables, RLS policies, functions, triggers, views, seeds — every change to the database goes through here. CI auto-applies on merge to `main` (`.github/workflows/deploy-schema.yml`). |
| `supabase/config.toml` | Supabase CLI config. |
| `gsheets/migrations/` | Python ETL scripts that pull data from Google Sheets into Supabase nightly. See `_run_nightly.py`. |
| `docs/modules/` | Module-level frontend data-source briefs (e.g. `hr.md`). |
| `docs/processes/` | Workflow / process documentation. |
| `scripts/` | Helper shell scripts (e.g. `gen-types.sh`). |
| `generated/` | Generated artifacts (TypeScript types from the schema). |

## Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Set credentials in .env at the repo root
SUPABASE_URL=https://kfwqtaazdankxmdlqdak.supabase.co
SUPABASE_SERVICE_KEY=<service_role_key>
```

The service key can be found in the Supabase Dashboard → Settings → API.

## Running a migration

```bash
# From the repo root:
python gsheets/migrations/20260401000008_fsafe.py

# Or run the full nightly batch:
python gsheets/migrations/_run_nightly.py
```

Each script is **idempotent** (clear-and-reinsert) and **logs partial-failure
recovery info** if a batch fails.

## Safety

These scripts write directly to the production Supabase project. Before
running anything:

1. Confirm you're connected to the right Supabase URL
2. Read the script's docstring to understand what tables it touches
3. Check that the script is idempotent if you intend to re-run it

## Schema coupling

Schema and data migrations live side-by-side in this repo. When a Python
data-migration script needs a schema change, add the `.sql` file to
`supabase/migrations/` in the same PR — CI applies it on merge, and the
Python script that depends on it runs against the updated schema on the
next nightly.
