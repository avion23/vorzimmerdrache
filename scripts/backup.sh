#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/.env" 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
BACKUP_ENCRYPT_DIR="${BACKUP_DIR}/encrypted"
BACKUP_KEY_ID="${BACKUP_GPG_KEY_ID:-vorzimmerdrache-backup@local}"
RETENTION_DAILY="${BACKUP_RETENTION_DAILY:-7}"
RETENTION_WEEKLY="${BACKUP_RETENTION_WEEKLY:-4}"
RETENTION_MONTHLY="${BACKUP_RETENTION_MONTHLY:-6}"
S3_ENABLED="${BACKUP_S3_ENABLED:-false}"
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
LOG_FILE="/var/log/vorzimmerdrache-backup.log"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${INSTALLER_TELEGRAM_CHAT_ID:-}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEMP_DIR=$(mktemp -d)
BACKUP_NAME="vorzimmerdrache-backup-${TIMESTAMP}"

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
        -d text="🔄 Backup: ${message}" >/dev/null || true
}

error_exit() {
    log "ERROR: $1"
    send_notification "FAILED - $1"
    exit 1
}

check_gpg_key() {
    if ! gpg --list-secret-keys "${BACKUP_KEY_ID}" >/dev/null 2>&1; then
        error_exit "GPG key ${BACKUP_KEY_ID} not found. Run setup-backup-encryption.sh first."
    fi
}

backup_postgres() {
    log "Backing up PostgreSQL database..."
    
    local postgres_container="postgres"
    if ! docker ps --format '{{.Names}}' | grep -q "^${postgres_container}$"; then
        error_exit "PostgreSQL container not running"
    fi
    
    docker exec "${postgres_container}" pg_dumpall -U "${POSTGRES_USER:-n8n}" > "${TEMP_DIR}/postgres-all.sql" \
        || error_exit "Failed to dump PostgreSQL database"
    
    docker exec "${postgres_container}" pg_dump -U "${POSTGRES_USER:-n8n}" \
        --schema=public --no-owner --no-acl "${POSTGRES_DB:-n8n}" > "${TEMP_DIR}/postgres-${POSTGRES_DB:-n8n}.sql" \
        || error_exit "Failed to dump PostgreSQL database ${POSTGRES_DB:-n8n}"
    
    log "PostgreSQL backup completed"
}

backup_n8n_workflows() {
    log "Backing up n8n workflows..."
    
    local n8n_container="n8n"
    if ! docker ps --format '{{.Names}}' | grep -q "^${n8n_container}$"; then
        log "Warning: n8n container not running, skipping workflow backup"
        return 0
    fi
    
    docker exec "${n8n_container}" n8n export:workflow --all --output=/tmp/workflows.json 2>/dev/null || true
    
    if docker exec "${n8n_container}" test -f /tmp/workflows.json; then
        docker cp "${n8n_container}:/tmp/workflows.json" "${TEMP_DIR}/n8n-workflows.json" \
            || log "Warning: Failed to copy n8n workflows"
        docker exec "${n8n_container}" rm -f /tmp/workflows.json || true
    fi
    
    cp -r "${PROJECT_ROOT}/workflows" "${TEMP_DIR}/" 2>/dev/null || log "Warning: Failed to copy local workflows"
    
    log "n8n workflows backup completed"
}

backup_env() {
    log "Encrypting environment variables..."
    
    local env_file="${PROJECT_ROOT}/.env"
    if [[ ! -f "${env_file}" ]]; then
        log "Warning: .env file not found"
        return 0
    fi
    
    gpg --encrypt --recipient "${BACKUP_KEY_ID}" --output "${TEMP_DIR}/.env.gpg" "${env_file}" \
        || error_exit "Failed to encrypt .env file"
    
    log "Environment variables encrypted"
}

backup_docker_volumes() {
    log "Backing up Docker volumes..."
    
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
        if ! docker volume inspect "${volume}" >/dev/null 2>&1; then
            log "Warning: Volume ${volume} does not exist, skipping"
            continue
        fi
        
        log "Backing up volume: ${volume}"
        
        local temp_container="backup-temp-${volume}-${RANDOM}"
        local temp_mount="/backup-data"
        
        docker run --rm \
            -v "${volume}:${temp_mount}:ro" \
            -v "${TEMP_DIR}:/backup-output" \
            alpine tar czf "/backup-output/${volume}.tar.gz" -C "${temp_mount}" . \
            || error_exit "Failed to backup volume ${volume}"
    done
    
    log "Docker volumes backup completed"
}

create_backup_archive() {
    log "Creating backup archive..."
    
    cd "${TEMP_DIR}"
    tar czf "${BACKUP_NAME}.tar.gz" . \
        || error_exit "Failed to create backup archive"
    
    log "Backup archive created"
}

encrypt_backup() {
    log "Encrypting backup archive..."
    
    mkdir -p "${BACKUP_ENCRYPT_DIR}"
    
    gpg --encrypt --recipient "${BACKUP_KEY_ID}" \
        --output "${BACKUP_ENCRYPT_DIR}/${BACKUP_NAME}.tar.gz.gpg" \
        "${TEMP_DIR}/${BACKUP_NAME}.tar.gz" \
        || error_exit "Failed to encrypt backup archive"
    
    log "Backup encrypted to ${BACKUP_ENCRYPT_DIR}/${BACKUP_NAME}.tar.gz.gpg"
}

apply_retention() {
    log "Applying retention policy..."
    
    local now_epoch=$(date +%s)
    
    for backup_file in "${BACKUP_ENCRYPT_DIR}"/*.tar.gz.gpg; do
        [[ -f "${backup_file}" ]] || continue
        
        local file_date=$(stat -f "%m" "${backup_file}" 2>/dev/null || stat -c "%Y" "${backup_file}")
        local age_days=$(( (now_epoch - file_date) / 86400 ))
        
        local keep=false
        local day_of_week=$(date -r "${file_date}" +%u 2>/dev/null || date -d "@${file_date}" +%u)
        local day_of_month=$(date -r "${file_date}" +%d 2>/dev/null || date -d "@${file_date}" +%d)
        
        if [[ ${age_days} -lt ${RETENTION_DAILY} ]]; then
            keep=true
        elif [[ ${day_of_week} -eq 7 ]] && [[ ${age_days} -lt $((RETENTION_WEEKLY * 7)) ]]; then
            keep=true
        elif [[ ${day_of_month} -eq 1 ]] && [[ ${age_days} -lt $((RETENTION_MONTHLY * 30)) ]]; then
            keep=true
        fi
        
        if [[ "${keep}" == "false" ]]; then
            log "Deleting old backup: $(basename "${backup_file}")"
            rm -f "${backup_file}"
        fi
    done
    
    log "Retention policy applied"
}

sync_to_s3() {
    [[ "${S3_ENABLED}" == "true" ]] || return 0
    [[ -n "${S3_BUCKET}" ]] || { log "S3 enabled but bucket not configured"; return 0; }
    
    log "Syncing backups to S3..."
    
    if command -v aws >/dev/null 2>&1; then
        aws s3 sync "${BACKUP_ENCRYPT_DIR}" "s3://${S3_BUCKET}/" \
            --storage-class STANDARD_IA \
            || log "Warning: Failed to sync to S3"
    elif command -v rclone >/dev/null 2>&1; then
        rclone sync "${BACKUP_ENCRYPT_DIR}" "s3:${S3_BUCKET}" || log "Warning: Failed to sync to S3"
    else
        log "Warning: Neither aws-cli nor rclone found for S3 sync"
    fi
    
    log "S3 sync completed"
}

main() {
    log "Starting backup process..."
    send_notification "Started"
    
    mkdir -p "${BACKUP_DIR}" "${BACKUP_ENCRYPT_DIR}"
    
    check_gpg_key
    backup_postgres
    backup_n8n_workflows
    backup_env
    backup_docker_volumes
    create_backup_archive
    encrypt_backup
    apply_retention
    sync_to_s3
    
    local backup_size=$(du -h "${BACKUP_ENCRYPT_DIR}/${BACKUP_NAME}.tar.gz.gpg" | cut -f1)
    log "Backup completed successfully: ${BACKUP_NAME}.tar.gz.gpg (${backup_size})"
    send_notification "SUCCESS - ${BACKUP_NAME}.tar.gz.gpg (${backup_size})"
}

main "$@"
