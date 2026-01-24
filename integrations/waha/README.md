# WhatsApp Integration Layer (Waha + SMS Fallback)

## Architecture

```
n8n → MessageService → Waha (WhatsApp) → Customer
                   ↓ (fallback)
                Twilio SMS → Customer
```

**Components:**
- **Waha**: WhatsApp HTTP API service (Docker container)
- **MessageService**: Node.js helper for n8n HTTP requests
- **Rate Limiter**: Max 5 messages/hour per session
- **SMS Fallback**: Automatic fallback to Twilio if Waha is down
- **Health Check**: Endpoint `/health` for service monitoring
- **QR Generation**: Dynamic QR code for device pairing

## Setup Steps

### 1. Install Dependencies
```bash
cd integrations/waha
npm init -y
npm install axios
```

### 2. Start Waha Service
```bash
docker-compose up -d
```

### 3. Pair WhatsApp Device
```bash
# Get QR code (returns base64 image)
curl http://localhost:3000/api/sessions/default/qr
```

Scan QR code with WhatsApp → Linked Devices → Link a Device

### 4. Verify Session Status
```bash
curl http://localhost:3000/api/sessions
# Look for "status": "WORKING"
```

### 5. Configure Environment
Create `.env` file:
```env
WAHA_BASE_URL=http://localhost:3000
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_PHONE_NUMBER=+1234567890
```

### 6. Integrate with n8n

**HTTP Request Node Example:**
- Method: POST
- URL: `http://your-service:port/send-message`
- Body (JSON):
```json
{
  "phone": "49151123456789",
  "templateKey": "appointment_confirmation",
  "variables": {
    "date": "2025-01-30",
    "time": "10:00",
    "address": "Musterstraße 1, 10115 Berlin"
  }
}
```

### 7. Health Monitoring
```bash
curl http://localhost:3000/health
# Returns: {"status":"ok"}
```

## Message Templates (German)

Available templates in `templates.json`:
- `lead_acknowledgment`: Initial lead acknowledgment
- `appointment_confirmation`: Appointment confirmation
- `quote_sent`: Quote sent notification
- `material_ordered`: Material ordered update
- `installation_scheduled`: Installation scheduled

## Rate Limiting

- **Max**: 5 messages per hour
- **Window**: 1 hour (3600000ms)
- **Behavior**: Throws error if exceeded, shows wait time

## Fallback Strategy

1. Check Waha health endpoint
2. Attempt WhatsApp send via Waha
3. If failure → Send SMS via Twilio
4. Log method used (`method: 'whatsapp' | 'sms'`)

## API Reference

### MessageService Methods

**`sendMessage(phone, templateKey, variables, mediaUrl)`**
Send message with template substitution

**`healthCheck()`**
Check if Waha service is running

**`getQRCode()`**
Get QR code for device pairing

**`getSessionStatus()`**
Get current WhatsApp session status

**`sendWhatsApp(phone, message, mediaUrl)`**
Send direct WhatsApp message

**`sendSMSFallback(phone, message)`**
Send SMS via Twilio

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `WAHA_BASE_URL` | Waha API URL | No (default: http://localhost:3000) |
| `TWILIO_ACCOUNT_SID` | Twilio account SID | Yes (for SMS fallback) |
| `TWILIO_AUTH_TOKEN` | Twilio auth token | Yes (for SMS fallback) |
| `TWILIO_PHONE_NUMBER` | Twilio phone number | Yes (for SMS fallback) |

## Troubleshooting

**QR code not generating:**
- Check if container is running: `docker ps`
- View logs: `docker-compose logs waha`

**Messages not sending:**
- Verify session status is "WORKING"
- Check rate limit (max 5/hour)
- Review health check endpoint

**SMS fallback not working:**
- Verify Twilio credentials in `.env`
- Check account balance
- Ensure phone number format: `+49151123456789`

**Session disconnects:**
- Waha auto-restarts sessions (configured)
- Re-scan QR code if needed
- Check session logs: `docker-compose logs waha`
