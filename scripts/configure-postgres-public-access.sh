#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/kartochki}"
POSTGRES_PUBLIC_PORT="${POSTGRES_PUBLIC_PORT:-5432}"

cd "$APP_DIR"

load_dotenv_value() {
  local name="$1"
  local current_value="${!name:-}"
  if [ -n "$current_value" ] || [ ! -f .env ]; then
    return 0
  fi

  local line
  local value
  line="$(grep -E "^${name}=" .env | tail -n 1 || true)"
  if [ -n "$line" ]; then
    value="${line#*=}"
    value="${value%$'\r'}"
    export "$name=$value"
  fi
}

load_dotenv_value POSTGRES_PUBLIC_ALLOWED_CIDR

PUBLIC_INTERFACE="${POSTGRES_PUBLIC_INTERFACE:-}"
if [ -z "$PUBLIC_INTERFACE" ]; then
  PUBLIC_INTERFACE="$(ip route show default | awk '{print $5; exit}')"
fi

if [ -z "$PUBLIC_INTERFACE" ]; then
  echo "Could not detect public network interface."
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root because it changes iptables and systemd."
  exit 1
fi

CHAIN="KARTOCHKI_POSTGRES_PUBLIC"

remove_docker_user_jump() {
  while iptables -D DOCKER-USER -i "$PUBLIC_INTERFACE" -p tcp --dport "$POSTGRES_PUBLIC_PORT" -j "$CHAIN" 2>/dev/null; do :; done
}

block_postgres_public_access() {
  iptables -N DOCKER-USER 2>/dev/null || true
  iptables -N "$CHAIN" 2>/dev/null || true
  iptables -F "$CHAIN"
  remove_docker_user_jump
  iptables -I DOCKER-USER 1 -i "$PUBLIC_INTERFACE" -p tcp --dport "$POSTGRES_PUBLIC_PORT" -j "$CHAIN"
  iptables -A "$CHAIN" -j DROP
}

install_systemd_service() {
  if [ "${INSTALL_SYSTEMD_SERVICE:-1}" != "1" ] || ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  cat >/etc/systemd/system/kartochki-postgres-public-access.service <<EOF
[Unit]
Description=Restrict public PostgreSQL access for kartochki.online
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
Environment=APP_DIR=$APP_DIR
Environment=POSTGRES_PUBLIC_ALLOWED_CIDR=$POSTGRES_PUBLIC_ALLOWED_CIDR
Environment=POSTGRES_PUBLIC_PORT=$POSTGRES_PUBLIC_PORT
Environment=POSTGRES_PUBLIC_INTERFACE=$PUBLIC_INTERFACE
Environment=INSTALL_SYSTEMD_SERVICE=0
ExecStart=/usr/bin/env bash $APP_DIR/configure-postgres-public-access.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable kartochki-postgres-public-access.service >/dev/null
}

if [ -z "${POSTGRES_PUBLIC_ALLOWED_CIDR:-}" ]; then
  block_postgres_public_access
  install_systemd_service
  rm -f "$APP_DIR/.postgres-public-access-configured"
  echo "PostgreSQL public access is disabled."
  exit 0
fi

CIDR_ADDRESS="${POSTGRES_PUBLIC_ALLOWED_CIDR%/*}"
CIDR_PREFIX="${POSTGRES_PUBLIC_ALLOWED_CIDR##*/}"
if ! [[ "$CIDR_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || ! [[ "$CIDR_PREFIX" =~ ^[0-9]+$ ]] || [ "$CIDR_PREFIX" -gt 32 ]; then
  echo "POSTGRES_PUBLIC_ALLOWED_CIDR must be an IPv4 CIDR value, for example 198.51.100.10/32"
  exit 1
fi
IFS=. read -r octet1 octet2 octet3 octet4 <<< "$CIDR_ADDRESS"
for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
  if [ "$octet" -gt 255 ]; then
    echo "POSTGRES_PUBLIC_ALLOWED_CIDR contains an invalid IPv4 address"
    exit 1
  fi
done

configure_docker_user_rules() {
  iptables -N DOCKER-USER 2>/dev/null || true
  iptables -N "$CHAIN" 2>/dev/null || true
  iptables -F "$CHAIN"

  # Docker-published ports can bypass UFW, so the allowlist is also enforced
  # in DOCKER-USER before Docker's own forwarding rules.
  remove_docker_user_jump
  iptables -I DOCKER-USER 1 -i "$PUBLIC_INTERFACE" -p tcp --dport "$POSTGRES_PUBLIC_PORT" -j "$CHAIN"

  iptables -A "$CHAIN" -s "$POSTGRES_PUBLIC_ALLOWED_CIDR" -j ACCEPT
  iptables -A "$CHAIN" -j DROP
}

configure_docker_user_rules
install_systemd_service
printf '%s' "$POSTGRES_PUBLIC_ALLOWED_CIDR" > "$APP_DIR/.postgres-public-access-configured"
chmod 0644 "$APP_DIR/.postgres-public-access-configured"

echo "PostgreSQL public access is allowed only from $POSTGRES_PUBLIC_ALLOWED_CIDR on $PUBLIC_INTERFACE:$POSTGRES_PUBLIC_PORT."
