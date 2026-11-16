#!/usr/bin/env bash
# Backup: Postgres dump + n8n data volume. Deletes backups older than KEEP_DAYS (default 14).
# Run manually or from cron. Copy the backups folder off this server as well.
set -euo pipefail

cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
source .env
set +a

BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%F_%H%M)"

mkdir -p "$BACKUP_DIR"
ABS_BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"

echo "Dumping Postgres database '$POSTGRES_DB'..."
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > "$ABS_BACKUP_DIR/n8n-db-$STAMP.sql.gz"

echo "Archiving the n8n data volume..."
docker run --rm \
  -v n8n-kit_n8n_data:/data:ro \
  -v "$ABS_BACKUP_DIR":/backup \
  alpine tar czf "/backup/n8n-data-$STAMP.tar.gz" -C /data .

echo "Removing backups older than $KEEP_DAYS days..."
find "$ABS_BACKUP_DIR" -type f -name 'n8n-*' -mtime +"$KEEP_DAYS" -delete

echo "Done: $ABS_BACKUP_DIR"
echo "Reminder: keep .env (it holds the encryption key) in a password manager, not next to these backups."
