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

wait_healthy() {
  local service="$1"
  local timeout_seconds="${2:-120}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    container_id="$(docker compose ps -q "$service" 2>/dev/null | head -n 1)"
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
  docker compose ps "$service" || true
  exit 1
}

case "$SERVICE" in
  all)
    require_non_empty_file .env
    require_non_empty_file backend.env
    require_non_empty_file frontend.env
    require_non_empty_file postgres.env
    docker compose pull
    docker compose up -d postgres redis
    wait_healthy postgres
    wait_healthy redis
    docker compose run --rm migrate
    docker compose up -d --no-deps backend
    wait_healthy backend
    docker compose up -d frontend
    docker compose up -d --no-deps caddy
    ;;
  frontend)
    require_non_empty_file .env
    require_non_empty_file frontend.env
    docker compose pull frontend
    docker compose up -d frontend
    ;;
  backend)
    require_non_empty_file .env
    require_non_empty_file backend.env
    require_non_empty_file postgres.env
    docker compose pull backend
    docker compose up -d postgres redis
    wait_healthy postgres
    wait_healthy redis
    docker compose run --rm migrate
    docker compose up -d --no-deps backend
    wait_healthy backend
    ;;
  caddy)
    require_non_empty_file .env
    docker compose pull caddy || true
    if [ -n "$(docker compose ps -q backend 2>/dev/null)" ] && [ -n "$(docker compose ps -q frontend 2>/dev/null)" ]; then
      docker compose up -d caddy
    else
      docker compose up -d --no-deps caddy
    fi
    ;;
  postgres)
    require_non_empty_file postgres.env
    docker compose pull postgres || true
    docker compose up -d postgres
    ;;
  redis)
    docker compose pull redis || true
    docker compose up -d redis
    ;;
  *)
    echo "Usage: $0 [all|frontend|backend|caddy|postgres|redis]"
    exit 1
    ;;
esac

docker image prune -f
