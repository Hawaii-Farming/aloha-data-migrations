# Supabase Schema Migrations

**This directory is the source of truth for the production database schema.**

Every file here is a Supabase CLI migration (DDL, RLS policies, functions,
triggers, seeds). When a file lands on `main`, the `Deploy Supabase Schema`
GitHub Actions workflow picks it up and runs `supabase db push` against the
project — so new migrations ship automatically.

## Conventions

- Filenames: `YYYYMMDDHHMMSS_<snake_case_name>.sql` (Supabase CLI format).
  Lexical order = apply order. Never renumber an already-applied file.
- One logical change per file. Keep it small enough to reason about.
- Idempotent where possible (`CREATE TABLE IF NOT EXISTS`, `DROP ... IF EXISTS`).
- If a change needs rollback, write a second migration that reverses it; do
  not edit the original after it has been applied.

## Local workflow

```bash
# Create a new migration (fills in the datestamp for you)
supabase migration new <snake_case_name>

# Apply everything to your local Supabase stack
supabase start
supabase db reset

# Test. When happy, commit and push. CI applies to production on merge to main.
```

## CI deploy

See [`.github/workflows/deploy-schema.yml`](../../.github/workflows/deploy-schema.yml).

Required repo secrets:

- `SUPABASE_ACCESS_TOKEN` — personal access token from
  [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens).
- `SUPABASE_PROJECT_REF` — the project id (the subdomain of your project URL,
  e.g. `kfwqtaazdankxmdlqdak` from `https://kfwqtaazdankxmdlqdak.supabase.co`).
- `SUPABASE_DB_PASSWORD` — the database password used by `supabase db push`.

## History

This directory was consolidated on 2026-04-22 from the former
`aloha-app/supabase/migrations/` location. The app repo no longer carries
schema; all schema lives here and deploys from here.
