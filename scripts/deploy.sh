#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/kartochki}"
SERVICE="${1:-all}"

cd "$APP_DIR"
[[ -O . ]] || { echo "Run deployment as the owner of $APP_DIR" >&2; exit 2; }
exec 9>.deploy.lock
flock -w 120 9

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

compose() {
  docker compose -f docker-compose.yml "$@"
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

case "$SERVICE" in
  all)
    require_non_empty_file .env
    require_non_empty_file backend.env
    require_non_empty_file frontend.env
    require_non_empty_file postgres.env
    compose pull
    compose up -d postgres redis
    wait_healthy postgres
    wait_healthy redis
    compose run --rm migrate
    compose run --rm blogsync
    compose up -d --no-deps backend
    wait_healthy backend
    compose up -d frontend
    ;;
  frontend)
    require_non_empty_file .env
    require_non_empty_file frontend.env
    compose pull frontend
    compose up -d frontend
    ;;
  backend)
    require_non_empty_file .env
    require_non_empty_file backend.env
    require_non_empty_file postgres.env
    compose pull backend
    compose up -d postgres redis
    wait_healthy postgres
    wait_healthy redis
    compose run --rm migrate
    compose run --rm blogsync
    compose up -d --no-deps backend
    wait_healthy backend
    ;;
  postgres)
    require_non_empty_file postgres.env
    compose pull postgres || true
    compose up -d postgres
    ;;
  redis)
    compose pull redis || true
    compose up -d redis
    ;;
  *)
    echo "Usage: $0 [all|frontend|backend|postgres|redis]"
    exit 1
    ;;
esac

docker image prune -f
