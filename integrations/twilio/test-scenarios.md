# Twilio Inbound Call Test Scenarios

## Test Environment Setup

```bash
# Start ngrok for local testing
ngrok http 3000

# Set environment
export WEBHOOK_BASE_URL=https://your-ngrok-url.ngrok-free.app
export TWILIO_PHONE_NUMBER=+49xxxxxxxxx
```

---

## Test Cases

### 1. Basic Inbound Call

**Objective**: Verify webhook receives call and returns valid TwiML

**Steps**:
1. Call Twilio number from personal phone
2. Listen for greeting: "Hallo, hier ist [Company]..."
3. Wait for recording prompt
4. Leave test message
5. Hang up

**Expected Results**:
- ✅ Greeting plays in German
- ✅ Recording starts with beep
- ✅ Recording completes after message
- ✅ Call ends with "Danke für Ihre Nachricht"

**Check**:
- Twilio Debugger shows `200 OK` response
- Webhook logs show call received
- Recording appears in Twilio Console

---

### 2. Webhook Connectivity Test

**Objective**: Verify webhook endpoint is accessible

**Steps**:
1. Run health check:
   ```bash
   curl -X POST https://yourdomain.com/webhook/health \
     -H "Content-Type: application/json"
   ```

**Expected Results**:
- ✅ Response: `{"status":"ok","timestamp":"..."}`
- ✅ Response time < 500ms

**Alternative**:
- Use test script: `./scripts/test-twilio-webhook.sh`

---

### 3. TwiML Validation Test

**Objective**: Validate TwiML is properly formed

**Steps**:
1. Call Twilio number
2. Let it ring 3 times
3. Answer

**Expected Results**:
- ✅ No error messages from Twilio
- ✅ Greeting plays without interruption
- ✅ XML structure valid

**Check in Twilio Debugger**:
- Look for "TwiML Result" section
- Verify no XML parsing errors

---

### 4. Voicemail Recording Test

**Objective**: Verify recording and transcription works

**Steps**:
1. Call Twilio number
2. Wait for recording prompt
3. Say test message: "This is a test voicemail from [your name] at [timestamp]"
4. Wait for completion
5. Hang up

**Expected Results**:
- ✅ Recording is saved
- ✅ Transcription appears in Twilio Console
- ✅ Transcription text is accurate (70%+)
- ✅ Recording URL is accessible

**Verification**:
```bash
# Check transcription callback
grep "TranscriptionText" webhook-logs.log
```

---

### 5. WhatsApp Notification Test

**Objective**: Verify WhatsApp message is sent after call

**Steps**:
1. Make test call
2. Leave voicemail
3. Hang up
4. Check WhatsApp business number

**Expected Results**:
- ✅ WhatsApp message received
- ✅ Message contains:
  - Caller number
  - Call duration
  - Voicemail URL
  - Timestamp
- ✅ Message format is readable

**Sample Message**:
```
📞 Neue Sprachnachricht
Von: +49123456789
Dauer: 25s
Nachricht: "This is a test voicemail..."
Aufnahme: https://api.twilio.com/2020-04-01/Accounts/.../Recordings/...
Zeit: 2026-01-24 16:30:00
```

**Check WAHA logs**:
```bash
docker logs waha | grep "message"
```

---

### 6. Telegram Bot Notification Test

**Objective**: Verify Telegram bot sends notification

**Steps**:
1. Make test call
2. Leave voicemail
3. Check Telegram chat

**Expected Results**:
- ✅ Telegram message received
- ✅ Message contains call details
- ✅ Recording URL works
- ✅ Formatting is clean

**Sample Message**:
```
📞 Incoming Call
From: +49123456789
Duration: 25s
Voicemail: https://api.twilio.com/...
Transcript: "This is a test voicemail..."
```

**Check Telegram API**:
```bash
curl -X GET "https://api.telegram.org/bot[TOKEN]/getUpdates"
```

---

### 7. Fallback TwiML Test

**Objective**: Verify fallback works when webhook is down

**Steps**:
1. Stop webhook server
2. Call Twilio number
3. Listen for fallback message

**Expected Results**:
- ✅ Fallback TwiML plays
- ✅ Message: "Hallo, hier ist [Company]..."
- ✅ Voicemail still records (if configured)
- ✅ Call completes gracefully

**Check**:
- Twilio Debugger shows fallback URL was used
- Recording still saved to Twilio

---

### 8. Business Hours Routing Test

**Objective**: Verify different behavior for business/non-business hours

**Steps** (during business hours 08:00-20:00):
1. Call Twilio number
2. Expect normal greeting

**Steps** (outside business hours):
1. Call Twilio number
2. Expect different message: "Wir sind derzeit geschlossen..."

**Expected Results**:
- ✅ Different TwiML returned based on time
- ✅ Both work correctly
- ✅ Transitions are smooth

---

### 9. DTMF Input Test

**Objective**: Verify DTMF (keypress) handling

**Steps** (if `<Gather>` is configured):
1. Call Twilio number
2. Wait for prompt: "Press 1 for inquiries, 2 for support..."
3. Press "1"
4. Verify routing

**Expected Results**:
- ✅ Keypress is recognized
- ✅ Correct action is taken
- ✅ No timeout after input

**Check webhook logs**:
```bash
grep "Digits" webhook-logs.log
```

---

### 10. Concurrent Call Test

**Objective**: Verify system handles multiple calls

**Steps**:
1. Make 3 simultaneous calls from different phones
2. Let all calls go to voicemail
3. Hang up after 10 seconds

**Expected Results**:
- ✅ All calls are handled
- ✅ No errors in webhook
- ✅ All recordings saved
- ✅ All notifications sent

**Check**:
- Twilio Console shows all calls
- Webhook logs show no crashes

---

### 11. Webhook Timeout Test

**Objective**: Verify webhook timeout handling

**Steps**:
1. Add artificial delay to webhook:
   ```javascript
   app.post('/webhook/incoming-voice', (req, res) => {
     setTimeout(() => {
       res.type('application/xml').send(twiML);
     }, 20000); // 20 second delay
   });
   ```
2. Call Twilio number
3. Observe behavior

**Expected Results**:
- ✅ Fallback TwiML is used
- ✅ Call doesn't drop
- ✅ Error is logged

---

### 12. Invalid Caller ID Test

**Objective**: Verify handling of blocked/unknown numbers

**Steps**:
1. Block caller ID (dial *31# before call)
2. Call Twilio number
3. Leave voicemail

**Expected Results**:
- ✅ Call is handled normally
- ✅ Caller shows as "Unknown" or "+0000..."
- ✅ Recording is saved
- ✅ Notification sent (with "Unknown" caller)

---

### 13. Recording Quality Test

**Objective**: Verify audio quality of recordings

**Steps**:
1. Call from different phone types:
   - Landline
   - Mobile (4G)
   - Mobile (WiFi calling)
2. Leave same test message each time
3. Compare recordings in Twilio Console

**Expected Results**:
- ✅ All recordings are clear
- ✅ No clipping or distortion
- ✅ Transcription accuracy > 70%
- ✅ File size reasonable (~100KB for 30s)

---

### 14. Webhook Signature Validation Test

**Objective**: Verify request signature validation works

**Steps**:
1. Enable signature validation:
   ```javascript
   const signature = req.headers['x-twilio-signature'];
   const isValid = twilio.validateRequest(
     authToken,
     signature,
     url,
     req.body
   );
   ```
2. Make test call from Twilio
3. Try spoofed request:
   ```bash
   curl -X POST https://yourdomain.com/webhook/incoming-voice \
     -H "X-Twilio-Signature: fake-signature" \
     -d "Caller=+49123456789"
   ```

**Expected Results**:
- ✅ Valid requests are accepted
- ✅ Invalid signatures are rejected
- ✅ Webhook logs show validation result

---

### 15. Status Callback Test

**Objective**: Verify status callback receives updates

**Steps**:
1. Make test call
2. Let it ring 5 times, then hang up
3. Check webhook logs for status updates

**Expected Results**:
- ✅ Status updates received:
  - `queued`
  - `ringing`
  - `in-progress` (if answered)
  - `completed` or `no-answer`
- ✅ Call duration logged
- ✅ Error codes (if any)

**Check logs**:
```bash
grep "CallStatus" webhook-logs.log
```

---

## Automated Test Suite

```bash
#!/bin/bash
# Run all tests
./scripts/test-twilio-webhook.sh --all

# Run specific test
./scripts/test-twilio-webhook.sh --test voicemail

# Run with verbose output
./scripts/test-twilio-webhook.sh --verbose
```

---

## Test Results Template

```markdown
## Test Run: 2026-01-24

| Test Case | Status | Notes |
|-----------|--------|-------|
| Basic Inbound Call | ✅ PASS | Greeting works |
| Webhook Connectivity | ✅ PASS | 150ms response |
| TwiML Validation | ✅ PASS | Valid XML |
| Voicemail Recording | ⚠️ WARN | Transcription 65% |
| WhatsApp Notification | ✅ PASS | Received |
| Telegram Notification | ❌ FAIL | No message sent |
| Fallback TwiML | ✅ PASS | Works when webhook down |
| Business Hours | ✅ PASS | Routes correctly |
| DTMF Input | N/A | Not configured |
| Concurrent Calls | ✅ PASS | 3 calls handled |
| Webhook Timeout | ✅ PASS | Fallback used |
| Invalid Caller ID | ✅ PASS | Handled |
| Recording Quality | ✅ PASS | Clear audio |
| Signature Validation | ✅ PASS | Rejects invalid |
| Status Callback | ✅ PASS | All statuses logged |

**Summary**: 13/14 passed (92%)
```

---

## Troubleshooting by Symptom

| Symptom | Likely Cause | Check Test |
|---------|--------------|------------|
| No greeting | Webhook down | Test 7 (Fallback) |
| No recording | TwiML error | Test 3 (Validation) |
| No WhatsApp | WAHA offline | Check docker logs |
| Poor audio quality | Network | Test 13 (Quality) |
| Call drops | Timeout | Test 11 (Timeout) |
| Wrong message | Business hours bug | Test 8 (Business hours) |
