#!/bin/bash

set -euo pipefail

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_NC='\033[0m'

log_info() {
  echo -e "${COLOR_GREEN}[INFO]${COLOR_NC} $1"
}

log_error() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1"
}

log_warn() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"
}

check_service() {
  local name="$1"
  local url="$2"
  local expected_status="${3:-200}"

  log_info "Checking $name: $url"

  status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url")

  if [ "$status" -eq "$expected_status" ]; then
    log_info "✓ $name is healthy (HTTP $status)"
    return 0
  else
    log_error "✗ $name is not healthy (expected $expected_status, got $status)"
    return 1
  fi
}

check_webhook() {
  local name="$1"
  local url="$2"
  local payload="${3:-'{\"test\":\"smoke\"}'}"

  log_info "Testing $name webhook: $url"

  response=$(curl -s -w "\n%{http_code}" --connect-timeout 10 --max-time 30 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$url")

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n-1)

  if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 202 ] || [ "$http_code" -eq 204 ]; then
    log_info "✓ $name webhook responded (HTTP $http_code)"
    return 0
  else
    log_error "✗ $name webhook failed (HTTP $http_code): $body"
    return 1
  fi
}

check_postgres() {
  local host="${1:-localhost}"
  local port="${2:-5432}"
  local user="${3:-n8n}"
  local db="${4:-n8n}"

  log_info "Testing PostgreSQL connection: $host:$port"

  if command -v docker &> /dev/null; then
    if docker compose ps postgres &> /dev/null; then
      docker compose exec -T postgres pg_isready -U "$user" &> /dev/null
      return $?
    fi
  fi

  if command -v psql &> /dev/null; then
    PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "$host" -p "$port" -U "$user" -d "$db" -c "SELECT 1" &> /dev/null
    return $?
  fi

  log_warn "PostgreSQL check skipped - no docker or psql available"
  return 0
}

check_redis() {
  local host="${1:-localhost}"
  local port="${2:-6379}"
  local password="${REDIS_PASSWORD:-}"

  log_info "Testing Redis connection: $host:$port"

  if command -v docker &> /dev/null; then
    if docker compose ps redis &> /dev/null; then
      if [ -n "$password" ]; then
        docker compose exec -T redis redis-cli -a "$password" ping | grep -q "PONG"
      else
        docker compose exec -T redis redis-cli ping | grep -q "PONG"
      fi
      return $?
    fi
  fi

  if command -v redis-cli &> /dev/null; then
    if [ -n "$password" ]; then
      redis-cli -h "$host" -p "$port" -a "$password" ping | grep -q "PONG"
    else
      redis-cli -h "$host" -p "$port" ping | grep -q "PONG"
    fi
    return $?
  fi

  log_warn "Redis check skipped - no docker or redis-cli available"
  return 0
}

failures=0

if [ -f .env ]; then
  source .env
else
  log_warn ".env file not found, using defaults"
fi

N8N_URL="${N8N_PROTOCOL:-http}://${N8N_HOST:-localhost}:${N8N_PORT:-5678}"
WAHA_URL="${WAHA_API_URL:-http://localhost:3000}"
DOMAIN="${DOMAIN:-localhost}"

log_info "Starting smoke tests..."

check_service "n8n" "${N8N_URL}/healthz" 200 || ((failures++))
check_service "Traefik" "http://${DOMAIN}/health" 200 || ((failures++))
check_service "Uptime Kuma" "http://uptime.${DOMAIN}/api/status" 200 || true

check_webhook "n8n webhook" "${N8N_URL}/webhook/test" || ((failures++))

check_webhook "Waha session" "${WAHA_URL}/api/sessions/default/status" || ((failures++))

check_postgres || ((failures++))

check_redis || ((failures++))

echo ""
log_info "Smoke tests completed"

if [ $failures -eq 0 ]; then
  log_info "✓ All checks passed"
  exit 0
else
  log_error "✗ $failures check(s) failed"
  exit 1
fi
