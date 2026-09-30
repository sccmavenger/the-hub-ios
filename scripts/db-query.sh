#!/usr/bin/env bash
# Query The Hub's Supabase database (project fnlufxhznqclpajyadcc) via the
# Management API — equivalent to running SQL in the dashboard's SQL editor,
# including access to auth.users and applying migrations.
#
# Usage:
#   scripts/db-query.sh "select email from auth.users"
#   scripts/db-query.sh < supabase/006-ncaa-readiness.sql
#
# Auth: a Supabase personal access token, read from $SUPABASE_ACCESS_TOKEN,
# .secrets/supabase-token (gitignored, next to this repo's root), or
# ~/.config/the-hub/supabase-token. Create one at
# https://supabase.com/dashboard/account/tokens — never commit it.
set -euo pipefail

PROJECT_REF="fnlufxhznqclpajyadcc"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
for candidate in "$REPO_ROOT/.secrets/supabase-token" "$HOME/.config/the-hub/supabase-token"; do
  if [[ -z "$TOKEN" && -f "$candidate" ]]; then
    TOKEN="$(tr -d '[:space:]' < "$candidate")"
  fi
done
if [[ -z "$TOKEN" ]]; then
  echo "No Supabase access token found." >&2
  echo "Create one at https://supabase.com/dashboard/account/tokens, then run:" >&2
  echo "  mkdir -p $REPO_ROOT/.secrets && echo 'sbp_YOUR_TOKEN' > $REPO_ROOT/.secrets/supabase-token && chmod 600 $REPO_ROOT/.secrets/supabase-token" >&2
  exit 1
fi

if [[ $# -ge 1 ]]; then
  QUERY="$1"
else
  QUERY="$(cat)"
fi

jq -n --arg q "$QUERY" '{query: $q}' \
  | curl -sS -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/query" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data @- \
  | jq .
