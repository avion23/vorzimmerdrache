#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

N8N_BASE_URL="${N8N_BASE_URL:-https://instance1.duckdns.org}"
N8N_API_URL="${N8N_BASE_URL}/api/v1"

if [ -z "$N8N_API_KEY" ]; then
    echo "ERROR: N8N_API_KEY not set"
    echo "Get your API key from: $N8N_BASE_URL/settings/api"
    echo "Then run: export N8N_API_KEY=<your-key>"
    exit 1
fi

echo "=== Recreating n8n Workflows ==="
echo "API: $N8N_API_URL"
echo ""

SMS_WORKFLOW="$(cat workflows/sms-working.json)"
ROOF_WORKFLOW="$(cat workflows/roof-mode-simple.json)"

echo "1. Importing SMS Opt-In workflow..."
SMS_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -d "$SMS_WORKFLOW" \
    "$N8N_API_URL/workflows")

SMS_ID=$(echo "$SMS_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$SMS_ID" ]; then
    echo "   ✓ Imported: $SMS_ID"
else
    echo "   ✗ Failed: $SMS_RESPONSE"
    exit 1
fi

echo ""
echo "2. Importing Roof-Mode workflow..."
ROOF_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -d "$ROOF_WORKFLOW" \
    "$N8N_API_URL/workflows")

ROOF_ID=$(echo "$ROOF_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$ROOF_ID" ]; then
    echo "   ✓ Imported: $ROOF_ID"
else
    echo "   ✗ Failed: $ROOF_RESPONSE"
    exit 1
fi

echo ""
echo "3. Activating SMS Opt-In..."
ACTIVATE_SMS=$(curl -s -X PATCH \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -d '{"active": true}' \
    "$N8N_API_URL/workflows/$SMS_ID")

if echo "$ACTIVATE_SMS" | grep -q '"active":true'; then
    echo "   ✓ Activated"
else
    echo "   ✗ Failed: $ACTIVATE_SMS"
fi

echo ""
echo "4. Activating Roof-Mode..."
ACTIVATE_ROOF=$(curl -s -X PATCH \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -d '{"active": true}' \
    "$N8N_API_URL/workflows/$ROOF_ID")

if echo "$ACTIVATE_ROOF" | grep -q '"active":true'; then
    echo "   ✓ Activated"
else
    echo "   ✗ Failed: $ACTIVATE_ROOF"
fi

echo ""
echo "=== Verification ==="
echo "Checking workflows..."
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" | \
    grep -o '"name":"[^"]*","active":[^,]*' | \
    sed 's/"name":/Name: /;s/","active":/ Active: /;s/"//' | \
    grep -E "(SMS Opt-In|Roof-Mode)"

echo ""
echo "=== Webhook URLs for Twilio ==="
echo "Voice: ${N8N_BASE_URL}/webhook/incoming-call"
echo "SMS:   ${N8N_BASE_URL}/webhook/sms-response"
echo ""
echo "Done. Configure credentials in n8n UI if needed."
