#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/kartochki}"
SERVICE="${1:-all}"

cd "$APP_DIR"

if [ ! -f docker-compose.yml ]; then
  echo "docker-compose.yml was not found in $APP_DIR"
  exit 1
fi

ensure_env_files_exist() {
  touch .env backend.env frontend.env postgres.env
  chmod 0600 .env backend.env frontend.env postgres.env
}

require_non_empty_file() {
  local file="$1"
  if [ ! -s "$file" ]; then
    echo "$file is required and must not be empty"
    exit 1
  fi
}

ensure_env_files_exist

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

require_postgres_public_firewall() {
  if [ -z "${POSTGRES_PUBLIC_ALLOWED_CIDR:-}" ]; then
    return 0
  fi

  local marker=".postgres-public-access-configured"
  if [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$POSTGRES_PUBLIC_ALLOWED_CIDR" ]; then
    echo "Run sudo bash ./configure-postgres-public-access.sh before publishing PostgreSQL"
    exit 1
  fi
}

COMPOSE_FILES=(-f docker-compose.yml)
if [ -n "${POSTGRES_PUBLIC_ALLOWED_CIDR:-}" ]; then
  if [ ! -f docker-compose.postgres-public.yml ]; then
    echo "docker-compose.postgres-public.yml is required when POSTGRES_PUBLIC_ALLOWED_CIDR is set"
    exit 1
  fi
  COMPOSE_FILES+=(-f docker-compose.postgres-public.yml)
fi

compose() {
  docker compose "${COMPOSE_FILES[@]}" "$@"
}

wait_healthy() {
  local service="$1"
  local timeout_seconds="${2:-120}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    container_id="$(compose ps -q "$service" 2>/dev/null | head -n 1)"
    status=""
    if [ -n "$container_id" ]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
    fi
    if [ "$status" = "healthy" ]; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "$service did not become healthy within ${timeout_seconds}s"
  compose ps "$service" || true
  exit 1
}

start_caddy_if_ready() {
  if [ -s .env ] && [ -s backend.env ] && [ -s frontend.env ]; then
    compose up -d --no-deps caddy
  fi
}

case "$SERVICE" in
  all)
    require_non_empty_file .env
    require_non_empty_file backend.env
    require_non_empty_file frontend.env
    require_non_empty_file postgres.env
    require_postgres_public_firewall
    compose pull
    compose up -d postgres redis
    wait_healthy postgres
    wait_healthy redis
    compose run --rm migrate
    compose run --rm blogsync
    compose up -d --no-deps backend
    wait_healthy backend
    compose up -d frontend
    compose up -d --no-deps caddy
    ;;
  frontend)
    require_non_empty_file .env
    require_non_empty_file frontend.env
    compose pull frontend
    compose up -d frontend
    start_caddy_if_ready
    ;;
  backend)
    require_non_empty_file .env
    require_non_empty_file backend.env
    require_non_empty_file postgres.env
    require_postgres_public_firewall
    compose pull backend
    compose up -d postgres redis
    wait_healthy postgres
    wait_healthy redis
    compose run --rm migrate
    compose run --rm blogsync
    compose up -d --no-deps backend
    wait_healthy backend
    start_caddy_if_ready
    ;;
  caddy)
    require_non_empty_file .env
    compose pull caddy || true
    if [ -n "$(compose ps -q backend 2>/dev/null)" ] && [ -n "$(compose ps -q frontend 2>/dev/null)" ]; then
      compose up -d caddy
    else
      compose up -d --no-deps caddy
    fi
    ;;
  postgres)
    require_non_empty_file postgres.env
    require_postgres_public_firewall
    compose pull postgres || true
    compose up -d postgres
    ;;
  redis)
    compose pull redis || true
    compose up -d redis
    ;;
  *)
    echo "Usage: $0 [all|frontend|backend|caddy|postgres|redis]"
    exit 1
    ;;
esac

docker image prune -f
