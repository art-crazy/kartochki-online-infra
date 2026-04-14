#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/kartochki}"
BACKUP_DIR="${BACKUP_DIR:-/opt/kartochki/backups/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

cd "$APP_DIR"
mkdir -p "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/kartochki-postgres-$(date +%F-%H%M%S).sql.gz"

docker compose exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "$BACKUP_FILE"
find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

echo "$BACKUP_FILE"
