# Vorzimmerdrache

**Automatisierte Anrufbearbeitung für Handwerker**

## Quick Start

```bash
git clone <repo> && cd vorzimmerdrache
cp .env.example .env  # Fill in your keys
./scripts/setup.sh    # Deploy everything
```

Then configure Twilio webhooks:
- Voice: `https://<YOUR-DOMAIN>/webhook/incoming-call`
- SMS: `https://<YOUR-DOMAIN>/webhook/sms-response`

## What it does

- **Catches calls when you're on the roof** - Instant voice response so customers aren't left hanging
- **Sends WhatsApp after SMS opt-in** - DSGVO-compliant flow: SMS first, WhatsApp only after "JA" reply
- **Qualifies leads** - Collects PLZ, kWh usage, and roof photo before you call back
- **Notifies you via Telegram** - Instant alerts for every call and qualified lead

## Data Flow

```
Call → Twilio → n8n → Voice Message
              ↓
        SMS: "Want WhatsApp info? Reply JA"
              ↓
        JA → PLZ → kWh → Photo → WhatsApp Link
```

## Tech Stack

n8n + Twilio + Google Sheets + Telegram on 1GB VPS (~€6/month)

## Setup

- **Full setup:** See [docs/DEPLOY.md](docs/DEPLOY.md)
- **Architecture:** See [ARCHITECTURE.md](ARCHITECTURE.md)
- **Pain points solved:** See [docs/PAIN_POINTS.md](docs/PAIN_POINTS.md)
- **Selling points:** See [docs/UNIQUE_SELLING_POINTS.md](docs/UNIQUE_SELLING_POINTS.md)

## Key Features

- **Loop prevention** - Blacklist + 5-minute cooldown prevents duplicate SMS costs
- **Race condition protection** - MessageSid deduplication handles simultaneous webhooks
- **Compact state machine** - Valid state transitions prevent data corruption
- **DSGVO-compliant opt-in** - SMS bridge ensures legal WhatsApp communication

## Project Status

✅ **Production-ready**
- Docker Compose with Traefik (SSL)
- SQLite database (no external DB needed)
- Automated backups
- Healthchecks and log rotation

📋 **Requires manual setup** (~30 min)
1. Configure API credentials in `.env`
2. Import workflows into n8n
3. Set up Twilio webhooks
4. End-to-end test

## Support

- n8n Community: https://community.n8n.io
- Twilio Support: https://support.twilio.com
