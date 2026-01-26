# Vorzimmerdrache

## What This Is

This is a 1GB VPS running:
- n8n with SQLite (no external database)
- Twilio API for WhatsApp + Voice (you pay per message)
- Google Sheets API as CRM (you manage in Sheets)
- Total container RAM: ~300MB

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

- Docker: Traefik + n8n only
- Database: SQLite internal to n8n
- WhatsApp: Twilio Business API (stateless, runs on Twilio's servers)
- Voice: Twilio (stateless, runs on Twilio's servers)
- CRM: Google Sheets (you manage in browser)

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

**For deployment instructions, see [SERVER_SETUP.md](SERVER_SETUP.md)**

Quick start:
1. Setup Twilio account (WhatsApp + Voice)
2. Create Google Sheet
3. Configure `.env` file
4. Run: `./scripts/deploy-1gb.sh`

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
