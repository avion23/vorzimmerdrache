#!/bin/bash

set -e

N8N_BASE_URL="${N8N_BASE_URL:-https://instance1.duckdns.org}"

echo "=== Testing n8n Webhooks ==="
echo ""

echo "1. Testing SMS Webhook (sms-response)..."
echo "   Sending test request..."
SMS_RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
    "${N8N_BASE_URL}/webhook/sms-response" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "From=%2B49151123456789&Body=JA" 2>/dev/null)

SMS_HTTP=$(echo "$SMS_RESULT" | grep "HTTP_CODE:" | cut -d: -f2)
SMS_BODY=$(echo "$SMS_RESULT" | grep -v "HTTP_CODE:")

echo "   HTTP $SMS_HTTP"
echo "   Response: $SMS_BODY"
if [ "$SMS_HTTP" = "200" ]; then
    echo "   ✓ SMS webhook working"
else
    echo "   ✗ SMS webhook failed"
fi

echo ""
echo "2. Testing Voice Webhook (incoming-call)..."
echo "   Sending test request..."
VOICE_RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
    "${N8N_BASE_URL}/webhook/incoming-call" \
    -H "Content-Type: application/json" \
    -d '{"From":"+49151123456789","CallStatus":"ringing"}' 2>/dev/null)

VOICE_HTTP=$(echo "$VOICE_RESULT" | grep "HTTP_CODE:" | cut -d: -f2)
VOICE_BODY=$(echo "$VOICE_RESULT" | grep -v "HTTP_CODE:")

echo "   HTTP $VOICE_HTTP"
echo "   Response: ${VOICE_BODY:0:100}..."
if [ "$VOICE_HTTP" = "200" ] || [ "$VOICE_HTTP" = "201" ]; then
    echo "   ✓ Voice webhook working"
else
    echo "   ✗ Voice webhook failed"
fi

echo ""
echo "To test with real Twilio:"
echo "1. Send SMS to +19135654323 with 'JA'"
echo "2. Call +19135654323"
echo ""
echo "Check executions at: ${N8N_BASE_URL}/executions"
