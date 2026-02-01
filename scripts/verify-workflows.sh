#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

N8N_BASE_URL="${N8N_BASE_URL:-https://instance1.duckdns.org}"
N8N_API_URL="${N8N_BASE_URL}/api/v1"

if [ -z "$N8N_API_KEY" ]; then
    echo "ERROR: N8N_API_KEY not set"
    echo "Run: export N8N_API_KEY=<your-key>"
    exit 1
fi

echo "=== n8n Workflows Status ==="
echo ""

echo "Active workflows:"
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" | \
    jq -r '.data[] | select(.active == true) | "\(.name) (\(.id))"' 2>/dev/null || \
    curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" | \
    grep -o '"name":"[^"]*","active":true' | sed 's/"name":/  /;s/","active":true//'

echo ""
echo "Inactive workflows:"
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" | \
    jq -r '.data[] | select(.active == false) | "\(.name) (\(.id))"' 2>/dev/null || \
    curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" | \
    grep -o '"name":"[^"]*","active":false' | sed 's/"name":/  /;s/","active":false//'

echo ""
echo "=== Webhooks ==="
echo "Checking webhook registration in database..."
ssh ralf_waldukat@instance1.duckdns.org \
    "sudo sqlite3 /var/lib/docker/volumes/vorzimmerdrache_n8n_data/_data/database.sqlite \
    'SELECT workflowId, webhookPath, method FROM webhook_entity;' 2>/dev/null || echo 'No webhooks registered'"

echo ""
echo "Webhook URLs:"
echo "  Voice: ${N8N_BASE_URL}/webhook/incoming-call"
echo "  SMS:   ${N8N_BASE_URL}/webhook/sms-response"
