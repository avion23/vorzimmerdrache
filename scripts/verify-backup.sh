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

cleanup() {
    rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

send_notification() {
    local message="$1"
    [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]] || return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text "🔄 Backup Verify: ${message}" >/dev/null || true
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

verify_file_integrity() {
    local file="$1"
    
    if [[ ! -f "${file}" ]]; then
        return 1
    fi
    
    if [[ ${file} == *.tar.gz.gpg ]]; then
        gpg --decrypt "${file}" > /dev/null 2>&1
        return $?
    fi
    
    return 0
}

verify_backup_file() {
    local backup_file="$1"
    
    log "Verifying: $(basename "${backup_file}")"
    
    local errors=0
    
    if ! verify_file_integrity "${backup_file}"; then
        log "  File integrity: FAILED"
        ((errors++))
    else
        log "  File integrity: OK"
    fi
    
    local size=$(du -h "${backup_file}" | cut -f1)
    log "  Size: ${size}"
    
    local date=$(stat -f "%Sm" "${backup_file}" 2>/dev/null || stat -c "%y" "${backup_file}")
    log "  Date: ${date}"
    
    if [[ ${errors} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

verify_postgres_dump() {
    local dump_file="$1"
    
    if [[ ! -f "${dump_file}" ]]; then
        log "  PostgreSQL dump: NOT FOUND"
        return 1
    fi
    
    if grep -q "^-- PostgreSQL database dump" "${dump_file}" 2>/dev/null; then
        log "  PostgreSQL dump: OK"
        return 0
    else
        log "  PostgreSQL dump: INVALID FORMAT"
        return 1
    fi
}

verify_n8n_workflows() {
    local workflows_file="$1"
    
    if [[ ! -f "${workflows_file}" ]]; then
        log "  n8n workflows: NOT FOUND (may not be needed)"
        return 0
    fi
    
    if python3 -m json.tool "${workflows_file}" >/dev/null 2>&1; then
        log "  n8n workflows: OK"
        return 0
    else
        log "  n8n workflows: INVALID JSON"
        return 1
    fi
}

verify_env_file() {
    local env_file="$1"
    
    if [[ ! -f "${env_file}" ]]; then
        log "  Encrypted .env: NOT FOUND (may not be needed)"
        return 0
    fi
    
    if gpg --decrypt "${env_file}" > /dev/null 2>&1; then
        log "  Encrypted .env: OK"
        return 0
    else
        log "  Encrypted .env: FAILED TO DECRYPT"
        return 1
    fi
}

verify_backup_contents() {
    local backup_file="$1"
    
    log "Verifying backup contents..."
    
    local decrypted_archive="${TEMP_DIR}/verify-backup.tar.gz"
    local extract_dir="${TEMP_DIR}/verify-extract"
    
    gpg --decrypt --output "${decrypted_archive}" "${backup_file}" \
        || error_exit "Failed to decrypt backup for content verification"
    
    mkdir -p "${extract_dir}"
    tar xzf "${decrypted_archive}" -C "${extract_dir}" \
        || error_exit "Failed to extract backup for content verification"
    
    local errors=0
    
    verify_postgres_dump "${extract_dir}/postgres-all.sql" || ((errors++))
    verify_postgres_dump "${extract_dir}/postgres-${POSTGRES_DB:-n8n}.sql" || ((errors++))
    verify_n8n_workflows "${extract_dir}/n8n-workflows.json" || ((errors++))
    verify_env_file "${extract_dir}/.env.gpg" || ((errors++))
    
    local volume_count=$(ls "${extract_dir}"/*.tar.gz 2>/dev/null | wc -l)
    log "  Docker volume backups: ${volume_count} found"
    
    return ${errors}
}

verify_latest_backup() {
    log "Verifying latest backup..."
    
    local latest_backup=$(ls -t "${BACKUP_ENCRYPT_DIR}"/*.tar.gz.gpg 2>/dev/null | head -1)
    
    if [[ -z "${latest_backup}" ]]; then
        error_exit "No backups found in ${BACKUP_ENCRYPT_DIR}"
    fi
    
    if verify_backup_file "${latest_backup}" && verify_backup_contents "${latest_backup}"; then
        log "Latest backup verification: PASSED"
        return 0
    else
        log "Latest backup verification: FAILED"
        return 1
    fi
}

verify_all_backups() {
    log "Verifying all backups..."
    
    local backups=($(ls -t "${BACKUP_ENCRYPT_DIR}"/*.tar.gz.gpg 2>/dev/null || true))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        error_exit "No backups found in ${BACKUP_ENCRYPT_DIR}"
    fi
    
    local passed=0
    local failed=0
    
    for backup in "${backups[@]}"; do
        if verify_backup_file "${backup}"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    log ""
    log "Backup verification summary:"
    log "  Total backups: ${#backups[@]}"
    log "  Passed: ${passed}"
    log "  Failed: ${failed}"
    
    if [[ ${failed} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

generate_health_report() {
    log ""
    log "=================================================="
    log "BACKUP HEALTH REPORT"
    log "=================================================="
    log ""
    
    local backups=($(ls -t "${BACKUP_ENCRYPT_DIR}"/*.tar.gz.gpg 2>/dev/null || true))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "Status: CRITICAL - No backups found"
        return 1
    fi
    
    local total_size=0
    local now_epoch=$(date +%s)
    local latest_age_days=0
    
    for backup in "${backups[@]}"; do
        local size_bytes=$(stat -f "%z" "${backup}" 2>/dev/null || stat -c "%s" "${backup}")
        total_size=$((total_size + size_bytes))
        
        local file_epoch=$(stat -f "%m" "${backup}" 2>/dev/null || stat -c "%Y" "${backup}")
        local age=$(( (now_epoch - file_epoch) / 86400 ))
        
        if [[ ${age} -gt ${latest_age_days} ]]; then
            latest_age_days=${age}
        fi
    done
    
    local total_size_mb=$((total_size / 1024 / 1024))
    
    log "Total backups: ${#backups[@]}"
    log "Total size: ${total_size_mb} MB"
    log "Latest backup age: ${latest_age_days} days"
    log ""
    
    local status="HEALTHY"
    
    if [[ ${#backups[@]} -lt 3 ]]; then
        log "Warning: Fewer than 3 backups available"
        status="WARNING"
    fi
    
    if [[ ${latest_age_days} -gt 1 ]]; then
        log "Warning: Latest backup is older than 1 day"
        status="WARNING"
    fi
    
    if [[ ${latest_age_days} -gt 7 ]]; then
        log "Critical: Latest backup is older than 7 days"
        status="CRITICAL"
    fi
    
    log "Overall status: ${status}"
    log ""
    
    if [[ "${status}" == "CRITICAL" ]]; then
        send_notification "CRITICAL - Backup status: ${status}"
        return 1
    elif [[ "${status}" == "WARNING" ]]; then
        send_notification "WARNING - Backup status: ${status}"
        return 0
    fi
    
    send_notification "OK - Backup status: ${status}"
    return 0
}

main() {
    if [[ ! -d "${BACKUP_ENCRYPT_DIR}" ]]; then
        error_exit "Backup directory ${BACKUP_ENCRYPT_DIR} does not exist"
    fi
    
    check_gpg_key
    
    local mode="${1:-latest}"
    
    case "${mode}" in
        latest)
            verify_latest_backup
            ;;
        all)
            verify_all_backups
            ;;
        report)
            generate_health_report
            ;;
        *)
            cat <<EOF
Usage: $0 [mode]

Verify backup integrity and contents.

Modes:
  latest   Verify only the latest backup (default)
  all      Verify all backups (slower)
  report   Generate health report without detailed verification

Examples:
  $0              # Verify latest backup
  $0 all          # Verify all backups
  $0 report       # Generate health report
EOF
            exit 0
            ;;
    esac
    
    log "Verification completed successfully"
}

main "$@"
