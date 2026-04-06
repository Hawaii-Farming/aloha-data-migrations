# Schema Reference

This is a **read-only snapshot** of the schema from the `aloha-app` repo,
copied here so migration scripts can be written without context-switching to
another repo.

## Folders

- **`docs/`** — Per-module markdown documentation (10 files). Each file
  describes the tables in one module with column types, constraints,
  relationships, and a Mermaid ERD. Start here when writing a new script.

- **`sql/`** — The 102 SQL migration files that define the actual schema.
  These are the source of truth — if a doc and a SQL file disagree, the SQL
  is correct. Use these to verify exact column names, types, defaults, and
  FK constraint names.

## Keeping it in sync

The contents of this folder are **not** edited here. They get re-copied from
the sibling `aloha-app` repo whenever the schema changes upstream:

```bash
./sync-schema-reference.sh
```

The sync script assumes `aloha-app` is checked out as a sibling directory
(`../aloha-app`). Override with `ALOHA_APP_DIR=/path/to/aloha-app` if not.

## Don't edit files here

Any changes to schema files in this folder will be overwritten on the next
sync. If you need to change the schema, do it in `aloha-app/supabase/migrations/`
and `aloha-app/docs/schemas/`, then run the sync.
