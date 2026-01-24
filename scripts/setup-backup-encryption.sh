#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BACKUP_GPG_KEY_ID="vorzimmerdrache-backup@local"
BACKUP_GPG_KEY_NAME="Vorzimmerdrache Backup"
BACKUP_GPG_KEY_EMAIL="vorzimmerdrache-backup@local"

TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

check_gpg() {
    if ! command -v gpg >/dev/null 2>&1; then
        error_exit "GPG is not installed. Install it with: brew install gnupg (macOS) or apt install gnupg (Ubuntu)"
    fi
}

generate_gpg_key() {
    log "Generating GPG key for backups..."
    
    local key_params="${TEMP_DIR}/gpg-batch"
    cat > "${key_params}" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: encrypt,sign
Name-Real: ${BACKUP_GPG_KEY_NAME}
Name-Email: ${BACKUP_GPG_KEY_EMAIL}
Expire-Date: 0
EOF
    
    gpg --batch --generate-key "${key_params}" \
        || error_exit "Failed to generate GPG key"
    
    log "GPG key generated successfully"
}

export_public_key() {
    log "Exporting public key..."
    
    local public_key_dir="${PROJECT_ROOT}/config/keys"
    mkdir -p "${public_key_dir}"
    
    gpg --armor --export "${BACKUP_GPG_KEY_ID}" > "${public_key_dir}/backup-public-key.asc" \
        || error_exit "Failed to export public key"
    
    log "Public key exported to config/keys/backup-public-key.asc"
    log "You can safely commit this file to the repository"
}

export_private_key() {
    log "Exporting private key..."
    
    local private_key_file="${TEMP_DIR}/backup-private-key.asc"
    
    gpg --armor --export-secret-keys "${BACKUP_GPG_KEY_ID}" > "${private_key_file}" \
        || error_exit "Failed to export private key"
    
    log ""
    log "=================================================="
    log "PRIVATE KEY EXPORTED - SAVE THIS SECURELY"
    log "=================================================="
    log ""
    log "The private key is stored in: ${private_key_file}"
    log ""
    log "IMPORTANT SECURITY INSTRUCTIONS:"
    log "1. Import this key into KeePassXC as a secure note"
    log "2. Store a copy offline (USB drive, safety deposit box)"
    log "3. NEVER commit this key to any repository"
    log "4. Share only with trusted backup operators"
    log ""
    log "To restore the key later:"
    log "  gpg --import ${private_key_file}"
    log ""
    
    cat "${private_key_file}"
    
    log ""
    log "=================================================="
    log "Save this output in a secure location!"
    log "=================================================="
    log ""
    
    read -p "Press Enter after you have saved the private key securely..."
}

save_revocation_certificate() {
    log "Generating revocation certificate..."
    
    local revocation_cert="${TEMP_DIR}/backup-revocation.asc"
    
    local revocation_params="${TEMP_DIR}/gpg-revoke"
    cat > "${revocation_params}" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: encrypt,sign
Name-Real: ${BACKUP_GPG_KEY_NAME}
Name-Email: ${BACKUP_GPG_KEY_EMAIL}
Expire-Date: 0
EOF
    
    log "Note: Revocation certificate generation requires interactive input"
    log "This step is optional. Press Ctrl+C to skip if you don't have the passphrase."
    
    gpg --output "${revocation_cert}" --gen-revoke "${BACKUP_GPG_KEY_ID}" 2>/dev/null || true
    
    if [[ -f "${revocation_cert}" ]]; then
        log "Revocation certificate saved to: ${revocation_cert}"
        log "Store this securely with your private key"
    else
        log "Revocation certificate generation skipped (no passphrase set)"
    fi
}

test_encryption() {
    log "Testing encryption/decryption..."
    
    local test_file="${TEMP_DIR}/test.txt"
    local encrypted_file="${TEMP_DIR}/test.txt.gpg"
    local decrypted_file="${TEMP_DIR}/test-decrypted.txt"
    
    echo "Test data $(date)" > "${test_file}"
    
    gpg --encrypt --recipient "${BACKUP_GPG_KEY_ID}" \
        --output "${encrypted_file}" "${test_file}" \
        || error_exit "Encryption test failed"
    
    gpg --decrypt --output "${decrypted_file}" "${encrypted_file}" \
        || error_exit "Decryption test failed"
    
    if diff "${test_file}" "${decrypted_file}" >/dev/null; then
        log "Encryption/decryption test PASSED"
    else
        error_exit "Encryption/decryption test FAILED"
    fi
}

display_instructions() {
    log ""
    log "=================================================="
    log "BACKUP ENCRYPTION SETUP COMPLETE"
    log "=================================================="
    log ""
    log "Next steps:"
    log "1. Add these variables to your .env file:"
    log "   BACKUP_GPG_KEY_ID=${BACKUP_GPG_KEY_ID}"
    log "   BACKUP_DIR=\${PROJECT_ROOT}/backups"
    log "   BACKUP_S3_ENABLED=false"
    log "   BACKUP_S3_BUCKET=your-bucket-name"
    log ""
    log "2. Run a test backup:"
    log "   ./scripts/backup.sh"
    log ""
    log "3. Verify the backup:"
    log "   ./scripts/verify-backup.sh"
    log ""
    log "4. Test restore (optional):"
    log "   ./scripts/restore.sh"
    log ""
    log "5. Set up systemd timer (Linux only):"
    log "   sudo cp scripts/systemd/backup.{timer,service} /etc/systemd/system/"
    log "   sudo systemctl enable backup.timer"
    log "   sudo systemctl start backup.timer"
    log ""
}

main() {
    log "Setting up backup encryption..."
    
    check_gpg
    
    if gpg --list-secret-keys "${BACKUP_GPG_KEY_ID}" >/dev/null 2>&1; then
        log "GPG key ${BACKUP_GPG_KEY_ID} already exists"
        read -p "Generate a new key? This will invalidate old backups. (y/N): " confirm
        [[ "${confirm}" =~ ^[Yy]$ ]] || error_exit "Setup cancelled"
    fi
    
    generate_gpg_key
    export_public_key
    export_private_key
    save_revocation_certificate
    test_encryption
    
    display_instructions
}

main "$@"
