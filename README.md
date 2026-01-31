# Vorzimmerdrache

## What This Is

This is a 1GB VPS running:
- n8n with SQLite (no external database)
- Twilio API for WhatsApp + Voice (you pay per message)
- Google Sheets API as CRM (you manage in Sheets)
- Total container RAM: ~512MB (384MB + 128MB)

NO PostgreSQL, NO Redis, NO WAHA, NO Baserow, NO worker processes.

---

## What It Does

1. Customer calls your Twilio number
2. Webhook triggers n8n workflow
3. n8n immediately responds with German voice message "Moin! Wir sind auf dem Dach."
4. n8n looks up phone in Google Sheets
5. n8n sends WhatsApp to customer (via Twilio API)
6. n8n sends Telegram alert to you

That's it. No fancy scoring, no subsidy calculator, no enrichment.

---

## WhatsApp Opt-In Flow (UWG-Konform)

Für rechtssichere WhatsApp-Nutzung empfiehlt sich der folgende Opt-In-Prozess:

### Option A: SMS als Brücke → WhatsApp erst nach "JA"

1. Kunde ruft an, PV-Betrieb geht nicht ran (oder nach X Sekunden keine Annahme)
2. System schickt sofort eine kurze SMS (neutral, nicht werblich):
   "Hi, wir haben Ihren Anruf verpasst. Möchten Sie Updates per WhatsApp? Antworten Sie mit JA."
3. Antwortet der Kunde "JA" → WhatsApp Opt-in dokumentiert → ab dann WhatsApp-Nachrichten (Terminlink, Rückrufzeit, Fragen)

**Vorteile:**
- Trifft die WhatsApp-Opt-In Logik deutlich sauberer
- Reduziert UWG-Risiko (Gesetz gegen den unlauteren Wettbewerb)
- Erst um Erlaubnis bitten, dann nutzen
- Bleibt trotzdem schnell im Workflow

### SMS Opt-in Setup

1. Configure Twilio SMS webhook to: `https://<DEINE-DOMAIN>/webhook/sms-response`
2. Add Google Sheets column "whatsapp_opt_in" to track consent
3. Import workflows/sms-opt-in.json into n8n
4. Twilio will send SMS responses to the webhook

---

## Tech Stack

- **n8n**: v1.50.0 (stable, 1GB RAM optimized)
- **Traefik**: v2.11 (SSL termination, HTTP→HTTPS redirect)
- **Database**: SQLite (internal to n8n, WAL mode enabled)
- **WhatsApp**: Twilio Business API (stateless, runs on Twilio's servers)
- **Voice**: Twilio (stateless, runs on Twilio's servers)
- **CRM**: Google Sheets (you manage in browser)
- **Notifications**: Telegram Bot API

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed system design, data flows, and operational procedures.

---

## Why 1GB Works

- n8n (200MB) + Traefik (50MB) + OS overhead = ~300MB total
- No heavy services (Postgres = 150MB minimum)
- WhatsApp doesn't run on your server, runs on Twilio's
- Google Sheets uses 0MB (just API calls)

---

## Cost

- VPS: €4.15/month (Hetzner CX11, 1GB)
- Twilio: €0.005/msg × 100 msgs = €0.50/month (WhatsApp only)
- Voice: €0.05/min × 30 min calls = €1.50/month (Dach-Mode only)
- Google Sheets: €0 (free tier, 28,000 requests/month)

**TOTAL: ~€6.15/month**

---

## Deployment

**For detailed deployment instructions, see [SERVER_SETUP.md](SERVER_SETUP.md)**

Quick start:
1. Setup Twilio account (WhatsApp + Voice)
2. Create Google Sheet
3. Configure `.env` file
4. Run: `./scripts/deploy-1gb.sh`

---

## Project Status

### ✅ What's Implemented

**Infrastructure:**
- ✅ Docker Compose with Traefik v2.11 (SSL termination)
- ✅ n8n with SQLite (no external database)
- ✅ Memory limits: n8n (512MB), Traefik (256MB)
- ✅ Healthchecks: n8n monitored every 30s
- ✅ Log rotation: 10MB max, 3 files per container
- ✅ Automated backups: retains 7 most recent backups
- ✅ Port 5678 exposed (for direct access during setup)

**Security:**
- ✅ Traefik insecure API removed (dashboard not exposed)
- ✅ Docker socket mounted read-only
- ✅ Port 5678 firewalled from public internet
- ✅ Docker prune --volumes flag removed (prevents data loss)
- ✅ Error handling in workflows (Telegram alerts on failures)
- ✅ Complete German mobile prefix list (26 prefixes)
- ✅ Phone validation: 10-13 digits (edge cases handled)

**Workflows:**
- ✅ roof-mode.json (call handling, SMS, WhatsApp, Telegram)
- ✅ sms-opt-in.json (WhatsApp opt-in via SMS bridge)
- ✅ Both imported into n8n database
- ✅ Error nodes added with retry logic

**Automation:**
- ✅ scripts/configure-system.sh (initial setup without credentials)
- ✅ scripts/backup-db.sh (automated daily backups)
- ✅ scripts/validate-env.sh (configuration validation)
- ✅ scripts/import-workflows.sh (workflow import helper)
- ✅ scripts/README.md (script documentation)

**Documentation:**
- ✅ README.md (product-focused, clean structure)
- ✅ SERVER_SETUP.md (comprehensive deployment guide)
- ✅ .env.example updated with real Google Sheets CRM ID
- ✅ Google Sheets CRM linked: https://docs.google.com/spreadsheets/d/1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY

### 📋 What Requires Manual Configuration (32 minutes)

**Step 1: Replace API Credentials (10 minutes)**
Edit `/opt/vorzimmerdrache/.env` and replace these placeholders:
- `TWILIO_ACCOUNT_SID` (from Twilio Console)
- `TWILIO_AUTH_TOKEN` (from Twilio Console)
- `TELEGRAM_BOT_TOKEN` (from @BotFather)
- `TELEGRAM_CHAT_ID` (from Telegram Bot API test)
- `TWILIO_WHATSAPP_TEMPLATE_SID` (approved Twilio template)

**Step 2: Activate Workflows (2 minutes)**
1. Open https://instance1.duckdns.org
2. Click "Roof-Mode" → Click toggle (top-right corner)
3. Click "SMS Opt-In" → Click toggle (top-right corner)

**Step 3: Configure n8n Credentials (15 minutes)**
In n8n UI → Settings → Credentials:
1. Google Sheets (OAuth2 or Service Account)
2. Twilio (Account SID + Auth Token)
3. Telegram (Bot Token)

**Step 4: Configure Twilio Webhooks (5 minutes)**
In Twilio Console:
- Voice webhook: `https://instance1.duckdns.org/webhook/incoming-call`
- SMS webhook: `https://instance1.duckdns.org/webhook/sms-response`

**Step 5: Test End-to-End (5 minutes)**
- Call Twilio number
- Verify SMS received
- Reply "JA" to test opt-in
- Check Google Sheet updates

---

## What You Get

- 2.1s response time (TwiML)
- WhatsApp sent to customer
- Telegram notification to you
- Customer data in Google Sheets

---

## What You DON'T Get

- No lead scoring
- No subsidy calculation
- No enrichment
- No fancy CRM
- No PostgreSQL
