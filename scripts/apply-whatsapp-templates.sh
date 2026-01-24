#!/bin/bash

set -euo pipefail

TEMPLATES_FILE="config/twilio-whatsapp-templates.json"
TWILIO_ACCOUNT_SID="${TWILIO_ACCOUNT_SID:-}"
TWILIO_AUTH_TOKEN="${TWILIO_AUTH_TOKEN:-}"
TWILIO_WHATSAPP_SENDER="${TWILIO_WHATSAPP_SENDER:-}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

check_requirements() {
  log "Checking requirements..."

  if ! command -v jq &> /dev/null; then
    error "jq not installed. Install with: brew install jq"
    exit 1
  fi

  if ! command -v curl &> /dev/null; then
    error "curl not installed"
    exit 1
  fi

  if [[ -z "$TWILIO_ACCOUNT_SID" || -z "$TWILIO_AUTH_TOKEN" ]]; then
    error "TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN must be set"
    exit 1
  fi

  if [[ ! -f "$TEMPLATES_FILE" ]]; then
    error "Templates file not found: $TEMPLATES_FILE"
    exit 1
  fi

  log "✓ Requirements checked"
}

validate_template() {
  local template_name="$1"
  local template_data="$2"

  local name
  local category
  local language
  local body
  local variables

  name=$(echo "$template_data" | jq -r '.name')
  category=$(echo "$template_data" | jq -r '.category')
  language=$(echo "$template_data" | jq -r '.language')
  body=$(echo "$template_data" | jq -r '.body')
  variables=$(echo "$template_data" | jq -r '.variables[]?' | wc -l)

  local errors=()

  [[ -z "$name" ]] && errors+=("Missing 'name'")
  [[ -z "$category" ]] && errors+=("Missing 'category'")
  [[ -z "$language" ]] && errors+=("Missing 'language'")
  [[ -z "$body" ]] && errors+=("Missing 'body'")

  if ! [[ "$category" =~ ^(MARKETING|UTILITY|AUTHENTICATION)$ ]]; then
    errors+=("Invalid category: $category (must be MARKETING, UTILITY, or AUTHENTICATION)")
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    error "Template '$template_name' validation failed:"
    for err in "${errors[@]}"; do
      error "  - $err"
    done
    return 1
  fi

  log "✓ Template '$template_name' is valid"
  return 0
}

submit_template() {
  local template_name="$1"
  local template_data="$2"

  local name
  local category
  local language
  local body

  name=$(echo "$template_data" | jq -r '.name')
  category=$(echo "$template_data" | jq -r '.category')
  language=$(echo "$template_data" | jq -r '.language')
  body=$(echo "$template_data" | jq -r '.body')

  log "Submitting template: $name"

  local response
  response=$(curl -s -X POST \
    "https://content.twilio.com/v1/Services/$TWILIO_WHATSAPP_SENDER/Templates" \
    -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"FriendlyName\": \"$name\",
      \"Language\": \"$language\",
      \"Category\": \"$category\",
      \"Content\": {
        \"Type\": \"text_body\",
        \"Text\": \"$body\"
      }
    }")

  local sid
  sid=$(echo "$response" | jq -r '.sid // empty')

  if [[ -z "$sid" ]]; then
    error "Failed to submit template '$name'"
    error "Response: $response"
    return 1
  fi

  log "✓ Template submitted (SID: $sid)"
  echo "$template_name,$sid" >> .twilio_template_sids.csv

  return 0
}

get_template_status() {
  local template_name="$1"

  if [[ ! -f ".twilio_template_sids.csv" ]]; then
    error "No template SIDs found. Run submission first."
    return 1
  fi

  local sid
  sid=$(grep "^$template_name," .twilio_template_sids.csv | cut -d',' -f2)

  if [[ -z "$sid" ]]; then
    error "Template SID not found for: $template_name"
    return 1
  fi

  local response
  response=$(curl -s -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
    "https://content.twilio.com/v1/Services/$TWILIO_WHATSAPP_SENDER/Templates/$sid")

  local status
  status=$(echo "$response" | jq -r '.Status // "unknown"')

  echo "Template: $template_name"
  echo "SID: $sid"
  echo "Status: $status"
  echo ""

  if [[ "$status" == "approved" ]]; then
    log "✓ Template '$template_name' is approved"
  elif [[ "$status" == "pending" ]]; then
    log "⏳ Template '$template_name' is pending approval"
  elif [[ "$status" == "rejected" ]]; then
    local reason
    reason=$(echo "$response" | jq -r '.RejectionReason // "unknown"')
    error "✗ Template '$template_name' was rejected"
    error "Reason: $reason"
  else
    log "? Template '$template_name' status: $status"
  fi

  return 0
}

export_approved_templates() {
  log "Exporting approved templates..."

  local response
  response=$(curl -s -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
    "https://content.twilio.com/v1/Services/$TWILIO_WHATSAPP_SENDER/Templates")

  local approved
  approved=$(echo "$response" | jq -r '.templates[] | select(.status == "approved") | {name: .friendly_name, sid: .sid, language: .language, content: .content.text}')

  if [[ -z "$approved" ]]; then
    log "No approved templates found"
    return 0
  fi

  echo "$approved" | jq -s '{templates: .}' > config/twilio-approved-templates.json

  log "✓ Exported approved templates to config/twilio-approved-templates.json"
  return 0
}

main() {
  local action="${1:-submit}"

  check_requirements

  case "$action" in
    submit)
      log "Submitting WhatsApp templates to Twilio..."

      rm -f .twilio_template_sids.csv
      echo "template_name,sid" > .twilio_template_sids.csv

      local templates
      templates=$(jq -r 'keys[]' "$TEMPLATES_FILE")

      for template_name in $templates; do
        local template_data
        template_data=$(jq ".\"$template_name\"" "$TEMPLATES_FILE")

        if validate_template "$template_name" "$template_data"; then
          submit_template "$template_name" "$template_data"
        fi
      done

      log "Template submission complete"
      log "Check status with: $0 status"
      log "Track SIDs in: .twilio_template_sids.csv"
      ;;

    status)
      log "Checking template status..."

      local templates
      templates=$(jq -r 'keys[]' "$TEMPLATES_FILE")

      for template_name in $templates; do
        get_template_status "$template_name"
      done
      ;;

    export)
      export_approved_templates
      ;;

    *)
      echo "Usage: $0 {submit|status|export}"
      echo ""
      echo "Commands:"
      echo "  submit   - Submit all templates from config/twilio-whatsapp-templates.json"
      echo "  status   - Check approval status of submitted templates"
      echo "  export   - Export approved templates to config/twilio-approved-templates.json"
      exit 1
      ;;
  esac
}

main "$@"
