# Opt-Out Handler - German GDPR Compliance

Instant opt-out handling for WhatsApp and SMS channels with German keyword support.

## Overview

This system provides:
- Instant opt-out via German keywords (STOP, ABMELDEN, etc.)
- Compliance with German DSGVO/GDPR requirements
- Automatic confirmation messages
- Database updates to prevent future messages
- Audit trail for compliance records

## Files

- `workflows/opt-out-handler.json` - n8n workflow for processing opt-out requests
- `config/opt-out-messages.json` - Confirmation messages and keyword definitions
- `migrations/003_create_opt_out_events.sql` - Database schema for audit trail
- `integrations/waha/message-service.js` - Guard function to prevent messaging opted-out leads

## Supported Keywords

German variations (case-insensitive):
- `stop`, `stopp`, `halt`
- `abmelden`, `abbestellen`
- `löschen`, `delete`, `remove`
- `kein interesse`, `no thanks`
- `nicht mehr`, `nicht kontaktieren`

## Webhook Endpoints

- `/webhook/incoming-whatsapp` - Receives messages from Waha
- `/webhook/incoming-sms` - Receives messages from Twilio

## Database Schema

### leads table (existing)
```sql
opted_out BOOLEAN DEFAULT FALSE,
opted_out_at TIMESTAMPTZ
```

### opt_out_events table (new)
```sql
lead_id UUID REFERENCES leads(id),
channel VARCHAR(20),
keyword_used VARCHAR(50),
timestamp TIMESTAMPTZ
```

## Usage

### 1. Run Migration
```bash
psql -U postgres -d vorzimmerdrache -f migrations/003_create_opt_out_events.sql
```

### 2. Import n8n Workflow
- Import `workflows/opt-out-handler.json` into n8n
- Configure credentials: postgres, twilio, httpHeaderAuth

### 3. Configure MessageService
```javascript
const messageService = new MessageService({
  pgPool: new Pool({ /* postgres config */ }),
  // ... other config
});
```

### 4. Test
```bash
node integrations/waha/opt-out-test.js status
node integrations/waha/opt-out-test.js opt-out +4912345678
```

## Guard Function

The `checkOptOutStatus()` method is called automatically before:
- `sendWhatsApp()`
- `sendSMSFallback()`
- `sendMessage()`

If `opted_out = TRUE`, an error is thrown preventing message delivery.

## Compliance Notes

- All opt-out events are logged with timestamp and keyword used
- Messages to opted-out leads are blocked at the service level
- Confirmation is sent immediately upon opt-out detection
- Audit trail supports GDPR accountability requirements
