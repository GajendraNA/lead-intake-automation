#!/usr/bin/env bash
# Copies the n8n and leads databases from the local Kubernetes Postgres
# (namespace lead-intake) into Neon.
#
# Usage (from Git Bash, in the Automation_Learning folder):
#   cp render-deploy/.neon.env.example render-deploy/.neon.env   # then fill it in
#   bash render-deploy/migrate-to-neon.sh
#
# Add --dump-only to just write the dumps without touching Neon.
set -euo pipefail

NS=lead-intake
HERE="$(cd "$(dirname "$0")" && pwd)"
DUMP_ONLY=false
[ "${1:-}" = "--dump-only" ] && DUMP_ONLY=true

if ! $DUMP_ONLY; then
  [ -f "$HERE/.neon.env" ] || { echo "Missing render-deploy/.neon.env (copy .neon.env.example and fill it in)"; exit 1; }
  set -a; . "$HERE/.neon.env"; set +a
  : "${NEON_N8N_URL:?NEON_N8N_URL is empty in .neon.env}"
  : "${NEON_LEADS_URL:?NEON_LEADS_URL is empty in .neon.env}"
  command -v psql >/dev/null || { echo "psql not found on PATH"; exit 1; }
fi

mkdir -p "$HERE/dumps"
ts=$(date +%F_%H%M)

echo "Stopping local n8n so nothing writes during the dump..."
kubectl scale deployment/n8n -n "$NS" --replicas=0 >/dev/null
trap 'echo "Starting local n8n again..."; kubectl scale deployment/n8n -n "$NS" --replicas=1 >/dev/null' EXIT
kubectl wait --for=delete pod -l app=n8n -n "$NS" --timeout=90s >/dev/null 2>&1 || true

for db in n8n leads; do
  out="$HERE/dumps/$db-$ts.sql"
  echo "Dumping $db -> render-deploy/dumps/$(basename "$out")"
  kubectl exec -n "$NS" postgres-0 -- sh -c \
    "pg_dump -U \"\$POSTGRES_USER\" -d $db --no-owner --no-acl --clean --if-exists" > "$out"
done

$DUMP_ONLY && { echo "Dump only: done."; exit 0; }

echo "Restoring n8n into Neon..."
psql "$NEON_N8N_URL" -v ON_ERROR_STOP=1 -q -f "$HERE/dumps/n8n-$ts.sql" >/dev/null
echo "Restoring leads into Neon..."
psql "$NEON_LEADS_URL" -v ON_ERROR_STOP=1 -q -f "$HERE/dumps/leads-$ts.sql" >/dev/null

echo
echo "Check (should show 3 workflows, 4 credentials, and your leads count):"
psql "$NEON_N8N_URL" -Atc "select 'workflows', count(*) from workflow_entity union all select 'credentials', count(*) from credentials_entity"
psql "$NEON_LEADS_URL" -Atc "select 'leads', count(*) from leads"
echo "Done."
