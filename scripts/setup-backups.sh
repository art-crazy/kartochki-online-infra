#!/usr/bin/env bash
set -euo pipefail
[[ "$EUID" == 0 ]] || { echo 'Run as root' >&2; exit 1; }
APP_DIR="${APP_DIR:-/opt/kartochki}"
DEPLOY_USER="${DEPLOY_USER:-$(stat -c %U "$APP_DIR")}"
[[ "$APP_DIR" == /opt/kartochki ]] || { echo 'Units currently require APP_DIR=/opt/kartochki' >&2; exit 1; }
id "$DEPLOY_USER" >/dev/null
[[ -s "$APP_DIR/rclone.conf" ]] || { echo 'Configure Yandex Disk first' >&2; exit 1; }
[[ -x "$APP_DIR/backup-all-to-yandex-disk.sh" ]] || { echo 'Install the backup scripts first' >&2; exit 1; }

cat > /etc/systemd/system/kartochki-backup.service <<EOF
[Unit]
Description=Kartochki PostgreSQL and media backup to Yandex Disk
Wants=network-online.target
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
User=$DEPLOY_USER
WorkingDirectory=/opt/kartochki
Environment=APP_DIR=/opt/kartochki
ExecStart=/bin/bash /opt/kartochki/backup-all-to-yandex-disk.sh
TimeoutStartSec=30min
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UMask=0077
NoNewPrivileges=true
EOF
cat > /etc/systemd/system/kartochki-backup.timer <<'EOF'
[Unit]
Description=Daily Kartochki backup at 03:15 Moscow

[Timer]
OnCalendar=*-*-* 03:15:00 Europe/Moscow
Persistent=true
RandomizedDelaySec=5min
Unit=kartochki-backup.service

[Install]
WantedBy=timers.target
EOF
systemd-analyze verify /etc/systemd/system/kartochki-backup.service /etc/systemd/system/kartochki-backup.timer
systemctl daemon-reload
systemctl enable --now kartochki-backup.timer
systemctl list-timers kartochki-backup.timer --no-pager
