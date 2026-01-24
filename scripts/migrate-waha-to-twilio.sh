#!/bin/bash

set -euo pipefail

BACKUP_DIR=".backup/waha-to-twilio-$(date +%Y%m%d-%H%M%S)"
ADMIN_NUMBER="${ADMIN_NUMBER:-}"
TWILIO_ACCOUNT_SID="${TWILIO_ACCOUNT_SID:-}"
TWILIO_AUTH_TOKEN="${TWILIO_AUTH_TOKEN:-}"
TWILIO_WHATSAPP_SENDER="${TWILIO_WHATSAPP_SENDER:-}"
N8N_API_URL="${N8N_API_URL:-http://localhost:5678}"
N8N_API_KEY="${N8N_API_KEY:-}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_requirements() {
  log "Checking requirements..."

  if ! command -v jq &> /dev/null; then
    log "ERROR: jq not installed. Install with: brew install jq"
    exit 1
  fi

  if ! command -v curl &> /dev/null; then
    log "ERROR: curl not installed"
    exit 1
  fi

  if [[ -z "$TWILIO_ACCOUNT_SID" || -z "$TWILIO_AUTH_TOKEN" ]]; then
    log "ERROR: TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN must be set"
    exit 1
  fi

  if [[ -z "$ADMIN_NUMBER" ]]; then
    log "ERROR: ADMIN_NUMBER must be set (e.g., +491234567890)"
    exit 1
  fi

  log "✓ Requirements checked"
}

check_twilio_status() {
  log "Checking Twilio WhatsApp sender status..."

  local response
  response=$(curl -s -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
    "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/IncomingPhoneNumbers?PhoneNumber=$TWILIO_WHATSAPP_SENDER")

  local status
  status=$(echo "$response" | jq -r '.incoming_phone_numbers[0].status // "not_found"')

  if [[ "$status" == "not_found" ]]; then
    log "WARNING: WhatsApp sender not found. Continuing anyway..."
  else
    log "✓ WhatsApp sender status: $status"
  fi
}

backup_workflows() {
  log "Backing up current n8n workflows..."

  mkdir -p "$BACKUP_DIR/workflows"

  local workflows
  workflows=$(fd -e json . workflows/)

  if [[ -z "$workflows" ]]; then
    log "No workflows found to backup"
    return
  fi

  for wf in $workflows; do
    cp "$wf" "$BACKUP_DIR/workflows/"
  done

  log "✓ Backed up $(echo "$workflows" | wc -l) workflows to $BACKUP_DIR"
}

import_twilio_workflow() {
  log "Importing Twilio WhatsApp workflow..."

  local workflow_file="workflows/inbound-handler-twilio-whatsapp.json"

  if [[ ! -f "$workflow_file" ]]; then
    log "ERROR: Workflow file not found: $workflow_file"
    return 1
  fi

  local workflow_id
  workflow_id=$(curl -s -X POST \
    "$N8N_API_URL/api/workflows/import" \
    -H "Authorization: Bearer $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$workflow_file" | jq -r '.id // empty')

  if [[ -z "$workflow_id" ]]; then
    log "ERROR: Failed to import workflow"
    return 1
  fi

  log "✓ Imported workflow with ID: $workflow_id"

  echo "$workflow_id" > "$BACKUP_DIR/twilio_workflow_id.txt"
}

update_env_vars() {
  log "Updating environment variables..."

  local env_file=".env"

  if [[ -f "$env_file" ]]; then
    cp "$env_file" "$BACKUP_DIR/.env.backup"
  fi

  {
    echo "TWILIO_WHATSAPP_SENDER=$TWILIO_WHATSAPP_SENDER"
  } >> "$env_file"

  log "✓ Updated environment variables"
  log "  Set: TWILIO_WHATSAPP_SENDER=$TWILIO_WHATSAPP_SENDER"
}

test_send() {
  log "Testing WhatsApp send to admin..."

  local test_message="🧪 Test: Twilio WhatsApp migration successful. Sent at $(date '+%H:%M:%S')"

  local response
  response=$(curl -s -X POST \
    "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json" \
    -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
    --data-urlencode "From=$TWILIO_WHATSAPP_SENDER" \
    --data-urlencode "To=whatsapp:$ADMIN_NUMBER" \
    --data-urlencode "Body=$test_message")

  local status
  status=$(echo "$response" | jq -r '.status // "error"')

  if [[ "$status" == "queued" || "$status" == "sent" ]]; then
    log "✓ Test message sent successfully (status: $status)"
    local message_sid
    message_sid=$(echo "$response" | jq -r '.sid')
    echo "$message_sid" > "$BACKUP_DIR/test_message_sid.txt"
    return 0
  else
    log "ERROR: Failed to send test message"
    log "Response: $response"
    return 1
  fi
}

rollback() {
  log "⚠️  Rolling back changes..."

  if [[ -f "$BACKUP_DIR/.env.backup" ]]; then
    cp "$BACKUP_DIR/.env.backup" ".env"
    log "✓ Restored .env file"
  fi

  local workflow_id
  if [[ -f "$BACKUP_DIR/twilio_workflow_id.txt" ]]; then
    workflow_id=$(cat "$BACKUP_DIR/twilio_workflow_id.txt")

    curl -s -X DELETE \
      "$N8N_API_URL/api/workflows/$workflow_id" \
      -H "Authorization: Bearer $N8N_API_KEY" &> /dev/null || true

    log "✓ Removed Twilio workflow: $workflow_id"
  fi

  log "Rollback complete. Backup available at: $BACKUP_DIR"
  exit 1
}

main() {
  log "Starting WAHA to Twilio WhatsApp migration..."

  check_requirements
  check_twilio_status
  backup_workflows

  if ! import_twilio_workflow; then
    log "CRITICAL: Workflow import failed"
    rollback
  fi

  update_env_vars

  if ! test_send; then
    log "CRITICAL: Test send failed"
    log "Check admin WhatsApp for the message, or verify:"
    log "  1. Twilio WhatsApp sender is configured"
    log "  2. Template 'roof_mode_response' is approved"
    log "  3. Admin number is in approved test list"
    echo ""
    read -p "Continue anyway? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      rollback
    fi
  fi

  log "✅ Migration completed successfully!"
  log ""
  log "Next steps:"
  log "  1. Verify test message received on admin WhatsApp"
  log "  2. Apply WhatsApp templates with: ./scripts/apply-whatsapp-templates.sh"
  log "  3. Monitor first few incoming calls"
  log "  4. Backup location: $BACKUP_DIR"
}

main "$@"
