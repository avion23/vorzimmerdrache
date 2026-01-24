#!/bin/bash

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
INSTALLER_TELEGRAM_CHAT_ID="${INSTALLER_TELEGRAM_CHAT_ID:-}"

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$INSTALLER_TELEGRAM_CHAT_ID" ]; then
  echo "Error: TELEGRAM_BOT_TOKEN and INSTALLER_TELEGRAM_CHAT_ID must be set"
  exit 1
fi

MESSAGE="$1"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${INSTALLER_TELEGRAM_CHAT_ID}\",
    \"text\": \"${MESSAGE}\",
    \"parse_mode\": \"HTML\"
  }"
