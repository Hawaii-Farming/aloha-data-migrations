# aloha-data-migrations

Standalone Python tooling for one-time data imports and ongoing data processes
that populate the Aloha agricultural ERP's Supabase database.

This repo was extracted from `aloha-app` so the TypeScript app and the Python
data tooling can evolve independently. The two repos share a Supabase project
but no code.

## What's in here

| Folder | Purpose |
|---|---|
| `migrations/` | One-time ETL scripts that imported legacy data from Google Sheets into Supabase. Already executed. Re-run only when seeding a fresh tenant or rebuilding from scratch. |
| `processes/` | Ongoing operational workflows (e.g. payroll). Run on a schedule or on-demand. |
| `python/` | Older one-off process scripts. Kept for reference. |
| `sql/` | One-shot SQL deploys (view contracts, test data seeding) run via Supabase SQL Editor. |
| `schema-reference/` | Read-only snapshot of the schema from `aloha-app` (10 markdown module docs + 102 SQL migrations). Browse here when writing a new migration script — no need to switch repos. |
| `MIGRATION_CONVENTIONS.md` | The rules every script in this repo must follow. |
| `sync-schema-reference.sh` | Pulls the latest schema docs and SQL from the sibling `aloha-app` repo into `schema-reference/`. Run whenever the schema changes upstream. |

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
python migrations/20260401000008_fsafe.py
```

Each script is **idempotent** (clear-and-reinsert) and **logs partial-failure
recovery info** if a batch fails. See `MIGRATION_CONVENTIONS.md` for the rules.

## Safety

These scripts write directly to the production Supabase project. Before
running anything:

1. Confirm you're connected to the right Supabase URL
2. Read the script's docstring to understand what tables it touches
3. Check that the script is idempotent if you intend to re-run it

## Schema coupling

The tables these scripts populate are defined in the `aloha-app` repo at
`supabase/migrations/`. **When the schema changes there, scripts here may
need updating.** There is no automatic sync — coordinate schema changes
across both repos.
