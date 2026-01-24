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
ROLLBACK_LOG="${ROLLBACK_LOG:-${PROJECT_DIR}/logs/rollback.log}"

mkdir -p "$(dirname "$ROLLBACK_LOG")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ROLLBACK_LOG"
}

restore_database() {
  log_step "Restoring database from backup..."

  local backup_file

  if [ -f "${BACKUP_DIR}/last-backup.txt" ]; then
    backup_file=$(cat "${BACKUP_DIR}/last-backup.txt")
  else
    log_warn "No last-backup.txt found, searching for latest backup..."

    backup_file=$(find "$BACKUP_DIR" -name "pre-deploy-*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
  fi

  if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
    log_error "No backup file found"
    exit 1
  fi

  log "Restoring from: $backup_file"

  docker compose exec -T postgres dropdb -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" || true
  docker compose exec -T postgres createdb -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}"

  gunzip -c "$backup_file" | docker compose exec -T postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}"

  if [ $? -eq 0 ]; then
    log_info "✓ Database restored"
  else
    log_error "✗ Database restore failed"
    exit 1
  fi
}

revert_git() {
  log_step "Reverting to previous Git commit..."

  cd "$PROJECT_DIR"

  local prev_commit
  prev_commit=$(cat "${BACKUP_DIR}/prev-commit.txt" 2>/dev/null || echo "")

  if [ -z "$prev_commit" ]; then
    log_warn "No previous commit found, using HEAD^"
    git reset --hard HEAD^
  else
    log "Checking out previous commit: $prev_commit"
    git reset --hard "$prev_commit"
  fi

  log_info "✓ Git reverted to $(git rev-parse --short HEAD)"
}

restart_containers() {
  log_step "Restarting containers..."

  docker compose down

  docker compose up -d

  log_info "✓ Containers restarted"
}

wait_for_health() {
  log_step "Waiting for services to be healthy..."

  local timeout=300
  local interval=10
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
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

    sleep $interval
    elapsed=$((elapsed + interval))
    log "Waiting... (${elapsed}s/${timeout}s)"
  done

  log_error "✗ Services did not become healthy within timeout"
  return 1
}

verify_rollback() {
  log_step "Verifying rollback..."

  if [ -x "${PROJECT_DIR}/tests/smoke/smoke-test.sh" ]; then
    "${PROJECT_DIR}/tests/smoke/smoke-test.sh"
    return $?
  else
    log_warn "Smoke test script not found, skipping verification"
    return 0
  fi
}

notify_rollback() {
  local message="🔄 Rollback completed: reverted to $(git rev-parse --short HEAD)"
  log "$message"

  if command -v "${PROJECT_DIR}/scripts/notify-telegram.sh" &> /dev/null; then
    "${PROJECT_DIR}/scripts/notify-telegram.sh" "$message" &> /dev/null || true
  fi
}

main() {
  log "=========================================="
  log "Starting rollback process..."
  log "=========================================="

  restore_database

  revert_git

  restart_containers

  wait_for_health

  verify_rollback

  notify_rollback

  log "=========================================="
  log "Rollback completed successfully!"
  log "=========================================="
  exit 0
}

main "$@"
