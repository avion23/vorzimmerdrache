#!/bin/bash
# Quick 3Q Flow Final Setup & Test

set -e

N8N_HOST="https://instance1.duckdns.org"
API_KEY=$(grep N8N_API_KEY .env.local | cut -d'=' -f2)

echo "🚀 3Q Flow Final Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━"

# 1. Activate workflows via API
echo "📤 Activating workflows..."

# Get workflow IDs and activate
for workflow_id in $(curl -s "$N8N_HOST/api/v1/workflows" \
  -H "X-N8N-API-KEY: $API_KEY" | jq -r '.data[].id'); do
  
  curl -s -X POST "$N8N_HOST/api/v1/workflows/$workflow_id/activate" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -o /dev/null
  echo "  ✅ Activated: $workflow_id"
done

# 2. Test webhook
echo ""
echo "🧪 Testing SMS webhook..."
curl -s -X POST "$N8N_HOST/webhook/sms-response" \
  -d "From=+491711234567" \
  -d "Body=JA" \
  -d "AccountSid=test" | head -c 100

echo ""
echo ""
echo "✅ Setup complete!"
echo ""
echo "⚠️  MANUAL STEP: Add these columns to Google Sheets Lead_DB:"
echo "   conversation_state | plz | kwh_consumption | meter_photo_url | qualification_timestamp | last_state_change"
echo ""
echo "Test with:"
echo "  curl -X POST $N8N_HOST/webhook/sms-response -d 'From=+491711234567' -d 'Body=JA'"
