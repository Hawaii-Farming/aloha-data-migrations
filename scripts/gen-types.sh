#!/usr/bin/env bash
# Generate database.types.ts from the linked hosted Supabase project.
# Output is committed to generated/database.types.ts and consumed by
# aloha-app via its sync:types script.
#
# Prereq (one-time): `npx supabase link --project-ref <ref>` from the repo root.

set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p generated

npx supabase gen types --lang typescript --linked > generated/database.types.ts

echo "Wrote generated/database.types.ts ($(wc -l < generated/database.types.ts) lines)"
