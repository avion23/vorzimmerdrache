#!/bin/bash

set -euo pipefail

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m'

log_info() { echo -e "${COLOR_GREEN}[INFO]${COLOR_NC} $1"; }
log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"; }
log_step() { echo -e "${COLOR_BLUE}[STEP]${COLOR_NC} $1"; }

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_DIR}/backups}"
DEPLOY_LOG="${DEPLOY_LOG:-${PROJECT_DIR}/logs/deploy.log}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-10}"

mkdir -p "$(dirname "$DEPLOY_LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOY_LOG"
}

check_requirements() {
  log_step "Checking requirements..."

  local missing=()

  for cmd in docker docker-compose git curl; do
    if ! command -v "$cmd" &> /dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing required commands: ${missing[*]}"
    exit 1
  fi

  if [ ! -f "${PROJECT_DIR}/.env" ]; then
    log_error ".env file not found in ${PROJECT_DIR}"
    exit 1
  fi

  log_info "✓ All requirements met"
}

backup_database() {
  log_step "Creating database backup..."

  mkdir -p "$BACKUP_DIR"
  local backup_file="${BACKUP_DIR}/pre-deploy-$(date +%Y%m%d-%H%M%S).sql.gz"

  docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" | gzip > "$backup_file"

  if [ $? -eq 0 ]; then
    log_info "✓ Database backed up to $backup_file"
    echo "$backup_file" > "${BACKUP_DIR}/last-backup.txt"
  else
    log_error "✗ Database backup failed"
    exit 1
  fi
}

pull_latest_code() {
  log_step "Pulling latest code from GitHub..."

  cd "$PROJECT_DIR"

  git fetch origin main

  local current_rev
  local target_rev

  current_rev=$(git rev-parse HEAD)
  target_rev=$(git rev-parse origin/main)

  if [ "$current_rev" = "$target_rev" ]; then
    log_warn "Already at latest commit ($current_rev)"
    return 0
  fi

  log "Saving current revision: $current_rev"
  echo "$current_rev" > "${BACKUP_DIR}/prev-commit.txt"

  git pull origin main

  log_info "✓ Updated from $current_rev to $(git rev-parse HEAD)"
}

stop_containers() {
  log_step "Stopping containers gracefully..."

  docker compose down

  local timeout=60
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
    if [ -z "$(docker compose ps -q)" ]; then
      log_info "✓ All containers stopped"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  log_warn "Some containers still running, forcing shutdown..."
  docker compose kill
}

build_images() {
  log_step "Building Docker images..."

  docker compose build --no-cache --pull

  log_info "✓ Images built"
}

pull_images() {
  log_step "Pulling latest images..."

  docker compose pull --ignore-pull-failures

  log_info "✓ Images pulled"
}

run_migrations() {
  log_step "Running database migrations..."

  if [ -d "${PROJECT_DIR}/migrations" ] && [ "$(ls -A ${PROJECT_DIR}/migrations 2>/dev/null)" ]; then
    log "Found migrations directory"

    for migration in "${PROJECT_DIR}/migrations"/*.sql; do
      if [ -f "$migration" ]; then
        local filename
        filename=$(basename "$migration")
        log "Running migration: $filename"

        docker compose exec -T postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" < "$migration"

        if [ $? -eq 0 ]; then
          log "✓ Migration $filename completed"
        else
          log_error "✗ Migration $filename failed"
          return 1
        fi
      fi
    done
  else
    log_warn "No migrations found"
  fi

  log_info "✓ Migrations completed"
}

start_containers() {
  log_step "Starting containers..."

  docker compose up -d

  log_info "✓ Containers started"
}

wait_for_health() {
  log_step "Waiting for services to be healthy..."

  local elapsed=0

  while [ $elapsed -lt $HEALTH_CHECK_TIMEOUT ]; do
    local healthy=true

    for service in postgres redis n8n; do
      if ! docker compose ps "$service" | grep -q "healthy\|running"; then
        healthy=false
        break
      fi
    done

    if [ "$healthy" = true ]; then
      log_info "✓ All services are healthy"
      return 0
    fi

    sleep $HEALTH_CHECK_INTERVAL
    elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    log "Waiting... (${elapsed}s/${HEALTH_CHECK_TIMEOUT}s)"
  done

  log_error "✗ Services did not become healthy within timeout"
  return 1
}

run_smoke_tests() {
  log_step "Running smoke tests..."

  if [ -x "${PROJECT_DIR}/tests/smoke/smoke-test.sh" ]; then
    "${PROJECT_DIR}/tests/smoke/smoke-test.sh"
    return $?
  else
    log_warn "Smoke test script not found, skipping"
    return 0
  fi
}

rollback() {
  log_error "Deployment failed, initiating rollback..."

  local prev_commit
  prev_commit=$(cat "${BACKUP_DIR}/prev-commit.txt" 2>/dev/null || echo "")

  if [ -z "$prev_commit" ]; then
    log_error "No previous commit found for rollback"
    exit 1
  fi

  log "Rolling back to commit: $prev_commit"

  cd "$PROJECT_DIR"

  git checkout "$prev_commit"

  if [ -f "${PROJECT_DIR}/scripts/rollback.sh" ]; then
    "${PROJECT_DIR}/scripts/rollback.sh"
  else
    log_error "Rollback script not found"
    exit 1
  fi
}

cleanup_old_backups() {
  log_step "Cleaning up old backups..."

  find "$BACKUP_DIR" -name "pre-deploy-*.sql.gz" -type f -mtime +7 -delete 2>/dev/null || true

  log_info "✓ Old backups cleaned up"
}

notify_success() {
  local message="✅ Deployment successful: $(git rev-parse --short HEAD) deployed to ${DEPLOY_ENV:-production}"
  log "$message"

  if command -v "${PROJECT_DIR}/scripts/notify-telegram.sh" &> /dev/null; then
    "${PROJECT_DIR}/scripts/notify-telegram.sh" "$message" &> /dev/null || true
  fi
}

main() {
  log "=========================================="
  log "Starting deployment process..."
  log "=========================================="

  check_requirements

  backup_database

  pull_latest_code

  stop_containers

  pull_images

  build_images

  run_migrations || { rollback; exit 1; }

  start_containers

  wait_for_health || { rollback; exit 1; }

  run_smoke_tests || { rollback; exit 1; }

  cleanup_old_backups

  notify_success

  log "=========================================="
  log "Deployment completed successfully!"
  log "=========================================="
  exit 0
}

trap 'log_error "Deployment interrupted"; rollback; exit 1' INT TERM

main "$@"
