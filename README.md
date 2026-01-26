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

## Setup

1. Setup Twilio account (WhatsApp + Voice)
2. Load €20 credit
3. Create Google Sheet
4. Copy keys to .env
5. Run: `./scripts/deploy-1gb.sh`

---

### Google Sheets Setup with OAuth2

**Step 1: Enable Google Sheets API**
1. Go to: https://console.cloud.google.com/apis/library
2. Search: "Google Sheets API"
3. Click "Enable"

**Step 2: Create OAuth2 Credentials**
1. Go to: https://console.cloud.google.com/apis/credentials
2. Create credentials → OAuth client ID
3. Application type: Desktop app
4. Name: "Vorzimmerdrache-n8n"
5. Scopes: https://www.googleapis.com/auth/spreadsheets.readonly

**Step 3: Get Access Tokens**
1. Use this URL to get OAuth tokens:
   https://developers.google.com/oauthplayground/
2. Authorize with your Google account
3. Copy the access token and refresh token

**Step 4: Share the Spreadsheet**
1. Open your spreadsheet
2. Click "Share"
3. Use: https://docs.google.com/spreadsheets/d/1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY/edit?usp=sharing
4. Add email from OAuth credentials as "Editor"
5. Click "Send"

**Step 5: Configure n8n**
1. Add credentials to .env
2. Import workflows/roof-mode.json
3. Update Google Sheets node with OAuth2 credentials

---

### Google Sheets Setup with Service Account (Alternative)

**Service accounts don't expire - better for headless servers**

**Step 1: Enable Google Sheets API**
1. Go to: https://console.cloud.google.com/apis/library
2. Search: "Google Sheets API"
3. Click "Enable"

**Step 2: Create Service Account**
1. Go to: https://console.cloud.google.com/iam-admin/serviceaccounts
2. Click "Create Service Account"
3. Name: "Vorzimmerdrache-n8n"
4. Click "Create and Continue"
5. Skip roles (optional)
6. Click "Done"

**Step 3: Generate JSON Key**
1. Click on your new service account
2. Go to "Keys" tab
3. Click "Add Key" → "Create new key"
4. Key type: JSON
5. Download the JSON file
6. Copy contents to GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON in .env

**Step 4: Share the Spreadsheet**
1. Open your spreadsheet
2. Click "Share"
3. Use: https://docs.google.com/spreadsheets/d/1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY/edit?usp=sharing
4. Add service account email (from JSON file) as "Editor"
5. Click "Send"

**Step 5: Configure n8n**
1. Add credentials to .env
2. Import workflows/roof-mode.json
3. Update Google Sheets node with Service Account credentials

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
