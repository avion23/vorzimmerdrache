#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PROJECT_ROOT}/.env" 2>/dev/null || true

BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
BACKUP_ENCRYPT_DIR="${BACKUP_DIR}/encrypted"
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
S3_STORAGE_CLASS="${BACKUP_S3_STORAGE_CLASS:-STANDARD_IA}"
S3_REGION="${BACKUP_S3_REGION:-us-east-1}"
RCLONE_REMOTE="${BACKUP_RCLONE_REMOTE:-s3}"

LOG_FILE="/var/log/vorzimmerdrache-backup.log"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${INSTALLER_TELEGRAM_CHAT_ID:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

send_notification() {
    local message="$1"
    [[ -n "${TELEGRAM_BOT_TOKEN}" && -n "${TELEGRAM_CHAT_ID}" ]] || return 0
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text "🔄 S3 Sync: ${message}" >/dev/null || true
}

error_exit() {
    log "ERROR: $1"
    send_notification "FAILED - $1"
    exit 1
}

check_backup_dir() {
    if [[ ! -d "${BACKUP_ENCRYPT_DIR}" ]]; then
        error_exit "Backup directory ${BACKUP_ENCRYPT_DIR} does not exist"
    fi
    
    if [[ -z "$(ls -A "${BACKUP_ENCRYPT_DIR}" 2>/dev/null)" ]]; then
        error_exit "No backups found in ${BACKUP_ENCRYPT_DIR}"
    fi
}

check_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        error_exit "AWS CLI not found. Install with: apt install awscli (Ubuntu) or brew install awscli (macOS)"
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log "Warning: AWS credentials not configured"
        log "Configure with: aws configure"
    fi
}

check_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        log "rclone not found. Install with: curl https://rclone.org/install.sh | sudo bash"
        return 1
    fi
    
    if ! rclone listremotes | grep -q "^${RCLONE_REMOTE}:"; then
        log "Warning: rclone remote '${RCLONE_REMOTE}' not configured"
        log "Configure with: rclone config"
        return 1
    fi
    
    return 0
}

sync_with_aws_cli() {
    [[ -n "${S3_BUCKET}" ]] || error_exit "BACKUP_S3_BUCKET not set in .env"
    
    log "Syncing to S3 bucket: ${S3_BUCKET}..."
    
    aws s3 sync "${BACKUP_ENCRYPT_DIR}" "s3://${S3_BUCKET}/" \
        --storage-class "${S3_STORAGE_CLASS}" \
        --exclude "*" \
        --include "*.tar.gz.gpg" \
        --delete \
        || error_exit "Failed to sync to S3"
    
    log "S3 sync completed with aws-cli"
}

sync_with_rclone() {
    log "Syncing to remote: ${RCLONE_REMOTE}..."
    
    rclone sync "${BACKUP_ENCRYPT_DIR}" "${RCLONE_REMOTE}:vorzimmerdrache-backups" \
        --exclude "*" \
        --include "*.tar.gz.gpg" \
        --delete \
        --progress \
        || error_exit "Failed to sync with rclone"
    
    log "rclone sync completed"
}

configure_lifecycle_policy() {
    [[ -n "${S3_BUCKET}" ]] || return 0
    
    log "Configuring S3 lifecycle policy..."
    
    local policy_file=$(mktemp)
    cat > "${policy_file}" <<EOF
{
  "Rules": [
    {
      "ID": "DeleteOldBackups",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "Expiration": {
        "Days": 90
      },
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 30
      }
    }
  ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${S3_BUCKET}" \
        --lifecycle-configuration "file://${policy_file}" \
        2>/dev/null && log "Lifecycle policy configured" || log "Warning: Failed to configure lifecycle policy (may already exist or permissions issue)"
    
    rm -f "${policy_file}"
}

list_s3_backups() {
    [[ -n "${S3_BUCKET}" ]] || return 0
    
    log "Listing backups in S3..."
    
    aws s3 ls "s3://${S3_BUCKET}/" --recursive --human-readable | grep ".tar.gz.gpg"
}

verify_s3_sync() {
    [[ -n "${S3_BUCKET}" ]] || return 0
    
    log "Verifying S3 sync..."
    
    local local_count=$(ls "${BACKUP_ENCRYPT_DIR}"/*.tar.gz.gpg 2>/dev/null | wc -l)
    local s3_count=$(aws s3 ls "s3://${S3_BUCKET}/" --recursive | wc -l)
    
    log "Local backups: ${local_count}"
    log "S3 backups: ${s3_count}"
    
    if [[ ${local_count} -ne ${s3_count} ]]; then
        log "Warning: Backup count mismatch"
        return 1
    fi
    
    log "S3 verification: OK"
    return 0
}

main() {
    local mode="${1:-sync}"
    
    check_backup_dir
    
    case "${mode}" in
        sync)
            if command -v aws >/dev/null 2>&1; then
                check_aws_cli
                sync_with_aws_cli
                verify_s3_sync
            elif command -v rclone >/dev/null 2>&1; then
                check_rclone
                sync_with_rclone
            else
                error_exit "Neither aws-cli nor rclone found"
            fi
            send_notification "SUCCESS - S3 sync completed"
            ;;
        
        lifecycle)
            check_aws_cli
            configure_lifecycle_policy
            ;;
        
        list)
            if command -v aws >/dev/null 2>&1; then
                list_s3_backups
            elif command -v rclone >/dev/null 2>&1; then
                rclone ls "${RCLONE_REMOTE}:vorzimmerdrache-backups" | grep ".tar.gz.gpg"
            else
                error_exit "Neither aws-cli nor rclone found"
            fi
            ;;
        
        verify)
            verify_s3_sync
            ;;
        
        *)
            cat <<EOF
Usage: $0 [mode]

Sync encrypted backups to S3-compatible storage.

Modes:
  sync       Upload backups to S3 (default)
  lifecycle  Configure S3 lifecycle policy
  list       List backups in S3
  verify     Verify S3 sync integrity

Configuration (in .env):
  BACKUP_S3_ENABLED=true
  BACKUP_S3_BUCKET=your-bucket-name
  BACKUP_S3_STORAGE_CLASS=STANDARD_IA
  BACKUP_RCLONE_REMOTE=s3

Examples:
  $0 sync      # Sync backups to S3
  $0 lifecycle # Configure retention policy
  $0 list      # List S3 backups
  $0 verify    # Verify sync integrity

S3-compatible services:
  - AWS S3: aws configure
  - Wasabi: Configure region us-east-1
  - Backblaze B2: Use rclone with b2: remote
  - Hetzner Storage Box: Use rclone with webdav: remote

Setup instructions:
  AWS S3:
    1. Install aws-cli
    2. aws configure
    3. Set BACKUP_S3_BUCKET in .env
  
  rclone (recommended for S3-compatible):
    1. Install rclone
    2. rclone config
    3. Select S3 or WebDAV provider
    4. Set BACKUP_RCLONE_REMOTE in .env
EOF
            exit 0
            ;;
    esac
}

main "$@"
