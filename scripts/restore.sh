#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/.env" 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
BACKUP_ENCRYPT_DIR="${BACKUP_DIR}/encrypted"
BACKUP_KEY_ID="${BACKUP_GPG_KEY_ID:-vorzimmerdrache-backup@local}"
LOG_FILE="/var/log/vorzimmerdrache-backup.log"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${INSTALLER_TELEGRAM_CHAT_ID:-}"

TEMP_DIR=$(mktemp -d)
RESTORE_DIR="${TEMP_DIR}/restore"

cleanup() {
    rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

send_notification() {
    local message="$1"
    [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]] || return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="🔄 Restore: ${message}" >/dev/null || true
}

error_exit() {
    log "ERROR: $1"
    send_notification "FAILED - $1"
    exit 1
}

check_gpg_key() {
    if ! gpg --list-secret-keys "${BACKUP_KEY_ID}" >/dev/null 2>&1; then
        error_exit "GPG key ${BACKUP_KEY_ID} not found"
    fi
}

select_backup() {
    log "Available backups:"
    
    local backups=($(ls -t "${BACKUP_ENCRYPT_DIR}"/*.tar.gz.gpg 2>/dev/null || true))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        error_exit "No backups found in ${BACKUP_ENCRYPT_DIR}"
    fi
    
    local i=1
    for backup in "${backups[@]}"; do
        local name=$(basename "${backup}")
        local size=$(du -h "${backup}" | cut -f1)
        local date=$(stat -f "%Sm" "${backup}" 2>/dev/null || stat -c "%y" "${backup}")
        echo "  ${i}) ${name} (${size}) - ${date}"
        ((i++))
    done
    
    echo ""
    if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
        local index=$(($1 - 1))
        if [[ ${index} -ge 0 && ${index} -lt ${#backups[@]} ]]; then
            echo "${backups[index]}"
            return 0
        fi
    fi
    
    read -p "Select backup number (1-${#backups[@]}): " selection
    if [[ ! "${selection}" =~ ^[0-9]+$ ]] || [[ ${selection} -lt 1 ]] || [[ ${selection} -gt ${#backups[@]} ]]; then
        error_exit "Invalid selection"
    fi
    
    echo "${backups[$((selection - 1))]}"
}

decrypt_backup() {
    local backup_file="$1"
    local output_file="$2"
    
    log "Decrypting backup..."
    
    gpg --decrypt --output "${output_file}" "${backup_file}" \
        || error_exit "Failed to decrypt backup"
    
    log "Backup decrypted"
}

extract_backup() {
    local archive_file="$1"
    
    log "Extracting backup..."
    
    mkdir -p "${RESTORE_DIR}"
    tar xzf "${archive_file}" -C "${RESTORE_DIR}" \
        || error_exit "Failed to extract backup"
    
    log "Backup extracted"
}

restore_postgres() {
    local dump_file="${RESTORE_DIR}/postgres-all.sql"
    
    if [[ ! -f "${dump_file}" ]]; then
        log "Warning: PostgreSQL dump not found in backup"
        return 0
    fi
    
    local postgres_container="postgres"
    
    if docker ps --format '{{.Names}}' | grep -q "^${postgres_container}$"; then
        log "PostgreSQL container is running. Stop it first to restore."
        read -p "Stop ${postgres_container} now? (y/N): " confirm
        [[ "${confirm}" =~ ^[Yy]$ ]] || error_exit "Restore cancelled"
        docker stop "${postgres_container}" || error_exit "Failed to stop PostgreSQL"
    fi
    
    log "Restoring PostgreSQL database..."
    
    local temp_container="postgres-restore-${RANDOM}"
    
    docker run --rm \
        -v "postgres_data:/var/lib/postgresql/data" \
        -v "${RESTORE_DIR}:/backup:ro" \
        postgres:15-alpine \
        sh -c "chown -R postgres:postgres /var/lib/postgresql/data && \
               cat /backup/postgres-all.sql | docker exec -i postgres psql -U ${POSTGRES_USER:-n8n}" \
        || error_exit "Failed to restore PostgreSQL"
    
    docker start "${postgres_container}" 2>/dev/null || log "PostgreSQL container needs to be started manually"
    
    log "PostgreSQL restore completed"
}

restore_n8n_workflows() {
    local workflows_file="${RESTORE_DIR}/n8n-workflows.json"
    
    if [[ ! -f "${workflows_file}" ]]; then
        log "Warning: n8n workflows export not found"
        return 0
    fi
    
    local n8n_container="n8n"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${n8n_container}$"; then
        log "Warning: n8n container not running, skipping workflow restore"
        return 0
    fi
    
    log "Restoring n8n workflows..."
    
    docker cp "${workflows_file}" "${n8n_container}:/tmp/workflows.json" \
        || error_exit "Failed to copy workflows to n8n container"
    
    docker exec "${n8n_container}" n8n import:workflow --input=/tmp/workflows.json 2>/dev/null || log "Warning: n8n import command failed"
    
    if [[ -d "${RESTORE_DIR}/workflows" ]]; then
        cp -r "${RESTORE_DIR}/workflows" "${PROJECT_ROOT}/workflows" || log "Warning: Failed to restore local workflows"
    fi
    
    log "n8n workflows restore completed"
}

restore_env() {
    local env_file="${RESTORE_DIR}/.env.gpg"
    
    if [[ ! -f "${env_file}" ]]; then
        log "Warning: Encrypted .env file not found"
        return 0
    fi
    
    log "Restoring .env file..."
    
    local decrypted_env="${TEMP_DIR}/.env.decrypted"
    
    gpg --decrypt --output "${decrypted_env}" "${env_file}" \
        || error_exit "Failed to decrypt .env file"
    
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        local backup_env="${PROJECT_ROOT}/.env.backup.$(date +%Y%m%d-%H%M%S)"
        log "Backing up existing .env to ${backup_env}"
        cp "${PROJECT_ROOT}/.env" "${backup_env}"
    fi
    
    cp "${decrypted_env}" "${PROJECT_ROOT}/.env" \
        || error_exit "Failed to restore .env file"
    
    chmod 600 "${PROJECT_ROOT}/.env"
    
    log ".env file restored"
}

restore_docker_volume() {
    local volume="$1"
    local archive="${RESTORE_DIR}/${volume}.tar.gz"
    
    if [[ ! -f "${archive}" ]]; then
        log "Warning: Volume backup ${volume} not found"
        return 0
    fi
    
    log "Restoring volume: ${volume}"
    
    if ! docker volume inspect "${volume}" >/dev/null 2>&1; then
        docker volume create "${volume}" || error_exit "Failed to create volume ${volume}"
    fi
    
    local temp_container="restore-temp-${volume}-${RANDOM}"
    local temp_mount="/restore-data"
    
    docker run --rm \
        -v "${volume}:${temp_mount}" \
        -v "${RESTORE_DIR}:/restore-input:ro" \
        alpine sh -c "rm -rf ${temp_mount}/* && tar xzf /restore-input/${volume}.tar.gz -C ${temp_mount}" \
        || error_exit "Failed to restore volume ${volume}"
    
    log "Volume ${volume} restored"
}

restore_docker_volumes() {
    log "Restoring Docker volumes..."
    
    local volumes=(
        "postgres_data"
        "redis_data"
        "n8n_data"
        "waha_data"
        "waha_sessions"
        "traefik_letsencrypt"
        "uptime_kuma_data"
        "telegram_bot_data"
    )
    
    for volume in "${volumes[@]}"; do
        restore_docker_volume "${volume}"
    done
    
    log "Docker volumes restore completed"
}

verify_restore() {
    log "Verifying restore integrity..."
    
    local errors=0
    
    if [[ -f "${RESTORE_DIR}/postgres-all.sql" ]]; then
        log "PostgreSQL dump: OK"
    else
        log "PostgreSQL dump: MISSING"
        ((errors++))
    fi
    
    if [[ -f "${RESTORE_DIR}/.env.gpg" ]]; then
        log "Environment variables: OK"
    else
        log "Environment variables: MISSING"
        ((errors++))
    fi
    
    local volume_count=$(ls "${RESTORE_DIR}"/*.tar.gz 2>/dev/null | wc -l)
    log "Docker volume backups: ${volume_count} found"
    
    log "Verification complete. Issues found: ${errors}"
    
    return ${errors}
}

main() {
    if [[ $# -eq 0 ]]; then
        local backup_file=$(select_backup)
    elif [[ "$1" == "--help" ]]; then
        cat <<EOF
Usage: $0 [backup_number]

Restore a backup. If no number is provided, you will be prompted to select one.

Arguments:
  backup_number    Optional backup number from the list

Examples:
  $0              # Interactive selection
  $0 1            # Restore the most recent backup
EOF
        exit 0
    else
        local backup_file=$(select_backup "$1")
    fi
    
    log "Starting restore from $(basename "${backup_file}")..."
    send_notification "Started"
    
    check_gpg_key
    
    local decrypted_archive="${TEMP_DIR}/backup.tar.gz"
    decrypt_backup "${backup_file}" "${decrypted_archive}"
    extract_backup "${decrypted_archive}"
    
    echo ""
    echo "Available restore options:"
    echo "  1) PostgreSQL database"
    echo "  2) n8n workflows"
    echo "  3) Environment variables (.env)"
    echo "  4) Docker volumes"
    echo "  5) All of the above"
    echo ""
    
    read -p "Select what to restore (1-5, or 'all' for full restore): " selection
    
    case "${selection}" in
        1) restore_postgres ;;
        2) restore_n8n_workflows ;;
        3) restore_env ;;
        4) restore_docker_volumes ;;
        5|all)
            restore_postgres
            restore_n8n_workflows
            restore_env
            restore_docker_volumes
            ;;
        *) error_exit "Invalid selection" ;;
    esac
    
    verify_restore
    
    log "Restore completed successfully"
    send_notification "SUCCESS - Restore from $(basename "${backup_file}") completed"
    
    log "Restart services: docker-compose up -d"
}

main "$@"
