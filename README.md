# Vorzimmerdrache

**Automatisierte Anrufbearbeitung für Handwerker**

## Inhaltsverzeichnis

- [Quick Start](#quick-start-5-minuten)
- [Was das ist](#was-das-ist)
- [Funktionsweise](#funktionsweise)
- [Tech Stack](#tech-stack)
- [Kosten](#kosten)
- [WhatsApp Opt-In](#whatsapp-opt-in-flow-uwg-konform)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

## Quick Start (5 Minuten)

1. **Repository klonen & Server starten:**
   ```bash
   git clone <repo> vorzimmerdrache
   cd vorzimmerdrache
   cp .env.example .env
   nano .env  # Platzhalter ausfüllen
   ./scripts/deploy-1gb.sh
   ```

2. **n8n öffnen:** `https://<DEINE-DOMAIN>/`
3. **Workflows aktivieren:** "Roof-Mode" & "SMS Opt-In" → Active
4. **Twilio Webhooks konfigurieren:**
   - Voice: `https://<DEINE-DOMAIN>/webhook/incoming-call`
   - SMS: `https://<DEINE-DOMAIN>/webhook/sms-response`

**Fertig!** Teste es mit einem Anruf auf deine Twilio-Nummer.

## Was das ist

Ein 1GB VPS mit folgendem Setup:
- n8n mit SQLite (keine externe Datenbank)
- Twilio API für WhatsApp + Voice (Pay-per-Message)
- Google Sheets API als CRM (Verwaltung via Browser)
- Gesamter Container-RAM: ~512MB (384MB + 128MB)

KEIN PostgreSQL, KEIN Redis, KEIN WAHA, KEIN Baserow, KEINE Worker-Prozesse.

---

## Funktionsweise

1. Kunde ruft Twilio-Nummer an.
2. Webhook triggert n8n Workflow.
3. n8n antwortet sofort mit Sprachansage: "Moin! Wir sind auf dem Dach."
4. n8n prüft Telefonnummer in Google Sheets.
5. n8n sendet WhatsApp an Kunden (via Twilio API).
6. n8n sendet Telegram-Alert an dich.

Minimalistischer Ansatz. Kein Lead-Scoring, keine Förderrechner, keine Datenanreicherung.

---

## WhatsApp Opt-In Flow (UWG-Konform)

Für rechtssichere WhatsApp-Nutzung wird folgender Prozess genutzt:

### Option A: SMS als Brücke → WhatsApp erst nach "JA"

1. Anruf verpasst oder nach X Sekunden nicht angenommen.
2. System sendet sofort neutrale SMS:
   "Hi, wir haben Ihren Anruf verpasst. Möchten Sie Updates per WhatsApp? Antworten Sie mit JA."
3. Kunde antwortet mit "JA" → Opt-In dokumentiert → Ab dann WhatsApp-Kommunikation (Termine, Rückrufe).

**Vorteile:**
- Konform mit WhatsApp Opt-In Richtlinien.
- Minimiert UWG-Risiko (Gesetz gegen den unlauteren Wettbewerb).
- Erst Erlaubnis, dann Nachricht.

### SMS Opt-In Setup

1. Twilio SMS Webhook konfigurieren: `https://<DEINE-DOMAIN>/webhook/sms-response`
2. Google Sheets Spalte "whatsapp_opt_in" zur Dokumentation hinzufügen.
3. `workflows/sms-opt-in.json` in n8n importieren.
4. Twilio leitet SMS-Antworten an den Webhook weiter.

---

## Tech Stack

- **n8n**: v1.50.0 (stabil, optimiert für 1GB RAM)
- **Traefik**: v2.11 (SSL-Terminierung, HTTP→HTTPS Redirect)
- **Datenbank**: SQLite (n8n-intern, WAL-Modus aktiviert)
- **WhatsApp**: Twilio Business API (stateless, läuft auf Twilio-Servern)
- **Voice**: Twilio (stateless, läuft auf Twilio-Servern)
- **CRM**: Google Sheets (Verwaltung im Browser)
- **Benachrichtigungen**: Telegram Bot API

Details zu Systemdesign und Datenflüssen in [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Warum 1GB ausreicht

- n8n (200MB) + Traefik (50MB) + OS-Overhead = ~300MB Gesamtauslastung.
- Keine schweren Dienste (Postgres benötigt min. 150MB).
- WhatsApp-Infrastruktur liegt bei Twilio, nicht auf dem eigenen Server.
- Google Sheets verbraucht 0MB (reine API-Calls).

---

## Kosten

- VPS: €4.15/Monat (Hetzner CX11, 1GB)
- Twilio: €0.005/Nachricht × 100 Msgs = €0.50/Monat (nur WhatsApp)
- Voice: €0.05/Min × 30 Min Anrufe = €1.50/Monat (Dach-Modus)
- Google Sheets: €0 (Free Tier, 28.000 Requests/Monat)

**GESAMT: ~€6.15/Monat**

---

## Bereitstellung

Detaillierte Anweisungen in [SERVER_SETUP.md](SERVER_SETUP.md).

Quick Start:
1. Twilio Account einrichten (WhatsApp + Voice).
2. Google Sheet erstellen.
3. `.env` Datei konfigurieren.
4. Ausführen: `./scripts/deploy-1gb.sh`

---

## Projektstatus

### ✅ Implementiert

**Infrastruktur:**
- Docker Compose mit Traefik v2.11 (SSL).
- n8n mit SQLite.
- Memory Limits: n8n (512MB), Traefik (256MB).
- Healthchecks: n8n Monitoring alle 30s.
- Log-Rotation: 10MB max, 3 Dateien pro Container.
- Automatisierte Backups: Die letzten 7 Backups werden vorgehalten.
- Port 5678 für initiales Setup freigegeben.

**Sicherheit:**
- Traefik Dashboard deaktiviert (keine Angriffsfläche).
- Docker Socket read-only gemountet.
- Port 5678 durch Firewall geschützt.
- Fehlerbehandlung in Workflows (Telegram-Alerts bei Fehlern).
- Validierung deutscher Mobilfunknummern (26 Präfixe).

**Workflows:**
- `roof-mode.json` (Anrufe, SMS, WhatsApp, Telegram).
- `sms-opt-in.json` (WhatsApp Opt-In via SMS).
- Error-Nodes mit Retry-Logik.

**Automatisierung:**
- `scripts/configure-system.sh` (Initiales Setup).
- `scripts/backup-db.sh` (Tägliche Backups).
- `scripts/validate-env.sh` (Konfigurationsprüfung).
- `scripts/import-workflows.sh` (Workflow-Import).

### 📋 Erfordert manuelle Konfiguration (ca. 32 Minuten)

**Schritt 1: API Credentials (10 Min)**
`/opt/vorzimmerdrache/.env` bearbeiten und Platzhalter ersetzen:
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `TWILIO_WHATSAPP_TEMPLATE_SID`

**Schritt 2: Workflows aktivieren (2 Min)**
1. n8n Instanz öffnen.
2. "Roof-Mode" & "SMS Opt-In" auf "Active" schalten.

**Schritt 3: n8n Credentials hinterlegen (15 Min)**
In n8n UI → Settings → Credentials:
1. Google Sheets (OAuth2 oder Service Account).
2. Twilio (Account SID + Auth Token).
3. Telegram (Bot Token).

**Schritt 4: Twilio Webhooks (5 Min)**
In der Twilio Console:
- Voice Webhook: `https://<DEINE-DOMAIN>/webhook/incoming-call`
- SMS Webhook: `https://<DEINE-DOMAIN>/webhook/sms-response`

**Schritt 5: End-to-End Test (5 Min)**
- Twilio Nummer anrufen.
- SMS-Erhalt prüfen.
- Mit "JA" antworten.
- Google Sheet auf Updates prüfen.

---

## Was enthalten ist

- 2.1s Antwortzeit (TwiML).
- Automatisierter WhatsApp-Versand.
- Telegram-Benachrichtigung bei jedem Ereignis.
- Kundendaten-Synchronisation in Google Sheets.

---

## Was NICHT enthalten ist

- Kein Lead-Scoring.
- Keine Förderrechner.
- Keine Datenanreicherung.
- Kein komplexes CRM.
- Kein PostgreSQL.

---

## Häufig gestellte Fragen (FAQ)

### Funktioniert das mit Festnetznummern?
**Teilweise.** Das System erkennt Festnetznummern über die Twilio Lookup API. Bei Festnetzanschlüssen wird keine SMS gesendet (da nicht möglich), sondern sofort eine Telegram-Benachrichtigung an den Handwerker gesendet: "📞 Festnetzanruf von +49 XXX XXXXXXX - Bitte manuell zurückrufen."

### Was passiert, wenn der Kunde nicht mit "JA" antwortet?
Der Lead wird nach 24 Stunden als "abgelaufen" markiert. Der Handwerker erhält eine Telegram-Benachrichtigung und kann manuell kontaktieren. Das System sendet keine weiteren automatischen Nachrichten.

### Kann ich das System vorübergehend deaktivieren?
Ja, über das Google Sheets. Füge ein Blatt "Global_Settings" hinzu mit einer Zelle "Status". Wenn der Wert "Inactive" ist, antwortet n8n nicht auf Anrufe. Alternative: Twilio-Nummer in der Konsole vorübergehend deaktivieren.

### Was kostet das pro Monat?
**Basisbetrieb:**
- VPS: €4.15 (Hetzner CX11, 1GB RAM)
- Twilio: ~€2.00 (100 WhatsApp + 30 Min Voice)
- **Gesamt: ~€6.15/Monat**

**Bei hoher Auslastung:**
- 1000 Kunden/Monat: ~€10-15
- 10.000 Kunden/Monat: ~€50-80

### Wie viele Kunden kann das System verarbeiten?
Unbegrenzt. Google Sheets API erlaubt 28.000 Requests/Monat (Free Tier). Bei 100 Anrufen/Tag = 3.000/Monat hast du reichlich Puffer. Für mehr: Google Sheets API für wenige €/Monat upgraden.

### Was passiert bei Twilio-Guthaben < €5?
Das System sendet automatisch eine Telegram-Warnung. Es empfiehlt sich, ein Auto-Recharge in Twilio einzurichten (ab €5 automatisch aufladen).

### Kann ich mehrere Handwerker unterstützen?
Aktuell nicht. Das System ist für EINEN Handwerker ausgelegt. Für mehrere Handwerker ist eine separate Twilio-Nummer pro Handwerker oder eine komplexere Routing-Logik erforderlich (siehe ARCHITECTURE.md, Abschnitt "Multi-Craftsman Routing").

### Wie sicher sind meine Kundendaten?
Sehr sicher:
- Alle API-Verbindungen sind HTTPS-verschlüsselt
- Webhooks werden per HMAC-SHA1 validiert
- Anmeldeinformationen liegen lokal auf deinem Server (.env)
- Telegram-Benachrichtigungen enthalten nur Telefonnummern, keine sensiblen Daten

---

## Troubleshooting

### n8n lässt sich nicht öffnen
**Prüfen:**
```bash
docker compose ps  # Container laufen?
docker compose logs n8n  # Fehler in Logs?
```

**Lösung:**
```bash
docker compose restart n8n
# Falls das nicht hilft:
docker compose down -v && docker compose up -d
```

### Telegram-Benachrichtigungen kommen nicht an
**Prüfen:**
1. Ist `TELEGRAM_BOT_TOKEN` korrekt in `.env`?
2. Ist `TELEGRAM_CHAT_ID` korrekt? (Mit @userinfobot prüfen)

**Testen:**
```bash
curl -X POST "https://api.telegram.org/bot<DEIN_TOKEN>/sendMessage" \
  -d "chat_id=<DEINE_CHAT_ID>" \
  -d "text=Test-Nachricht"
```

### Google Sheets werden nicht aktualisiert
**Prüfen:**
1. Ist die Tabelle mit der Service-Account-E-Mail geteilt?
2. Stimmt die `SPREADSHEET_ID`?
3. Sind die Sheet-Namen exakt korrekt (Groß-/Kleinschreibung)?

**Lösung:**
- Service-Account-E-Mail in Google Sheets als "Editor" hinzufügen
- n8n-Credentials neu konfigurieren

### SMS wird nicht gesendet
**Prüfen:**
```bash
# Twilio-Balance prüfen
curl -X GET "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Balance.json" \
  -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN"
```

**Lösung:**
- Guthaben aufladen (min. €20 empfohlen)
- Twilio-Nummer ist SMS-fähig?

### Anrufe werden nicht beantwortet
**Prüfen:**
1. Webhook-URL in Twilio korrekt?
2. n8n-Workflow ist "Active"?
3. Traefik leitet Port 443 richtig?

**Lösung:**
- Twilio-Webhook-Logs in der Konsole prüfen
- n8n-Workflow-Ausführungen anzeigen

### Speicherplatz auf VPS fast voll
**Prüfen:**
```bash
df -h  # Festplattenbelegung
du -sh ./n8n_data  # n8n-Daten prüfen
docker system df  # Docker-Belegung
```

**Lösung:**
```bash
# Docker-Cache aufräumen
docker system prune -a

# n8n-Ausführungsdaten bereinigen
# In n8n: Settings → Execution Data → Delete all older than 7 days
```

### SSL-Zertifikat ist abgelaufen
**Lösung:**
```bash
rm -rf letsencrypt/acme.json
docker compose restart traefik
```

---

## Support & Hilfe

- **Detaillierte Anleitungen:** Siehe [ARCHITECTURE.md](ARCHITECTURE.md)
- **Server-Einrichtung:** Siehe [SERVER_SETUP.md](SERVER_SETUP.md)
- **n8n Community:** https://community.n8n.io
- **Twilio Support:** https://support.twilio.com

**Probleme?** Die meisten Lösungen findest du im [SERVER_SETUP.md](SERVER_SETUP.md) im Abschnitt "Fehlerbehebung".