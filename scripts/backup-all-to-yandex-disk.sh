#!/usr/bin/env bash
set -euo pipefail
umask 077

APP_DIR="${APP_DIR:-/opt/kartochki}"
cd "$APP_DIR"
exec 9>.backup.lock
flock -w 5 9 || { echo 'Another backup is running' >&2; exit 1; }

# The setup workflow writes this shell-escaped file; never print its contents.
if [[ -s yandex-disk.env ]]; then
  set -a
  . ./yandex-disk.env
  set +a
fi
RCLONE_CONFIG_FILE="${RCLONE_CONFIG_FILE:-$APP_DIR/rclone.conf}"
RCLONE_REMOTE="${RCLONE_REMOTE:-yandex_disk}"
RCLONE_FULL_REMOTE_PATH="${RCLONE_FULL_REMOTE_PATH:-kartochki-online/complete}"
FULL_BACKUP_DIR="${FULL_BACKUP_DIR:-$APP_DIR/backups/complete}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
REMOTE_RETENTION_DAYS="${REMOTE_RETENTION_DAYS:-30}"
for days in "$RETENTION_DAYS" "$REMOTE_RETENTION_DAYS"; do
  [[ "$days" =~ ^[0-9]+$ ]] || { echo 'Invalid backup retention' >&2; exit 2; }
done
[[ -s "$RCLONE_CONFIG_FILE" ]] || { echo 'Missing rclone config' >&2; exit 1; }
install -d -m 700 "$FULL_BACKUP_DIR"
stage="$(mktemp -d "$FULL_BACKUP_DIR/.staging.XXXXXX")"
name="kartochki-complete-$(date -u +%Y%m%dT%H%M%S)-$$.tar.gz"
archive="$FULL_BACKUP_DIR/$name"
cleanup() { rm -rf -- "$stage"; rm -f -- "$archive.partial"; }
trap cleanup EXIT

# Capture the DB first and media second. The live application is not stopped.
db_backup="$(bash ./backup-postgres.sh)"
cp -- "$db_backup" "$stage/database.sql.gz"
docker compose exec -T backend tar -C /app/storage -czf - . > "$stage/storage.tar.gz"
gzip -t "$stage/database.sql.gz"
tar -tzf "$stage/storage.tar.gz" >/dev/null
date -u +%FT%TZ > "$stage/created-at.txt"
docker compose images --format json > "$stage/images.json"
(
  cd "$stage"
  sha256sum database.sql.gz storage.tar.gz created-at.txt images.json > SHA256SUMS
)
tar -czf "$archive.partial" -C "$stage" .
tar -tzf "$archive.partial" >/dev/null
mv -- "$archive.partial" "$archive"
local_hash="$(sha256sum "$archive" | cut -d ' ' -f 1)"
remote="$RCLONE_REMOTE:$RCLONE_FULL_REMOTE_PATH"
rclone_cmd=(rclone --config "$RCLONE_CONFIG_FILE" --contimeout 10s --timeout 60s --retries 3 --low-level-retries 3)
"${rclone_cmd[@]}" copyto "$archive" "$remote/$name" --immutable
# WebDAV does not consistently supply hashes: verify the actual remote bytes.
remote_hash="$("${rclone_cmd[@]}" cat "$remote/$name" | sha256sum | cut -d ' ' -f 1)"
[[ "$remote_hash" == "$local_hash" ]] || { echo 'Remote checksum mismatch' >&2; exit 1; }
printf '%s  %s\n' "$local_hash" "$name" > "$archive.sha256"
"${rclone_cmd[@]}" copyto "$archive.sha256" "$remote/$name.sha256" --immutable

# Prune only after both the upload and its read-back verification succeeded.
"${rclone_cmd[@]}" delete "$remote" --min-age "${REMOTE_RETENTION_DAYS}d" --include 'kartochki-complete-*.tar.gz' --include 'kartochki-complete-*.tar.gz.sha256'
find "$FULL_BACKUP_DIR" -maxdepth 1 -type f \( -name 'kartochki-complete-*.tar.gz' -o -name 'kartochki-complete-*.tar.gz.sha256' \) -mtime +"$RETENTION_DAYS" -delete
printf '%s\n%s\n%s\n' "$(date -u +%FT%TZ)" "$remote/$name" "$local_hash" > "$FULL_BACKUP_DIR/.last-success.partial"
mv -- "$FULL_BACKUP_DIR/.last-success.partial" "$FULL_BACKUP_DIR/last-success"
echo "Verified backup: $remote/$name (SHA256 $local_hash)"
