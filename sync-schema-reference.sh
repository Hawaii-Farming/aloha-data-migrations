#!/usr/bin/env bash
# Re-copy the schema reference files from the sibling aloha-app repo.
#
# The schema source of truth lives in ../aloha-app. This repo keeps a local
# snapshot in schema-reference/ for offline browsing while writing migration
# scripts. Run this script whenever the schema changes upstream.
#
# Usage:
#   ./sync-schema-reference.sh

set -euo pipefail

ALOHA_APP="${ALOHA_APP_DIR:-../aloha-app}"

if [ ! -d "$ALOHA_APP/docs/schemas" ] || [ ! -d "$ALOHA_APP/supabase/migrations" ]; then
  echo "ERROR: aloha-app not found at $ALOHA_APP" >&2
  echo "  Set ALOHA_APP_DIR=/path/to/aloha-app to override the default sibling location." >&2
  exit 1
fi

echo "Syncing schema reference from $ALOHA_APP..."

rm -rf schema-reference/docs schema-reference/sql
mkdir -p schema-reference

cp -r "$ALOHA_APP/docs/schemas" schema-reference/docs
cp -r "$ALOHA_APP/supabase/migrations" schema-reference/sql

doc_count=$(find schema-reference/docs -name "*.md" | wc -l)
sql_count=$(find schema-reference/sql -name "*.sql" | wc -l)

echo "  $doc_count markdown docs"
echo "  $sql_count SQL migration files"
echo "Done."
