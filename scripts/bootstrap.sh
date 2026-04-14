#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-arzhannikov_bot}"
APP_DIR="${APP_DIR:-/opt/kartochki}"
DEPLOY_PUBLIC_KEY="${DEPLOY_PUBLIC_KEY:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg ufw fail2ban unattended-upgrades rclone

install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
systemctl enable --now fail2ban
systemctl enable --now unattended-upgrades

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi

usermod -aG docker "$DEPLOY_USER"

install -d -m 0755 "$APP_DIR"
chown "$DEPLOY_USER:$DEPLOY_USER" "$APP_DIR"

if [ -n "$DEPLOY_PUBLIC_KEY" ]; then
  USER_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
  install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$USER_HOME/.ssh"
  touch "$USER_HOME/.ssh/authorized_keys"
  chmod 0600 "$USER_HOME/.ssh/authorized_keys"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$USER_HOME/.ssh/authorized_keys"
  if ! grep -qxF "$DEPLOY_PUBLIC_KEY" "$USER_HOME/.ssh/authorized_keys"; then
    echo "$DEPLOY_PUBLIC_KEY" >> "$USER_HOME/.ssh/authorized_keys"
  fi
fi

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "Bootstrap finished."
echo "Deploy user: $DEPLOY_USER"
echo "App dir: $APP_DIR"
echo "Root/password SSH settings were not changed."
