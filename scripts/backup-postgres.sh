#!/usr/bin/env bash
set -euo pipefail
umask 077

APP_DIR="${APP_DIR:-/opt/kartochki}"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/backups/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || { echo 'Invalid RETENTION_DAYS' >&2; exit 2; }
cd "$APP_DIR"
install -d -m 700 "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/kartochki-postgres-$(date -u +%Y%m%dT%H%M%S)-$$.sql.gz"
partial="$BACKUP_FILE.partial"
trap 'rm -f -- "$partial"' EXIT

docker compose exec -T postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --no-owner --no-acl -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "$partial"
gzip -t "$partial"
mv -- "$partial" "$BACKUP_FILE"
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'kartochki-postgres-*.sql.gz' -mtime +"$RETENTION_DAYS" -delete
printf '%s\n' "$BACKUP_FILE"
