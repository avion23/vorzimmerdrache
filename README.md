# MEISTERANRUF (Projekt: Vorzimmerdrache)

**Status:** EXECUTION PHASE (MVP)  
**Stack:** n8n (SQLite), Twilio API, Google Sheets, Telegram.

## Was es ist

Ein extrem leichtgewichtiger "Dach-Modus" Bot für Handwerker. Er verwandelt stressige Anrufe in qualifizierte WhatsApp-Leads, während der Meister auf dem Dach steht.

## Der Datenfluss (ASCII)

```text
KUNDE RUFT AN
      |
[Twilio Phone Number] <---- Webhook ----> [n8n auf 1GB VPS]
      |                                       |
      | (Parallel)                            | (Logik)
      v                                       v
1. SPRACHANSAGE                      1. PRÜFE BLACKLIST
   "Bin auf dem Dach!"               2. LOGGE ANRUF IN SHEETS (Debug)
      |                              3. SENDE OPT-IN SMS
      v                                       |
KUNDE ANTWORTET AUF SMS ("JA") <--------------+
      |
      v
[n8n STATE MACHINE - SQLite]
      |
      |-- State: "awaiting_plz" (SQLite, <10ms)
      |-- Q1: PLZ? --------> [SMS an Kunde]
      |
      |-- State: "qualified" (SQLite)
      |-- WhatsApp Link ----> [SMS an Kunde]
      v
[QUALIFIZIERTER LEAD] 
      |
      |---> [Google Sheets: Leads Tab] (für Sales)
      |---> [Google Sheets: Debug_Log] (für Debugging)
      |---> [Telegram Alarm an Meister]
```

## Kern-Features (V2 - SQLite State)

- **Zero-Maintenance:** Kein Postgres, kein Redis. n8n nutzt SQLite.
- **SQLite State Machine:** State wird in n8n SQLite gehalten (<10ms Latenz, keine Race Conditions).
- **Spam-Filter:** Blacklist + Rate-Limiting (max 10 SMS/Stunde) reduziert Kosten.
- **DSGVO-Brücke:** SMS-zu-WhatsApp Opt-In Flow mit Zeitstempel (Proof of Consent).
- **Abgekürzter Flow:** Nur 2 Fragen (Opt-In + PLZ) statt 4-5 für bessere Conversion.
- **Debug Logging:** Alle Interaktionen werden in Google Sheets geloggt (für Troubleshooting).
- **Speed-to-Lead:** Reaktion innerhalb von < 3 Sekunden.

## Setup & Deployment

### 1. VPS Vorbereitung

- **Aktueller Server:** Oracle Cloud ARM1 (4 Core, 24GB RAM) - instance2.duckdns.org
- **Alternative:** 1GB RAM Ubuntu VPS (Hetzner CX11 ~€4/Monat)
- Docker & Docker Compose installiert
- Domain zeigt auf Server-IP
- **Firewall:** Ports 80 und 443 in Security Group öffnen (Oracle Cloud)

### 2. Google Sheets vorbereiten

Erstelle 3 Tabs in deinem Spreadsheet:

**Tab 1: Leads** (für Sales)
| Phone | PLZ | OptIn_Timestamp | Qualified_Timestamp | Source | Status |

**Tab 2: Debug_Log** (für Debugging)
| Timestamp | Phone | Direction | Message | State | Action |

**Tab 3: Call_Log** (für Analytics)
| Timestamp | Phone | Status | SMS_Sent |

### 3. .env Konfiguration

Kopiere `.env.example` zu `.env` und fülle aus:

```bash
# Pflichtfelder
DOMAIN=deine-domain.de
TWILIO_ACCOUNT_SID=ACxxxxx
TWILIO_AUTH_TOKEN=xxxxx
TWILIO_PHONE_NUMBER=+49xxxx
TWILIO_WHATSAPP_NUMBER=49xxxx  # Ohne + für wa.me Links
TELEGRAM_BOT_TOKEN=xxxxx
TELEGRAM_CHAT_ID=xxxxx
GOOGLE_SHEETS_SPREADSHEET_ID=xxxxx
GOOGLE_SHEETS_LEADS_RANGE=Leads!A:F
GOOGLE_SHEETS_DEBUG_RANGE=Debug_Log!A:F

# Spam-Schutz
BLACKLISTED_NUMBERS=+491711234567,+49301234567
```

### 3. Start

```bash
cd backend
./scripts/setup.sh
```

### 4. Twilio Webhooks konfigurieren

- Voice Webhook: `https://<DOMAIN>/webhook/incoming-call`
- SMS Webhook: `https://<DOMAIN>/webhook/sms-response`

## Lokale Logik & Kompaktheit

Die gesamte Chat-Logik befindet sich im Workflow `sms-opt-in-v2.json`:

- **Validation:** PLZ muss 5-stellig sein
- **State Machine:** SQLite-basiert (`$getWorkflowStaticData`) - schnell & race-condition-frei
- **Deduplizierung:** Twilio `MessageSid` verhindert doppelte Webhooks
- **Rate Limiting:** Max 10 SMS pro Stunde pro Nummer
- **Debug Logging:** Jede Interaktion wird in `Debug_Log` Tab geschrieben
- **Timeout:** Nach 24h ohne Antwort wird der State automatisch auf `expired` gesetzt

## Hardware-Optimierung

### Für 1GB VPS (Hetzner CX11 etc.)
```yaml
# docker-compose.yml
N8N_CONCURRENCY_PRODUCTION_LIMIT: "1"    # Single execution
N8N_EXECUTIONS_PROCESS: "main"            # Kein Queue-Mode (spart RAM)
NODE_OPTIONS: "--max-old-space-size=768"  # Heap-Limit
```

**Warum diese Einstellungen?**
- Ohne `N8N_EXECUTIONS_PROCESS=main`: n8n startet Worker-Prozesse → RAM-Überlastung bei 3+ gleichzeitigen Anrufen
- Ohne Concurrency-Limit: Gleichzeitige Ausführungen konkurrieren um 1GB RAM

### Für Oracle Cloud ARM (24GB RAM)
Aktuell deployed auf Oracle Cloud ARM1 Instance (4 Core, 24GB RAM). 
Die Ressourcenlimits im docker-compose können hier erhöht werden:
```yaml
memory: 2048M  # Statt 384M bei 1GB VPS
```

## Warum Google Sheets?

Sheets dient als **Interface für den Handwerker** und **Debugging-Tool**:

- **Leads Tab:** Nur finale, qualifizierte Leads (für Sales)
- **Debug_Log Tab:** Alle SMS-Interaktionen (für Troubleshooting)
- **Call_Log Tab:** Alle eingehenden Anrufe (für Analytics)

**Architektur:**
- **State:** In n8n SQLite (schnell, race-condition-frei)
- **Debug:** In Google Sheets (übersichtlich, filterbar)
- **Leads:** In Google Sheets (für Sales-Team)

**Trade-off:** Sheets hat Latenz (~200-500ms), aber da nur finale Leads + Debug-Logs geschrieben werden, ist das System robust und schnell.

## DSGVO-Compliance

- **Opt-In Zeitstempel:** Jede "JA"-Antwort wird mit `OptIn_Timestamp` in Sheets gespeichert
- **STOP-Handler:** Automatische Abmeldung bei Keywords (stop, abmelden, ende)
- **Datenlöschung:** Kunde kann jederzeit "STOP" schreiben → sofortige Abmeldung

## Monitoring

- **Telegram Alerts:** Jeder Anruf und jede Qualifizierung wird per Telegram gemeldet
- **Test-Workflow:** `tester-state-machine.json` validiert alle State-Transitions
- **Logs:** `docker compose logs -f n8n`

## Kosten

### Oracle Cloud (Aktuell)
- VPS (ARM1, 24GB RAM): Kostenlos (Always Free Tier)
- Twilio SMS: ~€0.05 pro Lead
- Twilio Voice: ~€0.01 pro Anruf
- **Gesamt:** ~€2-6/Monat bei moderater Nutzung

### Alternative (Hetzner etc.)
- VPS (1GB): ~€4/Monat
- Twilio SMS: ~€0.05 pro Lead
- Twilio Voice: ~€0.01 pro Anruf
- **Gesamt:** ~€6-10/Monat bei moderater Nutzung

## Support

- n8n Community: https://community.n8n.io
- Twilio Support: https://support.twilio.com

---

**Es ist dreckig, aber es wird sich verkaufen, weil Handwerker keine Software-Architektur kaufen, sondern freie Abende.**
