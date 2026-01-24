# Twilio Inbound Call Setup Guide

## Prerequisites

- Twilio account (free tier or paid)
- Verified account with payment method
- Public webhook endpoint (ngrok for testing, production URL for live)

---

## 1. Twilio Console Setup

### 1.1 Buy a German Number (+49)

1. Log in to https://console.twilio.com
2. Navigate to **Phone Numbers** → **Manage** → **Buy a Number**
3. Select country: **Germany (🇩🇪 +49)**
4. Choose number type:
   - **Geographic (Landline)**: Area-specific (e.g., 030 for Berlin)
     - Better trust, higher cost (~€1-3/month)
     - Recommended for businesses
   - **Mobile (Mobilfunk)**: Mobile number (e.g., 0151, 0176)
     - Lower cost (~€0.50-1/month)
     - Good for SMS-heavy usage
5. Search available numbers
6. Click **Buy** on selected number
7. Configure number immediately (see section 2)

### 1.2 Configure Voice Webhook

1. After purchasing, click on the number
2. Under **Voice & Fax** section:
   - **Accept Incoming**: Voice Calls
   - **Configure With**: Webhooks
   - **A CALL COMES IN**:
     - **Webhook URL**: `https://[YOUR_DOMAIN]/webhook/incoming-voice`
     - **HTTP Method**: `POST`
     - **Fallback URL**: `https://[YOUR_DOMAIN]/integrations/twilio/twiml-fallback.xml`
       - OR use TwiML Bin (see section 3)

3. Under **Advanced**:
   - **Status Callback**: `https://[YOUR_DOMAIN]/webhook/call-status` (optional)
   - **Status Callback HTTP Method**: `POST`
   - **Status Callback Event**:
     - ✅ completed
     - ✅ failed
     - ✅ no-answer
     - ✅ busy
   - **Call Screening**: Enable if you want to verify caller intent

4. Click **Save**

### 1.3 Create TwiML Bin (Fallback)

1. Navigate to **Developer Tools** → **Twilio Runtime** → **TwiML Bins**
2. Click **+ Create new TwiML Bin**
3. **Friendly Name**: `inbound-fallback`
4. Paste TwiML:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="de-DE" voice="alice">
    Hallo, hier ist [Company]. Bitte hinterlasse eine Nachricht oder schreib uns auf WhatsApp.
  </Say>
  <Record
    action="https://[YOUR_DOMAIN]/webhook/voicemail-complete"
    method="POST"
    maxLength="120"
    timeout="5"
    transcribe="true"
    transcribeCallback="https://[YOUR_DOMAIN]/webhook/transcribe"
  />
  <Say language="de-DE" voice="alice">
    Danke für Ihre Nachricht. Wir melden uns so schnell wie möglich bei Ihnen.
  </Say>
  <Hangup/>
</Response>
```

5. Replace `[YOUR_DOMAIN]` with your actual domain
6. Click **Save**
7. Copy the **TwiML URL** (format: `https://handler.twilio.com/twiml/...`)
8. Use this URL as **Fallback URL** in number configuration

---

## 2. Webhook Configuration

### 2.1 Environment Variables

Add to `.env`:

```bash
# Twilio
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_PHONE_NUMBER=+49xxxxxxxxx

# Webhook
WEBHOOK_BASE_URL=https://yourdomain.com
WEBHOOK_SECRET=your-webhook-secret

# WhatsApp (WAHA integration)
WAHA_BASE_URL=http://localhost:3000
WAHA_API_KEY=your-waha-api-key

# Telegram (optional)
TELEGRAM_BOT_TOKEN=your-bot-token
TELEGRAM_CHAT_ID=your-chat-id
```

### 2.2 Webhook Endpoint Structure

```
POST /webhook/incoming-voice
  └─ Handles incoming calls
  └─ Returns TwiML for greeting and options
  └─ Triggers notifications

POST /webhook/gather
  └─ Processes DTMF input
  └─ Routes to appropriate action

POST /webhook/voicemail-complete
  └─ Handles recording completion
  └─ Sends notifications with recording URL

POST /webhook/transcribe
  └─ Receives transcription
  └─ Updates records

POST /webhook/call-status
  └─ Receives call status updates
  └─ Logs call metrics
```

---

## 3. Number Configuration Options

### 3.1 Forwarding Rules

Configure in Twilio console under number settings:

**Primary Option - Webhook** (recommended):
- Webhook URL: `https://[DOMAIN]/webhook/incoming-voice`
- Method: POST
- Fallback: TwiML Bin or static file

**Secondary Option - Forwarding**:
- Set phone number to forward to: `+49xxxxxxxxx`
- Keep webhook for voicemail when line is busy

### 3.2 Call Screening

Enable to ask caller for name before connecting:

```xml
<Gather action="/webhook/screened" numDigits="1">
  <Say>
    Press 1 for new inquiries.
    Press 2 for existing customers.
    Press 3 for emergencies.
  </Say>
</Gather>
```

### 3.3 Business Hours

Implement time-based routing in webhook:

```javascript
const now = new Date();
const hour = now.getHours();
const day = now.getDay();

const businessHours = day >= 1 && day <= 5 && hour >= 8 && hour < 20;

if (businessHours) {
  // Return connect TwiML
} else {
  // Return voicemail TwiML with closed message
}
```

---

## 4. Test Calls

### 4.1 Local Testing with Ngrok

```bash
# Start ngrok
ngrok http 3000

# Output: https://random-id.ngrok-free.app
```

Update `.env`:
```bash
WEBHOOK_BASE_URL=https://random-id.ngrok-free.app
```

### 4.2 Test Webhook Connectivity

```bash
# Use test script
./scripts/test-twilio-webhook.sh

# Or manually curl
curl -X POST https://yourdomain.com/webhook/health \
  -H "Content-Type: application/json"
```

Expected response:
```json
{"status":"ok","timestamp":"2026-01-24T16:00:00.000Z"}
```

### 4.3 Verify TwiML Response

Use Twilio Debugger:
1. Go to **Monitor** → **Debugger** in Twilio Console
2. Filter by phone number
3. Check TwiML returned is valid XML
4. Validate `Content-Type: application/xml`

### 4.4 Check WhatsApp Notification

After test call:
1. Verify WhatsApp message sent to configured number
2. Check message contains:
   - Caller number
   - Call duration
   - Voicemail URL (if applicable)
   - Timestamp

### 4.5 Verify Telegram Bot Notification

1. Check configured Telegram chat
2. Verify message format:
   ```
   📞 Incoming Call
   From: +49123456789
   Duration: 45s
   Voicemail: https://api.twilio.com/...
   ```

---

## 5. Troubleshooting

### 5.1 Webhook Timeouts

**Symptom**: Call ends immediately, no greeting

**Solutions**:
- Check webhook URL is publicly accessible (not localhost)
- Verify firewall allows Twilio IPs (see: https://www.twilio.com/docs/usage/security)
- Add timeout configuration:
  ```javascript
  app.post('/webhook/incoming-voice', (req, res) => {
    res.type('application/xml');
    res.send(twiML); // Must respond within 15 seconds
  });
  ```

### 5.2 Invalid TwiML

**Symptom**: "The application returned an error" in Twilio Debugger

**Solutions**:
- Validate XML structure using https://www.twilio.com/docs/twiml
- Ensure proper XML header:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <Response xmlns="http://twilio.com/xml/robot">
    ...
  </Response>
  ```
- Check for special characters in text (escape with CDATA if needed)
- Use TwiML Validator in Twilio Console

### 5.3 Number Not Receiving Calls

**Symptom**: Call goes to voicemail or "number not in service"

**Checklist**:
- ✅ Number is active in Twilio Console
- ✅ Number has voice capability enabled
- ✅ Webhook URL is correct and accessible
- ✅ HTTP method is POST (not GET)
- ✅ No forwarding rules conflicting
- ✅ Payment method is valid

### 5.4 Voice Quality Issues

**Symptom**: Choppy audio, delays, poor quality

**Solutions**:
- Check internet bandwidth (min 1 Mbps per concurrent call)
- Use regional Twilio edge locations:
  ```javascript
  const twilio = new Client(accountSid, authToken, {
    edge: 'frankfurt'  // Closest to Germany
  });
  ```
- Verify codec (G.711 is default, try Opus if supported)
- Check network latency to Twilio servers

### 5.5 Voicemail Not Recording

**Symptom**: Call ends without recording

**Solutions**:
- Verify `<Record>` timeout (set to 5+ seconds)
- Check recording permissions in Twilio account settings
- Ensure `action` URL is accessible
- Test with `<Record playBeep="true">` to confirm recording starts

### 5.6 Notifications Not Sending

**Symptom**: WhatsApp/Telegram messages not delivered

**Checklist**:
- ✅ WAHA service is running
- ✅ WhatsApp session is connected
- ✅ Telegram bot token is valid
- ✅ Webhook logs show notification attempt
- ✅ Check WAHA logs: `docker logs waha`

---

## 6. Production Checklist

Before going live:

- [ ] Test webhook from multiple locations (cell, landline)
- [ ] Verify WhatsApp integration works end-to-end
- [ ] Confirm Telegram bot delivers messages
- [ ] Set up monitoring/alerting for webhook failures
- [ ] Configure Twilio Monitor alerts
- [ ] Test fallback TwiML (take webhook down temporarily)
- [ ] Verify business hours routing works
- [ ] Check voicemail transcription accuracy
- [ ] Test with high volume (simulate multiple concurrent calls)
- [ ] Document escalation procedure for failed calls
- [ ] Set up Google Sheets tracking (if configured)
- [ ] Review Twilio billing and set usage alerts

---

## 7. Quick Reference

### Twilio Console URLs

- Phone Numbers: https://console.twilio.com/us1/develop/phone-numbers/manage
- TwiML Bins: https://console.twilio.com/us1/develop/runtime/twiml-bins
- Debugger: https://console.twilio.com/us1/monitor/debugger
- Monitor: https://console.twilio.com/us1/monitor/logs/calls

### IP Addresses to Whitelist

Twilio may call from these ranges (whitelist in firewall):
- `3.21.0.0/16`
- `3.20.0.0/16`
- `54.244.0.0/15`
- `54.208.0.0/13`
- (Full list: https://www.twilio.com/docs/usage/security)

### Webhook Headers from Twilio

```http
X-Twilio-Signature: xxxxx (for request validation)
User-Agent: TwilioProxy/1.1
Content-Type: application/x-www-form-urlencoded
```

### Key TwiML Elements

- `<Say>`: Text-to-speech
- `<Gather>`: Collect DTMF input
- `<Record>`: Record call
- `<Dial>`: Forward call
- `<Pause>`: Silence
- `<Hangup>`: End call
- `<Redirect>`: Forward to another URL
