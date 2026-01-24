# Telegram Bot Integration

Installer notification system for missed calls and lead alerts.

## Setup

1. Create a Telegram bot via @BotFather
2. Copy the bot token
3. Create config file from template:
   ```bash
   cp bot-config.example.json bot-config.json
   ```
4. Edit `bot-config.json` with your bot token

## Configuration

```json
{
  "botToken": "YOUR_BOT_TOKEN",
  "rateLimit": 20,
  "webhook": {
    "url": "https://your-domain.com/telegram/webhook",
    "path": "/telegram/webhook",
    "port": 3001
  },
  "installersPath": "./integrations/telegram/installers.json",
  "notifications": {
    "missedCall": {
      "enabled": true,
      "template": "📞 Verpasster Anruf von {phone}\nName: {name}\nZeit: {timestamp}\n\nHabe ihm eine WhatsApp geschickt."
    },
    "voicemail": {
      "enabled": true,
      "template": "🎤 Neue Voicemail von {phone}\nName: {name}\nZeit: {timestamp}\nDauer: {duration}s"
    },
    "roofMode": {
      "enabled": true,
      "autoReply": true,
      "message": "Installer ist auf dem Dach - automatische WhatsApp wurde versendet"
    }
  },
  "n8n": {
    "webhookUrl": "https://n8n.yourdomain.com/webhook/incoming-voice",
    "authentication": {
      "type": "header",
      "headerName": "X-Telegram-Auth",
      "secret": "your-secret-token"
    }
  }
}
```

### Configuration Options

- `notifications.missedCall.enabled`: Enable/disable missed call notifications
- `notifications.missedCall.template`: Template for missed call messages
- `notifications.voicemail.enabled`: Enable/disable voicemail notifications
- `notifications.roofMode.enabled`: Enable roof mode notifications
- `notifications.roofMode.autoReply`: Enable auto-reply for roof mode
- `n8n.webhookUrl`: n8n webhook endpoint for incoming voice calls
- `n8n.authentication`: Authentication header for n8n webhooks

### Template Variables

Missed call template supports:
- `{phone}` - Caller's phone number
- `{name}` - Customer name from CRM
- `{timestamp}` - Call timestamp in German timezone
- `{address}` - Customer address (if available)

Voicemail template supports:
- `{phone}` - Caller's phone number
- `{name}` - Customer name from CRM
- `{timestamp}` - Call timestamp
- `{duration}` - Voicemail duration in seconds
- `{recordingUrl}` - Link to recording (if available)
- `{transcription}` - Voicemail transcription text (if available)

## Running

```bash
# With webhook (recommended for production)
node integrations/telegram/bot.js

# With polling (for development)
node integrations/telegram/bot.js
```

## Installer Registration

Each installer must register via Telegram:
```
/register <Installer Name>
```

## API Reference

### notifyMissedCall(callData)

Send missed call notification to all registered installers.

```javascript
const { notifyMissedCall } = require('./integrations/telegram/bot');

await notifyMissedCall({
  customerName: 'Max Mustermann',
  address: 'Musterstraße 1, 12345 Berlin',
  phoneNumber: '+491234567890',
  leadType: 'Solaranlage'
});
```

### notifyLeadAlert(leadData)

Send high priority lead alert.

```javascript
const { notifyLeadAlert } = require('./integrations/telegram/bot');

await notifyLeadAlert({
  customerName: 'Erika Musterfrau',
  address: 'Beispielweg 42, 10115 Berlin',
  phoneNumber: '+491234567891',
  leadType: 'Speicher',
  priority: 'high',
  notes: 'Kunde möchte bis Montag Entscheidung'
});
```

### sendDailySummary(summaryData)

Send daily statistics summary.

```javascript
const { sendDailySummary } = require('./integrations/telegram/bot');

await sendDailySummary({
  date: '2026-01-24',
  totalLeads: 45,
  missedCalls: 12,
  connectedCalls: 33,
  topInstallers: [
    { name: 'Max Mustermann', calls: 15 },
    { name: 'Erika Musterfrau', calls: 12 }
  ]
});
```

## Bot Features

| Feature | Description |
|---------|-------------|
| Missed call notifications | 📞 Notify installers of missed calls |
| Lead alerts | 🔴 High priority lead alerts with priority levels |
| Daily summary | 📊 Optional daily statistics summary |
| Rate limiting | ⏱️ 20 messages/minute with queue system |
| Installer registration | 👥 Multiple installers with `/register` |
| Command handlers | `/status`, `/today`, `/help` |
| MarkdownV2 formatting | ✨ Rich text with bold, code blocks |
| German timezone | 🇩🇪 Timestamps in Europe/Berlin |

## Rate Limiting

Built-in queue system respects Telegram's 20 messages/minute limit. Messages are automatically queued and sent when capacity is available.
