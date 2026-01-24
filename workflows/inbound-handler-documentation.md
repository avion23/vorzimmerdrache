# Inbound Call Handler - Roof Mode Documentation

## Overview
This workflow handles incoming voice calls when installers are on the roof (Roof Mode/Dach-Modus). It immediately responds with a German voice message, sends a WhatsApp to the caller, and notifies the installer via Telegram.

## Flow Diagram
```
Webhook → Normalize Phone → CRM Lookup → Parse CRM Data
                                         ↓
                              ┌──────────┴──────────┐
                              ↓                     ↓
                    TwiML Response      Prepare WhatsApp → Send WhatsApp → If Failed → SMS Fallback
                              ↓
                    Prepare Telegram → Send Telegram → If Failed → Log Error
```

## Node-by-Node Explanation

### 1. Webhook Trigger
- **Type:** Webhook
- **Path:** `/webhook/incoming-voice`
- **Method:** POST
- **Response Mode:** Response Node
- **Purpose:** Receives Twilio voice webhook data with caller information
- **Input:** `From`, `CallSid`, `To`, `FromCity`, `FromState` from Twilio
- **Location:** workflows/inbound-handler.json:6-16

### 2. Normalize Phone Number
- **Type:** Code Node (JavaScript)
- **Purpose:** Converts German phone numbers to E.164 format (+49...)
- **Formats Handled:**
  - `01701234567` → `+491701234567`
  - `+491701234567` → `+491701234567` (unchanged)
  - `00491701234567` → `+491701234567`
- **Output:** `originalPhone`, `normalizedPhone`, `callSid`, `toNumber`, `fromCity`, `fromState`, `timestamp`
- **Location:** workflows/inbound-handler.json:17-44

### 3. CRM Lookup
- **Type:** Google Sheets
- **Operation:** Lookup
- **Sheet:** CRM
- **Purpose:** Checks if caller is an existing customer by phone number
- **Credentials:** googleSheetsOAuth2Api
- **Output:** Returns matching rows with phone, name, status, address, projectType
- **Location:** workflows/inbound-handler.json:45-65

### 4. Parse CRM Data
- **Type:** Code Node (JavaScript)
- **Purpose:** Processes CRM lookup results to extract customer information
- **Logic:**
  - Iterates through CRM results
  - Matches normalized phone number
  - Returns customer object with `found`, `name`, `status`, `address`, `projectType`
  - Default: `name: 'Unbekannt'`, `status: 'New Lead'` if not found
- **Location:** workflows/inbound-handler.json:66-97

### 5. TwiML Voice Response
- **Type:** Respond to Webhook
- **Response Type:** XML (TwiML)
- **Purpose:** Returns immediate voice response to caller
- **Voice:** alice, de-DE (German female voice)
- **Message:**
  ```
  "Hallo, hier ist Solar Vorzimmerdrache. Wir sind gerade auf dem Dach bei einer Montage. 
  Ich habe deine Nummer gesehen und schicke dir sofort eine WhatsApp. Bitte antworte dort kurz."
  ```
- **Action:** Auto-hangup after message
- **Location:** workflows/inbound-handler.json:98-116
- **Critical:** Always executes immediately, doesn't block on other notifications

### 6. Prepare WhatsApp Message
- **Type:** Code Node (JavaScript)
- **Purpose:** Constructs WhatsApp message with German template and emojis
- **Message:**
  ```
  👋 Moin! Hab deinen Anruf gesehen. Bin gerade auf dem Dach.
  
  Schreib mir kurz hier:
  1. Geht es um eine neue Anlage?
  2. Oder hast du eine Frage zu einem Termin?
  
  Ich melde mich, sobald ich wieder unten bin! ☀️
  ```
- **Variables:** `phone`, `message`, `customerName`
- **Location:** workflows/inbound-handler.json:117-141

### 7. Send WhatsApp
- **Type:** HTTP Request
- **Method:** POST
- **URL:** `$env.WAHA_API_URL/api/sendText`
- **Auth:** Bearer token via WAHA_API_TOKEN
- **Purpose:** Sends WhatsApp message to caller via Waha API
- **Body:**
  ```json
  {
    "session": "default",
    "chatId": "<normalizedPhone>",
    "text": "<message>"
  }
  ```
- **Location:** workflows/inbound-handler.json:142-179

### 8. If WhatsApp Failed
- **Type:** IF Node
- **Purpose:** Checks if WhatsApp send failed
- **Condition:** `error` or `status` contains "error"
- **Branches:**
  - **True:** Send SMS fallback
  - **False:** End flow
- **Location:** workflows/inbound-handler.json:180-205

### 9. SMS Fallback
- **Type:** Twilio
- **Operation:** Send SMS
- **Purpose:** Sends SMS to caller if WhatsApp fails
- **Credentials:** twilioApi
- **Message:**
  ```
  "Hallo! Hab deinen Anruf gesehen. Wir sind gerade auf dem Dach. 
  Schreib uns eine WhatsApp oder ruf später wieder an."
  ```
- **Location:** workflows/inbound-handler.json:206-223

### 10. Prepare Telegram Message
- **Type:** Code Node (JavaScript)
- **Purpose:** Constructs installer notification message
- **Message:**
  ```
  📞 Verpasster Anruf von <phone>
  Name: <Name oder 'Unbekannt'>
  Zeit: <Timestamp>
  
  Habe ihm eine WhatsApp geschickt.
  ```
- **Location:** workflows/inbound-handler.json:224-248
- **Runs in parallel** with WhatsApp preparation

### 11. Send Telegram Notification
- **Type:** HTTP Request
- **Method:** POST
- **URL:** `$env.TELEGRAM_BOT_API_URL`
- **Purpose:** Notifies installer about missed call via Telegram
- **Body:**
  ```json
  {
    "chat_id": "$env.INSTALLER_TELEGRAM_CHAT_ID",
    "text": "<message>",
    "parse_mode": "HTML"
  }
  ```
- **Location:** workflows/inbound-handler.json:249-268

### 12. If Telegram Failed
- **Type:** IF Node
- **Purpose:** Checks if Telegram send failed
- **Condition:** `ok` equals `false`
- **Branches:**
  - **True:** Log error
  - **False:** End flow
- **Location:** workflows/inbound-handler.json:269-294

### 13. Log Telegram Error
- **Type:** Code Node (JavaScript)
- **Purpose:** Logs Telegram API errors to console
- **Output:** `telegramError`, `logged: true`
- **Location:** workflows/inbound-handler.json:295-305

## Parallel Execution

After **Parse CRM Data**, the workflow splits into three parallel branches:
1. **TwiML Voice Response** - Immediate caller response (critical path)
2. **WhatsApp Branch** - Send message to caller with SMS fallback
3. **Telegram Branch** - Notify installer with error logging

This ensures the caller always receives an immediate voice response, regardless of notification success/failure.

## Environment Variables Required

Add these to your `.env` file:

```bash
# Waha WhatsApp API
WAHA_API_URL=https://waha.yourdomain.com
WAHA_API_TOKEN=your_waha_token

# Telegram Bot
TELEGRAM_BOT_API_URL=https://api.telegram.org/bot<your-bot-token>/sendMessage
INSTALLER_TELEGRAM_CHAT_ID=123456789

# Twilio (for SMS fallback)
TWILIO_PHONE_NUMBER=+1234567890
```

## Google Sheets CRM Configuration

### Required Sheet
- **Sheet Name:** `CRM`
- **Required Columns:** `phone`, `name`, `status`, `address`, `projectType`

### Example CRM Data

| phone | name | status | address | projectType |
|-------|------|--------|---------|-------------|
| +491701234567 | Max Mustermann | Active | Musterstraße 1, Berlin | New Installation |
| +491639876543 | Erika Muster | Lead | Hauptstraße 5, München | Replacement |

## Testing the Workflow

### 1. Test Webhook Endpoint
```bash
curl -X POST https://n8n.yourdomain.com/webhook/incoming-voice \
  -H "Content-Type: application/json" \
  -d '{
    "From": "01701234567",
    "CallSid": "CA1234567890",
    "To": "+49123456789",
    "FromCity": "Berlin",
    "FromState": "Berlin"
  }'
```

### 2. Test Phone Normalization
Send various formats to verify E.164 conversion:
- `01701234567`
- `+491701234567`
- `00491701234567`

### 3. Test CRM Lookup
Add a test number to CRM sheet and verify customer data is retrieved.

### 4. Test TwiML Response
Verify the response contains valid TwiML XML with German voice message.

### 5. Test WhatsApp Send
Verify WhatsApp message is sent to the caller with correct template.

### 6. Test SMS Fallback
Temporarily disable Waha API to trigger SMS fallback.

### 7. Test Telegram Notification
Verify installer receives missed call notification with customer details.

## Error Handling

### WhatsApp Failure
- Condition: HTTP response contains `error` or `status` with "error"
- Action: Sends SMS via Twilio to same number
- Logs: n8n execution history

### Telegram Failure
- Condition: Telegram API returns `ok: false`
- Action: Logs error to console
- Does not block voice response

### TwiML Response
- Always succeeds (returns static XML)
- Never blocked by notification failures
- Critical path for caller experience

## Performance Considerations

1. **TwiML Response Priority:** Voice response runs in parallel to notifications, ensuring immediate caller feedback
2. **Non-blocking:** WhatsApp and Telegram failures don't delay voice response
3. **CRM Lookup:** Only executes once, results used by both WhatsApp and Telegram branches
4. **Phone Normalization:** Efficient regex-based conversion, minimal overhead

## Security Notes

1. **Environment Variables:** Sensitive tokens stored in `.env`, never in workflow JSON
2. **Credentials:** External credentials configured in n8n UI, not in JSON
3. **Input Validation:** Phone number normalization handles various formats safely
4. **Rate Limiting:** Consider adding rate limits to prevent abuse

## Troubleshooting

### No Voice Response
- Check TwiML XML syntax
- Verify webhook path matches Twilio configuration
- Check n8n webhook trigger is active

### WhatsApp Not Sending
- Verify WAHA_API_URL and WAHA_API_TOKEN
- Check Waha service status
- Verify phone format is correct
- Check n8n HTTP Request node logs

### Telegram Not Sending
- Verify INSTALLER_TELEGRAM_CHAT_ID is correct
- Check bot has message permissions
- Verify TELEGRAM_BOT_API_URL format
- Check Telegram API status

### CRM Not Finding Customer
- Verify CRM sheet exists
- Check phone column format
- Ensure phone number normalization matches CRM data
- Test lookup manually in Google Sheets

### SMS Fallback Not Triggering
- Verify Twilio credentials are configured
- Check TWILIO_PHONE_NUMBER is correct
- Verify WhatsApp failure detection logic
- Check Twilio account balance
