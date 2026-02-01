# Vorzimmerdrache: Systemarchitektur-Dokumentation

## Inhaltsverzeichnis

- [System Overview](#1-system-overview)
- [Call Handling Flow](#2-call-handling-flow)
- [SMS Opt-In Flow](#3-sms-opt-in-flow)
- [Data Model](#4-data-model)
- [Error Handling](#5-error-handling--recovery-flows)
- [Security](#6-security)
- [Multi-User](#7-erweiterung-für-weitere-handwerker)
- [Daily Operations](#8-daily-operations)
- [Technology Stack](#13-technology-stack)

---

## Quick Start
**Funktion:** Verarbeitet automatisch verpasste Anrufe von Kunden, sendet eine Sprachnachricht, erfasst Informationen in einer Tabelle und leitet Kunden zur Nachverfolgung an WhatsApp weiter.

**Zielgruppe:** Handwerker (Dachdecker, Installateure etc.), die während der Arbeit keine Anrufe entgegennehmen können.

**Ablauf:** Kunde ruft an → hört „Wir sind auf dem Dach, antworte mit JA für WhatsApp“ → erhält SMS → antwortet mit „JA“ → erhält WhatsApp-Link mit Buchungsinfos → Handwerker sieht Benachrichtigung und kann nachfassen.

## 1. System Overview

### High-Level Architecture

```mermaid
graph TB
    subgraph External["Externe Dienste"]
        TW[Twilio API<br/>Voice + SMS + WhatsApp]
        TE[Telegram Bot API]
        GS[Google Sheets<br/>CRM-Datenbank]
    end
    
    subgraph VPS["1GB VPS (Hetzner CX11)"]
        subgraph Edge["Edge-Schicht"]
            TR[Traefik v2.11<br/>SSL-Terminierung<br/>Rate Limiting]
        end
        
        subgraph App["Anwendungsschicht"]
            N8[n8n v1.50.0<br/>Workflow-Engine<br/>SQLite DB]
        end
        
        subgraph Storage["Persistenter Speicher"]
            VOL1[(n8n_data<br/>Workflows + DB)]
            VOL2[(letsencrypt<br/>SSL-Zertifikate)]
        end
    end
    
    subgraph Clients["Client-Schicht"]
        C[Kunde<br/>Telefon]
        CR[Handwerker<br/>Telegram App]
    end
    
    C <-- "Sprache/SMS/WhatsApp" --> TW
    TW <-- "Webhooks" --> TR
    TR --> N8
    N8 --> GS
    N8 --> TE
    TE --> CR
    
    N8 -.-> VOL1
    TR -.-> VOL2
    
    style TW fill:#f9f,stroke:#333,stroke-width:2px
    style TE fill:#5af,stroke:#333,stroke-width:2px
    style GS fill:#4f4,stroke:#333,stroke-width:2px
    style N8 fill:#ff9,stroke:#333,stroke-width:2px
    style TR fill:#f99,stroke:#333,stroke-width:2px
```

### Network & Container Topology

```mermaid
graph LR
    subgraph docker_network["Docker-Netzwerk: vorzimmerdrache_default"]
        subgraph traefik["Traefik-Container"]
            TR1[Traefik]
        end
        
        subgraph n8n["n8n-Container"]
            N8N[n8n]
        end
    end
    
    subgraph volumes["Docker-Volumes"]
        V1[n8n_data<br/>/home/node/.n8n]
        V2[letsencrypt<br/>/letsencrypt]
    end
    
    subgraph ports["Host-Ports"]
        P80[Port 80]
        P443[Port 443]
    end
    
    P80 --> TR1
    P443 --> TR1
    TR1 --> N8N
    
    N8N -.->|SQLite DB + Workflows| V1
    TR1 -.->|SSL-Zertifikate| V2
```

### Infrastructure Layer
Das System läuft auf Docker hinter einem Traefik Reverse Proxy:

```mermaid
graph LR
    subgraph Edge
        T[Twilio Gateway]
    end
    
    subgraph Application_Layer
        TR[Traefik Proxy]
        N[n8n Automatisierungs-Engine]
    end
    
    subgraph Data_Alerting
        GS[Google Sheets CRM]
        TG[Telegram Bot API]
    end

    T <--> TR
    TR <--> N
    N <--> GS
    N --> TG
```

### Komponenten-Rollen
| Component | Role |
|-----------|------|
| **Twilio** | Empfängt Anrufe/SMS, sendet Sprachnachrichten und SMS |
| **n8n** | Orchestriert Workflows (Anrufbearbeitung, SMS-Verarbeitung, CRM-Updates) |
| **Google Sheets** | Speichert Kundendaten und Anrufhistorie |
| **Telegram** | Sendet Echtzeit-Alarme an den Handwerker |
| **Traefik** | Übernimmt SSL, Routing und Sicherheit |

## 2. Lead Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> IncomingCall: Telefon klingelt
    IncomingCall --> Logged: Anruf in Sheet protokolliert
    Logged --> SMS_Sent: Opt-in SMS auslösen
    SMS_Sent --> PendingOptIn: 24h Zeitfenster
    
    PendingOptIn --> WhatsApp_Active: Kunde antwortet "JA"
    PendingOptIn --> Expired: Keine Antwort/Timeout
    
    WhatsApp_Active --> ManualFollowUp: WhatsApp-Link gesendet
    Expired --> ManualFollowUp: Handwerker benachrichtigt
    
    ManualFollowUp --> [*]: Gespräch abgeschlossen
    
    note right of PendingOptIn
        Kunde hat 24h zum Antworten mit "JA"
        Nach 24h: Abgelaufen-Status
    end note
    
    note right of WhatsApp_Active
        UWG-konformer Opt-in dokumentiert
        WhatsApp-Kommunikation aktiviert
    end note
```

### Lead States Explained

| State | Description | Next Action |
|-------|-------------|-------------|
| **IncomingCall** | Customer is calling | System answers, logs call |
| **Logged** | Call recorded in Google Sheets | SMS opt-in invite sent |
| **SMS_Sent** | Opt-in SMS delivered | Waiting for customer reply |
| **PendingOptIn** | 24-hour window active | Customer replies or expires |
| **WhatsApp_Active** | Opt-in confirmed | Send WhatsApp link |
| **Expired** | No response within 24h | Manual follow-up needed |
| **ManualFollowUp** | Craftsman takes over | Conversation via WhatsApp |

## 3. Data Flow: CRM Updates

```mermaid
sequenceDiagram
    participant T as Twilio
    participant N as n8n
    participant GS as Google Sheets
    participant TG as Telegram
    
    Note over N: Schritt 1: Anruf empfangen
    T->>N: Webhook: Eingehender Anruf
    N->>N: Telefonnummer normalisieren (E.164)
    N->>GS: Prüfen ob Kunde existiert
    
    alt Kunde existiert
        GS-->>N: Kundendaten zurückgeben
        N->>GS: Last_Contact aktualisieren
    else Neuer Kunde
        N->>GS: Neue Zeile erstellen
    end
    
    Note over N: Schritt 2: Anruf protokollieren
    N->>GS: An Call_Log Sheet anhängen
    N->>N: Parallele Aktionen auslösen
    
    par Parallele Aktionen
        N->>T: TwiML-Sprachnachricht zurückgeben
        N->>T: SMS Opt-in Einladung senden
        N->>TG: Telegram Alarm senden
    end
    
    Note over GS: Daten für Analytics persistiert
```

### CRM Update Flow Details

**Phone Normalization:**
- **Input:** `0171 1234567`, `0049 171 1234567`, `+49 171 1234567`
- **Validation:** Regex `^\+?[1-9]\d{1,14}$`
- **Output:** `+491711234567` (E.164 format)

**Google Sheets Operations:**
1. **Lookup:** Query by `Phone` column
2. **Update:** Modify `Last_Contact` timestamp
3. **Log:** Append row to `Call_Log` sheet

**Parallel Processing:**
- Voice message (instant response)
- SMS delivery (async)
- Telegram alert (async, non-blocking)

## 4. Call Handling Flow

Wenn ein Kunde die Nummer des Handwerkers anruft:

```mermaid
sequenceDiagram
    participant C as Kunde
    participant T as Twilio
    participant N as n8n
    participant G as Google Sheets
    participant H as Handwerker (Telegram)

    C->>T: Wählt Nummer
    T->>N: Webhook: Eingehender Anruf
    
    Note over N: 1. Signatur verifizieren<br/>2. Telefonnummer normalisieren
    
    par Parallele Aktionen
        N->>G: Anruf in Call_Log protokollieren
        N->>G: Kundeninfo nachschlagen
        N->>H: Alarm senden: "Verpasster Anruf von..."
    end
    
    N->>T: Sprachnachricht zurückgeben
    T->>C: 🔊 "Wir sind auf dem Dach. Antworte JA für WhatsApp"
    
    N->>T: SMS mit Opt-in Einladung senden
    T->>C: 📱 "Antworte JA um auf WhatsApp fortzufahren"
```

**Customer Experience:**
1. Ruft die Nummer an.
2. Hört: „Moin! Wir sind gerade auf dem Dach...“
3. Erhält SMS: „Antworte mit JA, um über WhatsApp fortzufahren."

**Craftsman View:**
- Telegram-Benachrichtigung: „Verpasster Anruf von +49 171 1234567".
- Eintrag im Google Sheets Call_Log.

## 5. SMS Opt-In Flow

Nach Erhalt der SMS stimmt der Kunde zu:

```mermaid
sequenceDiagram
    participant C as Kunde
    participant T as Twilio
    participant N as n8n
    participant G as Google Sheets
    participant H as Handwerker (Telegram)

    C->>T: Antwortet: "JA"
    T->>N: Webhook: SMS-Antwort
    
    Note over N: Nachrichteninhalt parsen
    
    alt Nachricht = "JA"
        N->>G: OptIn_Status = TRUE aktualisieren
        N->>T: WhatsApp Nachricht senden
        T->>C: 📲 WhatsApp: "Hier ist Ihr Buchungslink..."
        N->>H: Alarm: "Neuer Lead hat zugestimmt!"
    else Anderer Text
        N->>H: Alarm: "Ungültige Antwort, manuelle Nachverfolgung erforderlich"
    end
```

**Customer Experience:**
1. Antwortet mit „JA" auf die SMS.
2. Erhält WhatsApp-Nachricht mit Buchungs-/Terminlink.
3. Kann nun direkt via WhatsApp mit dem Handwerker chatten.

**Craftsman View:**
- Telegram-Benachrichtigung: „Neuer Lead hat zugestimmt: +49 171 1234567".
- Customer OptIn_Status in Google Sheets aktualisiert.
- Kann nun auf WhatsApp antworten.

## 6. Error Handling & Recovery Flows

### Error Matrix

| Twilio Error Code | Description | Recovery Action | Notification |
|-------------------|-------------|-----------------|--------------|
| **21614** | "To" number is not a valid mobile number | Skip SMS, send Telegram alert | Landline detected |
| **21612** | Phone number is not reachable | Retry 3x with backoff | Delivery failed |
| **21408** | Permission to send SMS not enabled | Check Twilio account permissions | Configuration error |
| **30001** | Queue overflow | Retry after 1s delay | Rate limit hit |

### Error Handling Flow

```mermaid
flowchart TD
    Start[Webhook empfangen] --> Validate{Signatur validieren}
    
    Validate -->|Ungültig| Security[HMAC-SHA1 fehlgeschlagen]
    Validate -->|Gültig| Process[Anfrage verarbeiten]
    
    Process --> CheckType{Leitungstyp prüfen}
    
    CheckType -->|Mobilfunk| Proceed[Flow fortsetzen]
    CheckType -->|Festnetz| Landline[Festnetz erkannt]
    
    Landline --> AlertTG[Telegram Alarm: Festnetzanruf]
    AlertTG --> ManualNotify[Handwerker: Manuell zurückrufen]
    ManualNotify --> End[Ende]
    
    Proceed --> API[API-Aufruf: Twilio/Sheets]
    
    API -->|Erfolg| Success[Workflow fortsetzen]
    API -->|Rate Limit| Retry[Warten + Wiederholen]
    API -->|Auth Fehler| AuthFail[Zugangsdaten ungültig]
    API -->|Netzwerk Fehler| NetRetry[Exponentieller Backoff]
    
    Retry -->|3 Versuche fehlgeschlagen| FailMax[Max Wiederholungen überschritten]
    NetRetry -->|Immer noch fehlgeschlagen| FailMax
    AuthFail --> Critical[Kritischer Alarm]
    
    FailMax --> Partial[Teilerfolg]
    Critical --> Admin[Admin Benachrichtigung]
    
    Success --> End
    Partial --> End
    
    style Security fill:#f99,stroke:#333,stroke-width:2px
    style Critical fill:#f00,stroke:#000,stroke-width:3px
    style Landline fill:#ff9,stroke:#333,stroke-width:2px
```

### Webhook Security Implementation

**HMAC-SHA1 Signature Verification:**
```javascript
// n8n Function Node code
const crypto = require('crypto');
const url = require('url');

const twilioSignature = $webhook.headers['x-twilio-signature'];
const urlParsed = url.parse($webhook.url);
const urlWithPath = $execution.url.split('?')[0];

const signature = crypto
  .createHmac('sha1', $env.TWILIO_AUTH_TOKEN)
  .update(urlWithPath + $webhook.body)
  .digest('base64');

if (signature !== twilioSignature) {
  throw new Error('Invalid Twilio signature');
}

// Valid, continue processing
```

### Common Failure Scenarios

**1. Landline Detection:**
- **Trigger:** Twilio Lookup API returns "landline"
- **Action:** Skip SMS, send Telegram alert immediately
- **Message:** "📞 Landline call from +49 XXX XXXXXXX - SMS not possible, please call back"

**2. Twilio Balance Low:**
- **Trigger:** Balance < €5.00
- **Action:** Alert via Telegram
- **Monitoring:** n8n sub-workflow checks hourly

**3. SQLite Database Lock:**
- **Symptom:** `SQLITE_BUSY` error
- **Recovery:** 
  ```bash
  # Check for lock files
  ls -la n8n_data/.n8n/*.journal
  ls -la n8n_data/.n8n/*-wal
  
  # Restart n8n container
  docker compose restart n8n
  ```
- **Prevention:** WAL mode enabled, max 1 concurrent write

## 7. Erweiterung für weitere Handwerker

**Aktuelles System:** Ein Handwerker, eine Telefonnummer, alle Kunden.

**Für zusätzliche Handwerker:** Separate Server-Instanz aufsetzen mit eigenen Credentials.

Siehe `README.md` Abschnitt "Multi-Instance Setup".

### Mehrere Kunden ✅

**Funktionsweise:**
- Jeder Anrufer ist ein Kunde.
- Telefonnummer = Eindeutige Kennung.
- Google Sheets speichert unbegrenzt Kunden.
- Call_Log verfolgt alle Interaktionen pro Kunde.
- Wiederkehrende Kunden werden über Telefon-Lookup erkannt.

**Beispiel:**
```
Customer A: +49 171 1234567 (called 3x, opted-in)
Customer B: +49 160 9876543 (called 1x, not opted-in)
Customer C: +1 913 5550123 (called 2x, opted-in)
```

## 9. WhatsApp Template Constraints

### 24-Hour Window Rule

Twilio Business API enforces strict messaging rules:

**Within 24 hours:**
- Free-form messages allowed after customer opt-in
- Direct conversation possible

**After 24 hours:**
- Only pre-approved templates allowed
- No free-form text permitted

**Template Structure:**
```
Template Name: booking_link_v1
Content: "Hi {{1}}, thanks for your interest! 
Here's your booking link: {{2}}
Reply STOP to opt out."
Variables:
  {{1}} = Customer Name
  {{2}} = Booking URL
```

**Template Approval Process:**
1. Create template in Twilio Console
2. Submit for WhatsApp approval
3. Wait 24-48 hours for review
4. Use `TWILIO_WHATSAPP_TEMPLATE_SID` in n8n

### WhatsApp Link Format

**Pre-filled Message Format:**
```
https://wa.me/491711234567?text=Hi%2C%20I%20received%20your%20booking%20link
```

**Components:**
- Base: `https://wa.me/`
- Number: `491711234567` (E.164 without +)
- Query: `?text=` + URL-encoded message

## 10. Data Model

### Google Sheets Struktur

**Sheet 1: Customers (Lead_DB)**
| Column | Description | Example |
|--------|-------------|---------|
| Phone | Primary key (E.164 format) | +491711234567 |
| Name | Kundenname | Hans Müller |
| OptIn_Status | Boolean (TRUE/FALSE) | TRUE |
| Last_Contact | Datum der letzten Interaktion | 2026-02-01 |

**Sheet 2: Call_Log**
| Column | Description | Example |
|--------|-------------|---------|
| Timestamp | Zeitpunkt des Anrufs | 2026-02-01 14:30:00 |
| Phone | Anrufernummer | +491711234567 |
| Status | Ergebnis des Anrufs | Missed / Opted-In |
| Action_Taken | Systemaktion | Sent SMS invite |

## 11. Technical Details

### Phone Number Normalization
Alle eingehenden Nummern werden in das E.164 Format konvertiert:
- **Input-Variationen:** `0171 1234567`, `0049 171 1234567`, `49 171 1234567`
- **Output:** `+491711234567`

### Security Measures
- **Webhook validation:** HMAC-SHA1 Signaturprüfung für alle Twilio-Anfragen.
- **Rate limiting:** 100 Anfragen/Minute via Traefik.
- **TLS only:** Gesamter Traffic wird über HTTPS erzwungen.
- **Credential storage:** API-Keys in `.env` (nie im Code).

### Error Handling
| Failure | Detection | Recovery |
|---------|-----------|----------|
| Webhook timeout | Twilio alert | Fallback auf statisches TwiML |
| Sheets API limit | n8n error (429) | Retry 3x mit exponential backoff |
| Database lock | SQLite error | WAL-Modus aktiviert |

## 12. Onboarding New Craftsmen

### Schritt-für-Schritt Einrichtung

**1. Google Sheets vorbereiten**
- Tabelle mit zwei Reitern erstellen: `Customers` und `Call_Log`.
- Header gemäß Sektion 4 hinzufügen.
- Mit Service-Account-E-Mail teilen.

**2. Twilio konfigurieren**
- Telefonnummer erwerben.
- Webhook-URLs setzen:
  - Voice: `https://your-domain.com/webhook/incoming-call`
  - SMS: `https://your-domain.com/webhook/sms-response`

**3. n8n Workflow einrichten**
- Template-Workflow duplizieren.
- Umgebungsvariablen aktualisieren:
  ```bash
  CRAFTSMAN_NAME="Max Mustermann"
  CRAFTSMAN_PHONE="+491711234567"
  TELEGRAM_CHAT_ID="123456789"
  SPREADSHEET_ID="your-sheet-id"
  TWILIO_ACCOUNT_SID="ACxxxxx"
  TWILIO_AUTH_TOKEN="your-token"
  ```

**4. Telegram konfigurieren**
- Chat mit dem Bot starten.
- Chat-ID via `/start` Befehl abrufen.
- In `.env` als `TELEGRAM_CHAT_ID` eintragen.

**5. Test Flow**
- Twilio-Nummer anrufen.
- Telegram-Alarm prüfen.
- Google Sheets Log-Eintrag prüfen.
- Mit „JA" auf SMS antworten.
- WhatsApp-Zustellung prüfen.



## 8. Daily Operations

### Für den Handwerker

**Passives Monitoring:**
- Erhalt von Telegram-Alarmen für:
  - Jeden verpassten Anruf mit Telefonnummer.
  - Jeden erfolgreichen Opt-In.

**Aktive Nachverfolgung:**
- WhatsApp öffnen, um Kunden mit Opt-In zu kontaktieren.
- Google Sheets prüfen, um Anrufhistorie einzusehen.
- Keine manuelle Dateneingabe erforderlich – alles erfolgt automatisch.

### Für den Administrator

**Monitoring:**
- n8n Dashboard auf Workflow-Fehler prüfen.
- Monatlicher Abgleich Call_Log gegen Twilio-Abrechnung.

**Wartung:**
- `.env` bei Konfigurationsänderungen anpassen.
- Container neu starten: `docker-compose restart`

## 13. Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Orchestration | n8n v1.50.0 | Workflow-Automatisierung |
| Communication | Twilio API | Voice, SMS, WhatsApp |
| Proxy | Traefik v2.11 | SSL, Routing, Rate Limiting |
| Database | SQLite (WAL) | Interner n8n-Status |
| CRM | Google Sheets API | Kundendaten, Logs |
| Notifications | Telegram Bot | Echtzeit-Alarme |
| Deployment | Docker Compose | Container-Orchestrierung |