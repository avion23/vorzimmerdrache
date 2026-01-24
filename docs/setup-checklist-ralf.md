# Setup-Checkliste für Ralf 🔧

**Zeitaufwand:** ~2 Stunden (inkl. Wartezeiten)
**Schwierigkeit:** Mittel (Copy-Paste Skills erforderlich)
**Budget:** ~€30 Startkosten + €12/Monat

---

## Phase 1: Accounts & Zugänge (30 Min)

### 1.1 Hetzner Cloud Account
- [ ] Gehe zu [hetzner.cloud](https://hetzner.cloud)
- [ ] Registrieren mit Email + Kreditkarte
- [ ] Bestätigung abwarten (5-10 Min)
- [ ] SSH Key generieren:
  ```bash
  ssh-keygen -t ed25519 -C "ralf@solar-meier.de"
  cat ~/.ssh/id_ed25519.pub
  ```
- [ ] Public Key in Hetzner Console einfügen
- [ ] **CX21 Server bestellen** (2GB RAM, €5.82/Monat)
  - Standort: Nürnberg (DSGVO-konform)
  - OS: Ubuntu 22.04
  - SSH Key auswählen

**Resultat:** Server-IP notieren (z.B. `95.217.123.45`)

---

### 1.2 Domain (Optional aber empfohlen)
- [ ] Domain bei [Namecheap](https://namecheap.com) kaufen (~€10/Jahr)
  - Beispiel: `solar-meier.de`
- [ ] DNS Settings → A Record hinzufügen:
  ```
  Host: @
  Value: 95.217.123.45 (deine Server-IP)
  
  Host: n8n
  Value: 95.217.123.45
  
  Host: waha
  Value: 95.217.123.45
  ```
- [ ] Warten bis DNS propagiert (10-30 Min)
  ```bash
  dig n8n.solar-meier.de
  ```

**Wenn keine Domain:** Nutze Server-IP direkt (kein SSL)

---

### 1.3 Twilio Account
- [ ] Gehe zu [twilio.com/try-twilio](https://twilio.com/try-twilio)
- [ ] Registrieren (Email-Verifizierung)
- [ ] Trial Account: €10 Startguthaben
- [ ] **Deutsche Nummer kaufen:**
  - Phone Numbers → Buy a Number
  - Country: Germany (+49)
  - Type: Mobile (z.B. +49 15...)
  - Capabilities: Voice + SMS + MMS
  - Preis: ~€1/Monat
- [ ] **Credentials notieren:**
  ```
  TWILIO_ACCOUNT_SID=AC... (36 Zeichen)
  TWILIO_AUTH_TOKEN=... (32 Zeichen)
  TWILIO_PHONE_NUMBER=+49151234567
  ```
  (Findest du unter Console → Account Info)

**Später:** WhatsApp Business API beantragen (dauert 2 Wochen)

---

### 1.4 Telegram Bot
- [ ] Telegram App öffnen
- [ ] Suche nach `@BotFather`
- [ ] Chat starten: `/start`
- [ ] Neuen Bot erstellen: `/newbot`
- [ ] Bot Name: `Solar Meier Leads`
- [ ] Bot Username: `solar_meier_bot` (muss unique sein)
- [ ] **Bot Token notieren:**
  ```
  TELEGRAM_BOT_TOKEN=1234567890:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
  ```
- [ ] Deine Chat ID finden:
  - Schreibe deinem Bot: `/start`
  - Gehe zu: `https://api.telegram.org/bot<TOKEN>/getUpdates`
  - Suche nach `"chat":{"id":123456789`
  ```
  INSTALLER_TELEGRAM_CHAT_ID=123456789
  ```

---

### 1.5 Google Cloud (Maps API)
- [ ] Gehe zu [console.cloud.google.com](https://console.cloud.google.com)
- [ ] Neues Projekt: "Vorzimmerdrache"
- [ ] APIs aktivieren:
  - Google Maps Geocoding API
  - Google Sheets API
- [ ] API Key erstellen:
  - APIs & Services → Credentials → Create Credentials → API Key
  - Restriction: HTTP referrers (nur deine Domain)
  ```
  GOOGLE_MAPS_API_KEY=AIzaSy...
  ```
- [ ] **Service Account für Sheets:**
  - IAM & Admin → Service Accounts → Create
  - Name: `n8n-vorzimmerdrache`
  - Role: Editor
  - Create Key → JSON downloaden
  - Inhalt kopieren:
  ```bash
  cat ~/Downloads/vorzimmer-*.json | tr -d '\n' | pbcopy
  ```
  ```
  GOOGLE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
  ```

- [ ] **Google Sheet erstellen:**
  - Neue Tabelle: "PV Leads"
  - Spalten: `timestamp | name | phone | email | address | status | notes`
  - Sheet mit Service Account teilen (Email aus JSON)
  - Sheet ID aus URL kopieren:
    ```
    https://docs.google.com/spreadsheets/d/1BxiMvs0XRA5n.../edit
                                           ^^^^^^^^^^^^^^^^
    GOOGLE_SHEETS_ID=1BxiMvs0XRA5n...
    ```

---

### 1.6 WhatsApp Prepaid SIM (für Waha)
- [ ] Prepaid SIM kaufen (Aldi Talk, Congstar, ~€10)
- [ ] WhatsApp Business App auf altem Handy installieren
- [ ] Mit SIM-Nummer registrieren
- [ ] **WICHTIG:** Nutze NICHT deine Haupt-Nummer!
  - Meta kann Account bannen bei Automatisierung
  - Separates Business-Profil schützt privates WhatsApp

---

## Phase 2: Server Setup (20 Min)

### 2.1 SSH Verbindung testen
```bash
ssh root@95.217.123.45
# Beim ersten Mal: yes eingeben (Fingerprint)
```

### 2.2 Ein-Zeilen-Installation
```bash
curl -fsSL https://raw.githubusercontent.com/avion23/vorzimmerdrache/main/scripts/deploy-hetzner.sh | bash
```

**Der Script macht:**
- ✅ Docker + Docker Compose installieren
- ✅ Swap File (4GB) erstellen
- ✅ Firewall konfigurieren (ufw)
- ✅ Traefik Reverse Proxy (SSL)
- ✅ n8n, Waha, PostgreSQL, Redis starten
- ✅ Health Monitoring Setup

**Wartezeit:** ~5 Minuten

---

### 2.3 Environment Konfigurieren
```bash
cd vorzimmerdrache
cp .env.example .env
nano .env
```

**Kritische Variablen eintragen:**
```bash
# Server
DOMAIN=solar-meier.de
LETSENCRYPT_EMAIL=ralf@solar-meier.de

# Twilio (von Phase 1.3)
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_PHONE_NUMBER=+49151234567

# Telegram (von Phase 1.4)
TELEGRAM_BOT_TOKEN=1234567890:ABC...
INSTALLER_TELEGRAM_CHAT_ID=123456789

# Google (von Phase 1.5)
GOOGLE_MAPS_API_KEY=AIzaSy...
GOOGLE_SHEETS_ID=1BxiMvs0XRA5n...
GOOGLE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'

# Installateur
INSTALLER_PHONE_NUMBER=+491701234567  # DEINE Handynummer
COMPANY_NAME=Solar Meier GmbH
```

**Auto-Generate Secrets:**
```bash
./scripts/validate-env.sh --fix
# Generiert automatisch:
# - N8N_ENCRYPTION_KEY
# - WAHA_API_TOKEN
# - Passwörter (n8n, DB, Redis)
```

**Speichern:** `Ctrl+X` → `Y` → `Enter`

---

### 2.4 Services starten
```bash
docker compose up -d
```

**Prüfen:**
```bash
docker ps
# Sollte zeigen:
# - n8n (running)
# - waha (running)
# - postgres (running)
# - redis (running)
# - traefik (running)
```

**Logs checken:**
```bash
docker compose logs -f n8n
# Warte auf: "Editor is now accessible via: https://n8n.solar-meier.de"
```

---

## Phase 3: Waha (WhatsApp) Pairing (10 Min)

### 3.1 QR Code generieren
```bash
curl http://localhost:3000/api/sessions/default/qr
```

**Oder im Browser:**
```
https://waha.solar-meier.de/api/sessions/default/qr
```

**Du siehst:** ASCII QR Code im Terminal

---

### 3.2 WhatsApp Business Handy scannen
1. WhatsApp Business App öffnen (auf Prepaid-Handy)
2. Menü → WhatsApp Web
3. QR Code scannen (vom Terminal/Browser)
4. **Bestätigung:** "WhatsApp Web erfolgreich verbunden"

---

### 3.3 Session prüfen
```bash
curl http://localhost:3000/api/sessions
# Erwartung:
# [{"id":"default","status":"WORKING"}]
```

**Status WORKING = Erfolg!** 🎉

---

## Phase 4: n8n Workflows aktivieren (15 Min)

### 4.1 n8n öffnen
```
https://n8n.solar-meier.de
```

**Login:**
```
User: admin (aus .env N8N_BASIC_AUTH_USER)
Pass: (aus .env N8N_BASIC_AUTH_PASSWORD)
```

---

### 4.2 Workflows importieren
1. Workflows → Import from File
2. Auswählen:
   - `workflows/inbound-handler.json` (Dach-Modus)
   - `workflows/speed-to-lead-main.json` (Outbound)
   - `workflows/status-loop.json` (Automatisierung)

3. **Credentials konfigurieren:**
   - Google Sheets: Service Account JSON einfügen
   - Twilio: Account SID + Auth Token
   - Waha: API URL + Token (aus .env)

---

### 4.3 Workflows aktivieren
- [ ] Inbound Handler → Active (Slider rechts oben)
- [ ] Speed-to-Lead → Active
- [ ] Status Loop → Active

**Webhook URLs notieren:**
```
Inbound: https://n8n.solar-meier.de/webhook/incoming-voice
Outbound: https://n8n.solar-meier.de/webhook/pv-lead
```

---

## Phase 5: Twilio konfigurieren (10 Min)

### 5.1 Voice Webhook setzen
1. Gehe zu [console.twilio.com](https://console.twilio.com)
2. Phone Numbers → Manage → Active Numbers
3. Klicke deine +49 Nummer
4. **Voice Configuration:**
   ```
   A CALL COMES IN:
   Webhook: https://n8n.solar-meier.de/webhook/incoming-voice
   HTTP POST
   ```
5. Save

---

### 5.2 SMS Webhook (Optional für Fallback)
```
A MESSAGE COMES IN:
Webhook: https://n8n.solar-meier.de/webhook/incoming-sms
HTTP POST
```

---

## Phase 6: Testen (15 Min)

### 6.1 Dach-Modus Test
1. **Ruf deine Twilio-Nummer an:** `+49 151...`
2. **Erwartung:**
   - ✅ Voice-Bot antwortet sofort (DE Stimme)
   - ✅ "Moin! Bin auf dem Dach, WhatsApp kommt..."
   - ✅ Automatisches Auflegen
3. **Prüfe WhatsApp:** (auf Prepaid-Handy)
   - Nachricht mit Emojis an deine Hauptnummer
4. **Prüfe Telegram:** (auf deinem Handy)
   - Bot schickt: "📞 Verpasster Anruf von +491701234567"

**Alle 3 funktionieren?** 🎉 **Dach-Modus läuft!**

---

### 6.2 Outbound Test
```bash
curl -X POST https://n8n.solar-meier.de/webhook/pv-lead \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Max Mustermann",
    "phone": "017012345678",
    "email": "max@test.de",
    "address": "Musterstraße 1, 80331 München"
  }'
```

**Erwartung:**
1. Google Sheet bekommt neue Zeile
2. WhatsApp an Max (falls Nummer echt)
3. Du wirst angerufen: "Drücke 1 um zu verbinden"

---

### 6.3 Telegram Bot testen
In Telegram:
```
/status      → Zeigt offene Leads
/today       → Heute's Übersicht
/register Ralf → Registriert dich als Installateur
```

---

## Phase 7: Monitoring & Wartung

### 7.1 Logs ansehen
```bash
# Alle Services
docker compose logs -f

# Nur n8n
docker compose logs -f n8n

# Nur Waha (bei WhatsApp-Problemen)
docker compose logs -f waha
```

---

### 7.2 Memory Monitoring
```bash
./scripts/monitor.sh
# Zeigt RAM/Swap Nutzung alle 5 Sekunden
```

**Warnsignale:**
- Swap > 1GB genutzt = System überlastet
- OOM Kills in `dmesg` = RAM zu wenig

---

### 7.3 Backup einrichten
```bash
# Cronjob für tägliches Backup
crontab -e
```

Einfügen:
```
0 2 * * * /root/vorzimmerdrache/scripts/backup.sh >> /var/log/backup.log 2>&1
```

**Backup beinhaltet:**
- PostgreSQL Datenbank
- n8n Workflows
- .env Secrets (verschlüsselt)

---

## Troubleshooting 🔧

### Problem: n8n startet nicht
```bash
docker compose logs n8n
# Prüfe auf Fehler wie:
# - "Port 5678 already in use" → docker compose down && docker compose up -d
# - "Database connection failed" → PostgreSQL läuft nicht
```

### Problem: Waha Session FAILED
```bash
# QR Code neu generieren
docker compose restart waha
sleep 30
curl http://localhost:3000/api/sessions/default/qr
# Erneut scannen
```

### Problem: Twilio Webhook Timeout
```bash
# n8n Workflow testen (ohne Twilio)
# In n8n: Workflow → Execute Workflow
# Webhook manuell triggern mit Test-Daten
```

### Problem: WhatsApp kommt nicht an
```bash
# Waha Status prüfen
curl http://localhost:3000/api/sessions
# Status WORKING? → OK
# Status FAILED? → docker compose restart waha

# Fallback: SMS sollte funktionieren (Twilio)
```

### Problem: OOM Kills (Speicher voll)
```bash
dmesg | grep -i "killed process"
# Wenn Waha killed wurde:
# → Hetzner CX31 (4GB RAM) upgraden
# Oder: docker-compose-low-memory.yml nutzen (halbe Allocations)
```

---

## Nächste Schritte (nach Go-Live)

### Woche 1: Beobachten
- [ ] Täglich Logs checken (`docker compose logs`)
- [ ] Memory Monitoring (`./scripts/monitor.sh`)
- [ ] Erste echte Leads testen

### Woche 2-4: Optimieren
- [ ] Twilio WhatsApp Business API beantragen (2 Wochen Approval)
- [ ] A/B Test der 3 TwiML Voice Varianten (welche konvertiert besser?)
- [ ] Double Opt-In (DOI) Workflow einbauen

### Monat 2: Skalieren
- [ ] PostgreSQL als Haupt-CRM (statt Google Sheets)
- [ ] Baserow UI für Lead-Management
- [ ] KfW Förderrechner integrieren

---

## Support & Hilfe

**Dokumentation:**
- [n8n Docs](https://docs.n8n.io)
- [Waha API Docs](https://waha.devlike.pro)
- [Twilio Docs](https://twilio.com/docs)

**Community:**
- GitHub Issues: `github.com/avion23/vorzimmerdrache/issues`
- n8n Forum: `community.n8n.io`

**Notfall-Support:**
```bash
# System komplett neu starten
docker compose down
docker compose up -d

# Alle Container neu bauen
docker compose down
docker compose up -d --build --force-recreate
```

---

**Viel Erfolg, Ralf! 🚀**

*Denk dran: Das System spart dir ~€30.000/Jahr an verlorenen Leads. Die €12/Monat sind die beste Investition deines Lebens.*
