# Twilio Voice Call Bridging System

## Webhook Flow Explanation

### 1. Initial Call Flow

```
[New Lead] → n8n Webhook → /initiate-call → Twilio API
                                    ↓
                           [Installer Called]
                                    ↓
                    installer-welcome TwiML Template
                (German TTS: "Guten Tag. Neue Anfrage...")
                                    ↓
                <Gather numDigits="1" timeout="10">
```

### 2. DTMF Input Processing

```
[Installer Presses Key] → /voice/gather POST
                                    ↓
                    ┌───────────────────────┐
                    │   Digits == 1?         │
                    └───────────────────────┘
                           ↓           ↓
                         Yes          No
                           ↓           ↓
                dtmf-response-1    dtmf-response-2
                (Connect to      (Send SMS, hangup)
                customer)
                           ↓
                   /voice/call-complete
```

### 3. Call Status Tracking

```
[Call to Customer] → DialCallStatus → /voice/call-complete
                                        ↓
                         ┌────────────────────────┐
                         │ DialCallStatus == ?    │
                         └────────────────────────┘
                    ↓           ↓           ↓
                 completed  no-answer  busy/cancelled
                    ↓           ↓           ↓
              call-completed  voicemail-fallback  call-failed
```

### 4. Google Sheets Update

All events trigger sheet append:
- Timestamp | CallSID | CallerID | Status | Outcome

### 5. SMS Fallback Triggers

- Timeout (no installer response) → SMS to installer
- Installer presses '2' → SMS with lead details
- Customer no-answer → SMS notification
- Voicemail left → SMS with recording URL

### 6. Voicemail Flow

```
[Customer No Answer] → <Record> → voicemail-complete
                                    ↓
                           Transcribe (if enabled)
                                    ↓
                           SMS to installer
                           SMS to customer (if enabled)
```

### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/voice/welcome` | POST | Initial installer call |
| `/voice/gather` | POST | Process DTMF input |
| `/voice/timeout` | POST | No response handler |
| `/voice/call-complete` | POST | Call ended |
| `/voice/voicemail-complete` | POST | Recording done |
| `/callback/status` | POST | Twilio status callback |
| `/initiate-call` | POST | Start new call chain |
| `/health` | GET | Health check |

### Status Outcomes

| Status | Meaning |
|--------|---------|
| `answered` | Installer responded |
| `installer_connected` | Connected to customer |
| `installer_deferred` | Pressed '2', will call back |
| `no-answer` | Customer didn't pick up |
| `voicemail` | Left voicemail |
| `call_failed` | Technical error |
| `timeout` | No DTMF input |

### Configuration

1. Copy `config.example.json` to `config.json`
2. Add Twilio credentials (accountSid, authToken)
3. Configure Google Sheets API credentials
4. Set webhook baseUrl (must be publicly accessible)
5. Configure phone numbers (callerId, smsNumber)

### Deployment

```bash
npm install @twilio/rest express googleapis
node integrations/twilio/call-handler.js
```

Use ngrok for local testing:
```bash
ngrok http 3000
```

Then update `config.json` baseUrl to ngrok URL.
