#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/kartochki}"
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_FILE:-$APP_DIR/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-yandex_disk}"
YANDEX_DISK_USERNAME="${YANDEX_DISK_USERNAME:-}"
YANDEX_DISK_APP_PASSWORD="${YANDEX_DISK_APP_PASSWORD:-}"

if [ -z "$YANDEX_DISK_USERNAME" ]; then
  echo "YANDEX_DISK_USERNAME is required"
  exit 1
fi

if [ -z "$YANDEX_DISK_APP_PASSWORD" ]; then
  echo "YANDEX_DISK_APP_PASSWORD is required"
  exit 1
fi

install -d -m 0755 "$APP_DIR"

OBSCURED_PASSWORD="$(rclone obscure "$YANDEX_DISK_APP_PASSWORD")"

cat > "$RCLONE_CONFIG_FILE" <<EOF
[$RCLONE_REMOTE]
type = webdav
url = https://webdav.yandex.ru
vendor = yandex
user = $YANDEX_DISK_USERNAME
pass = $OBSCURED_PASSWORD
EOF

chmod 0600 "$RCLONE_CONFIG_FILE"
chown --reference="$APP_DIR" "$RCLONE_CONFIG_FILE" 2>/dev/null || true

rclone --config "$RCLONE_CONFIG_FILE" lsd "$RCLONE_REMOTE:" >/dev/null

echo "Yandex Disk rclone config written to $RCLONE_CONFIG_FILE"
