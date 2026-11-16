#!/usr/bin/env bash
# Restore a Postgres dump into the running stack.
# WARNING: this replaces the current n8n database. Use the same N8N_ENCRYPTION_KEY as the backup.
# Usage: scripts/restore.sh backups/n8n-db-YYYY-MM-DD_HHMM.sql.gz
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
source .env
set +a

FILE="${1:?Usage: scripts/restore.sh backups/n8n-db-YYYY-MM-DD_HHMM.sql.gz}"
[ -f "$FILE" ] || { echo "File not found: $FILE"; exit 1; }

read -r -p "This replaces database '$POSTGRES_DB'. Type YES to continue: " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "Cancelled."; exit 1; }

# Stop n8n processes (the worker only exists in queue mode).
docker compose stop n8n
docker compose stop n8n-worker 2>/dev/null || true

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\";"
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"

gunzip -c "$FILE" | docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

docker compose start n8n
docker compose start n8n-worker 2>/dev/null || true
echo "Restore finished. Check: docker compose logs n8n --tail 30"
