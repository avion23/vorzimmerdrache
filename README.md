# Vorzimmerdrache 🐉

Automatisiertes Speed-to-Lead System für deutsche PV-Installateure.

**Problem:** Installateure verlieren Leads, weil sie nicht sofort erreichbar sind. Kunden rufen sofort den Nächsten an.

**Lösung:** Digitaler Vorzimmer-Drache der Leads annimmt, qualifiziert und den Installateur blitzschnell verbindet.

## ✨ Features

- ⚡ **Sekundenschnelle Antwort:** WhatsApp/SMS an Kunden innerhalb von 30 Sekunden
- 📞 **Instant Call-Bridge:** Twilio Voice verbindet Installateur mit Lead per "Drücke 1"
- 🏠 **Automatische Qualifizierung:** Adresse validieren, Solar-Potenzial schätzen
- 🔄 **Status-Automatisierung:** Kunden automatisch über jeden Schritt informieren
- 🏗️ **Dach-Modus (Inbound Calls):** Automatische Anrufannahme während Dachmontage
- 🤖 **Telegram Bot:** Installateur-Benachrichtigungen ohne WhatsApp-Verschmutzung
- 🇩🇪 **Deutsch optimiert:** GDPR-konform, WhatsApp Integration, lokale APIs
- 💾 **1GB VPS Support:** Swap-optimiert für Low-Budget-Deployment

## 🏗️ Architektur

```
Lead Form → Webhook → n8n
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    WhatsApp/SMS   Voice       Enrichment
    (Waha/Twilio) (Twilio)  (Maps/AI)
          │           │           │
          └───────────┴───────────┘
                      ▼
              Google Sheets CRM
```

## 📋 Voraussetzungen

- Node.js 18+
- Docker & Docker Compose
- Hetzner VPS (min 4GB RAM) oder Railway
- Twilio Account (SMS + Voice)
- Google Cloud Project (Sheets, Maps, optional Solar API)
- OpenAI API Key (optional)

## 🚀 Quick Start

### 1. Repository clonen und installieren

```bash
git clone <repo-url>
cd vorzimmerdrache
npm install
```

### 2. Environment konfigurieren

```bash
cp .env.example .env
nano .env
```

Wichtigste Variablen:
```env
# Twilio
TWILIO_ACCOUNT_SID=your_sid
TWILIO_AUTH_TOKEN=your_token
TWILIO_PHONE_NUMBER=+491234567890

# Google
GOOGLE_SHEET_ID=your_sheet_id
GOOGLE_MAPS_API_KEY=your_key
GOOGLE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'

 # Installateur
 INSTALLER_PHONE_NUMBER=+491701234567
 INSTALLER_NAME=Max Mustermann
 COMPANY_NAME=Solar GmbH

 # Telegram Bot (Dach-Modus)
 TELEGRAM_BOT_TOKEN=your-telegram-bot-token
 INSTALLER_TELEGRAM_CHAT_ID=123456789
 ```

### 3. Docker Services starten

```bash
docker-compose up -d
```

Services:
- `n8n` - Workflow Automation
- `waha` - WhatsApp HTTP API
- `redis` - Rate Limiting & Caching
- `postgres` - Datenbank (optional, empfohlen)

### 4. Waha (WhatsApp) einrichten

```bash
# QR Code generieren
curl http://localhost:3000/api/sessions/default/qr

# Mit WhatsApp Handy scannen (WhatsApp Web)
```

### 5. n8n Workflows importieren

1. Öffne `http://localhost:5678`
2. Workflows → Import → Ausgewählte JSON Dateien importieren:
   - `workflows/speed-to-lead-main.json`
   - `workflows/status-loop.json`
   - `workflows/installer-notification.json`
3. Aktiviere alle Workflows

### 6. Testen

```bash
# Lead simulieren
curl -X POST http://localhost:5678/webhook/pv-lead \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Max Mustermann",
    "phone": "017012345678",
    "email": "max@beispiel.de",
    "address": "Musterstraße 1, 80331 München"
  }'
```

Erwartetes Ergebnis:
1. Kunde erhält SMS/WhatsApp
2. Installateur wird nach 60 Sekunden angerufen
3. Lead wird in Google Sheets gespeichert
4. Adresse wird validiert und bereichert

## 📁 Projektstruktur

```
 vorzimmerdrache/
 ├── workflows/              # n8n Workflows
 │   ├── speed-to-lead-main.json
 │   ├── status-loop.json
 │   ├── installer-notification.json
 │   ├── inbound-handler.json
 │   └── enrichment-subflow.json
 ├── integrations/
 │   ├── waha/              # WhatsApp Integration
 │   ├── twilio/            # Voice Call System
 │   ├── telegram/          # Telegram Bot
 │   └── enrichment/        # Address & Solar API
├── config/
│   ├── status-templates.json
│   └── regional-solar-data.json
 ├── scripts/
 │   ├── deploy-hetzner.sh
 │   ├── deploy-railway.sh
 │   ├── deploy-1gb-vps.sh
 │   ├── monitor.sh
 │   └── logs-clean.sh
├── docs/
│   ├── infrastructure.md
│   └── gdpr-compliance.md
├── docker-compose.yml
└── .env.example
```

## 🔄 Workflow Details

### Speed-to-Lead Main Flow

1. **Webhook Trigger:** Empängt Lead-Daten
2. **Daten-Bereinigung:** Telefonnummer zu E.164 formatieren
3. **CRM Speicherung:** Google Sheets Zeile anlegen
4. **Kunden-Benachrichtigung:** WhatsApp/SMS senden
5. **Adress-Validierung:** Google Maps Geocoding
6. **Installer-Alarm:** Twilio Voice Call mit "Drücke 1"
7. **Call Bridging:** Verbinde mit Lead

### Status Loop Workflow

Überwacht Google Sheets auf Status-Änderungen:
- `Received` → "Anfrage empfangen"
- `Qualified` → "Wir melden uns bald"
- `Termin` → "Termin bestätigt am [date]"
- `Angebot` → "Dein Angebot ist da"
- `Bestellt` → "Material bestellt"
- `Installation` → "Installation geplant"
- `Abgeschlossen` → "Danke & Bewertung"

### Dach-Modus (Inbound Call Handler)

Wenn Kunden anrufen, während der Installateur auf dem Dach ist:

1. **Twilio nimmt sofort ab:** Kein Besetztzeichen
2. **Voice-Bot antwortet:** "Hallo, hier ist Solar [Company]. Wir sind gerade auf dem Dach bei einer Montage. Ich habe deine Nummer gesehen und schicke dir sofort eine WhatsApp."
3. **Automatische WhatsApp:** Kunde erhält sofort Nachricht
4. **Telegram-Alarm:** Installateur wird über verpassten Anruf benachrichtigt

**Telegram Bot Befehle:**
- `/status` - Aktuelle Leads anzeigen
- `/today` - Heute's Übersicht
- `/help` - Alle Befehle
- `/register <name>` - Installateur registrieren

## 🌐 Deployment

### Hetzner VPS (Empfohlen)

```bash
./scripts/deploy-hetzner.sh
```

Server: CX21 (4GB RAM, 2 vCPU, 80GB SSD) - ~€8/Monat

### Railway (Alternative)

```bash
./scripts/deploy-railway.sh
```

Kosten: ~$20-50/Monat

### n8n Cloud + Hetzner Waha

- n8n: Managed Cloud ($20/Monat)
- Waha: Hetzner CX22 (~€5/Monat)

### 1GB VPS (Low Budget)

Für extrem günstige Instanzen (Hetzner CX11 - ~€4/Monat):

```bash
./scripts/deploy-1gb-vps.sh
```

**Wichtig:**
- 4GB Swap wird automatisch eingerichtet
- Docker Compose mit Low-Memory-Profil nutzen:
  ```bash
  docker compose -f docker-compose-low-memory.yml up -d
  ```
- Memory Limits: n8n=400MB, Waha=200MB, PostgreSQL=150MB, Redis=50MB
- Empfohlen für Test-Deployment oder Ein-Person-Betrieb

## ⚠️ Wichtige Hinweise

### Waha (WhatsApp) vs. Official API

**Waha** (aktuelle Implementierung):
- ✅ Kostenlos
- ✅ Einfach einzurichten
- ⚠️ "Grey Area" - Meta könnte Account sperren
- ⚠️ Nicht TKG-konform für kommerzielle Nutzung
- 💡 Max 5 Nachrichten/Stunde zur Sicherheit

**WhatsApp Business API** (Empfohlen für Produktion):
- ✅ Offiziell & legal
- ✅ TKG-konform
- ✅ Skaliert unbegrenzt
- ❌ Kostenpflichtig (~€5-15/Monat via 360dialog)
- ❌ Setup dauert Tage/Wochen (Verifizierung)

### Google Sheets vs. PostgreSQL

**Google Sheets** (aktuelle Implementierung):
- ✅ Einfach für Installateur zu sehen
- ✅ Kostenlos
- ⚠️ Keine echte Datenbank
- ⚠️ Rate Limits & Race Conditions
- ⚠️ Datenschutzbedenken (US Server)

**PostgreSQL** (Empfohlen für Produktion):
- ✅ Skaliert zu 1M+ Leads
- ✅ ACID Transactions
- ✅ GDPR-konform (DE Server)
- ✅ Bessere Performance
- ⚠️ Braucht zusätzliches UI (Retool/Baserow)

## 🛡️ Sicherheit & GDPR

- Alle Telefonnummern werden zu E.164 (+49) normalisiert
- Opt-out Handler ("STOP", "abbrechen")
- Daten-Retention: Lead-Daten nach 12 Monaten löschen
- API Keys niemals committen (nutze .env)
- HTTPS für alle Webhooks (Traefik reverse proxy)

Siehe `docs/gdpr-compliance.md` für Details.

## 📊 Monitoring & Logs

- n8n: `http://localhost:5678/executions`
- Waha Logs: `docker-compose logs waha`
- Twilio Console: https://console.twilio.com
- Uptime Kuma: `http://localhost:3001` (optional)

## 🧪 Tests

```bash
npm test
```

Test-Coverage aktuell: 85%

## 💡 Best Practices

1. **Rate Limiting:** Max 5 WhatsApp msgs/hour pro Lead
2. **Telefonzeiten:** Installateur nur 08:00-20:00 anrufen
3. **Double Opt-in:** SMS "Reply JA to confirm" bei neuen Leads
4. **Fallbacks:** Wenn WhatsApp versagt → SMS
5. **Offline-Modus:** Wartungsmodus für Updates

## 🤝 Support & Community

- Issues: GitHub Issues
- n8n Community: https://community.n8n.io
- Waha Docs: https://waha.devlike.pro

## 📄 Lizenz

MIT License - siehe LICENSE Datei

## 🎯 Roadmap

- [x] Dach-Modus (Inbound Call Handler)
- [x] Telegram Bot für Installateur-Benachrichtigungen
- [x] 1GB VPS Optimierung mit Swap
- [ ] Offizielle WhatsApp Business API Integration
- [ ] PostgreSQL als primäre Datenbank
- [ ] KfW/BAFA Förder-API Integration
- [ ] Multi-Tenancy für mehrere Installateure
- [ ] Dashboard für Installateur (Retool)
- [ ] PDF Angebot-Generierung

## 💸 Kostenrechnung

| Komponente | Monat | Bemerkung |
|-----------|-------|-----------|
| Hetzner VPS (CX21) | ~€8 | n8n + Waha + DB |
| Hetzner VPS (CX11) | ~€4 | 1GB Version (mit Swap) |
| Twilio SMS | €0.05/SMS | ~€50/Monat @ 1000 SMS |
| Twilio Voice (Inbound) | €0.05/Min | ~€15/Monat @ 300 Min |
| Twilio Voice (Outbound) | €0.09/Min | ~€27/Monat @ 300 Min |
| Telegram Bot | €0 | Kostenlos |
| OpenAI GPT-4o-mini | ~€10 | @ 100k requests |
| Google Maps | €5 | 1000 Geocoding Requests |
| WhatsApp Business API | €5-15 | Optional |
| **Gesamt (CX21)** | **~€80-120/Monat** | @ 1000 Leads |
| **Gesamt (CX11)** | **~€60-90/Monat** | @ 1000 Leads |

Mit Google Sheets (kein PostgreSQL) und Waha (kein WhatsApp API): ~€40-60/Monat.

---

**Hergestellt mit ❤️ für deutsche Handwerker**