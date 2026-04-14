#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/kartochki}"
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_FILE:-$APP_DIR/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-yandex_disk}"
RCLONE_REMOTE_PATH="${RCLONE_REMOTE_PATH:-kartochki-online/postgres}"
REMOTE_RETENTION_DAYS="${REMOTE_RETENTION_DAYS:-30}"

cd "$APP_DIR"

if [ ! -f "$RCLONE_CONFIG_FILE" ]; then
  echo "rclone config not found: $RCLONE_CONFIG_FILE"
  echo "Run setup-yandex-disk-rclone.sh first."
  exit 1
fi

BACKUP_OUTPUT="$(./backup-postgres.sh)"
BACKUP_FILE="$(printf "%s\n" "$BACKUP_OUTPUT" | tail -n 1)"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "backup file was not created: $BACKUP_FILE"
  exit 1
fi

rclone --config "$RCLONE_CONFIG_FILE" mkdir "$RCLONE_REMOTE:$RCLONE_REMOTE_PATH"
rclone --config "$RCLONE_CONFIG_FILE" copy "$BACKUP_FILE" "$RCLONE_REMOTE:$RCLONE_REMOTE_PATH"
rclone --config "$RCLONE_CONFIG_FILE" delete "$RCLONE_REMOTE:$RCLONE_REMOTE_PATH" --min-age "${REMOTE_RETENTION_DAYS}d" --include "*.sql.gz"
rclone --config "$RCLONE_CONFIG_FILE" rmdirs "$RCLONE_REMOTE:$RCLONE_REMOTE_PATH" --leave-root

echo "Uploaded to $RCLONE_REMOTE:$RCLONE_REMOTE_PATH/$(basename "$BACKUP_FILE")"
