#!/usr/bin/env bash
# Install into a prepared writable app directory; never replace secrets or start containers.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-/opt/kartochki}"
[[ -d "$APP_DIR" && -w "$APP_DIR" ]] || { echo 'Prepare APP_DIR via vps-infra first'; exit 2; }
exec 9>"$APP_DIR/.deploy.lock"
flock -w 120 9
install -m 0644 "$ROOT/docker-compose.prod.yml" "$APP_DIR/docker-compose.yml"
for script in deploy backup-postgres backup-all-to-yandex-disk backup-postgres-to-yandex-disk setup-yandex-disk-rclone setup-backups install-backup-rclone; do
  install -m 0755 "$ROOT/scripts/$script.sh" "$APP_DIR/$script.sh"
done
echo 'Restore private env/config files and data before starting the project.'
