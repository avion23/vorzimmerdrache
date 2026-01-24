# Status Communication Flow

## Overview
Automated customer communication system triggered by CRM status changes in Google Sheets. Primary channel: WhatsApp (Waha), Fallback: SMS (Twilio).

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           STATUS LOOP WORKFLOW                               │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐
│  Schedule    │  Every 5 minutes
│  Trigger     │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Get CRM     │  Read Google Sheets CRM sheet
│  Data        │  All rows (A:Z)
└──────┬───────┘
       │
       ▼
┌──────────────┐      ┌──────────────────┐
│ Check Status │──────│   Status has     │
│   Changed    │      │   changed?       │
└──────┬───────┘      └──────────────────┘
       │                     │ Yes
       ▼                     ▼
┌──────────────┐      ┌──────────────┐
│   Ignore     │      │ Check Opt-Out│
│   (no change)│      │  (opt_out != │
└──────────────┘      │   true)      │
                      └──────┬───────┘
                             │ Yes
                             ▼
                     ┌──────────────┐
                     │   Prepare    │  Load template from
                     │   Message    │  status-templates.json
                     │              │  Replace placeholders
                     └──────┬───────┘
                            │
                            ▼
                     ┌──────────────┐
                     │  Apply Delay │  Template delay_seconds
                     │              │  (default: 10 min)
                     └──────┬───────┘
                            │
                            ▼
                     ┌──────────────┐
                     │   Check      │  Has phone number?
                     │ Has Phone?   │
                     └──────┬───────┘
                            │ Yes
                            ▼
                     ┌──────────────┐
                     │   Send       │  WhatsApp via Waha
                     │  WhatsApp    │  API endpoint
                     └──────┬───────┘
                            │
                            ▼
                     ┌──────────────┐
                     │   Check      │  Error in response?
                     │    Error?    │
                     └──────┬───────┘
                     /             \
                 No/               \Yes
                  /                 \
                 ▼                   ▼
         ┌──────────────┐    ┌──────────────┐
         │   Update     │    │   Send SMS   │
         │  Last Sent   │    │   Fallback   │  Twilio API
         │  (row)       │    └──────┬───────┘
         └──────┬───────┘           │
                │                   ▼
                │           ┌──────────────┐
                └──────────▶│   Update     │
                            │  Last Sent   │
                            │  (row)       │
                            └──────┬───────┘
                                   │
                                   ▼
                            ┌──────────────┐
                            │   Log        │  Track sent messages
                            │   Message    │  (phone, status, time)
                            └──────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                         OPT-OUT HANDLING FLOW                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐
│  Incoming    │  Webhook from Waha
│  Message     │  (customer replies)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Check       │  Message == "STOP" ||
│  Opt-Out     │  "abbrechen" || "abmelden"
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Process     │  Found STOP keyword
│  Opt-Out     │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Mark Opted  │  Update CRM sheet:
│   Out        │  opt_out = true
│              │  opt_out_date = timestamp
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Send        │  WhatsApp confirmation:
│  Confirmation│  "Du wurdest von der
│              │   Nachrichtenliste entfernt"
└──────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                        STATUS MESSAGE MAPPING                                │
└─────────────────────────────────────────────────────────────────────────────┘

Status        │ Delay  │ Message Template                    │ Variables
──────────────┼────────┼─────────────────────────────────────┼─────────────────────────────
Received      │ 0s     │ Danke für Anfrage, melden uns bald │ {name}
Qualified     │ 5m     │ Wir melden uns für Termin          │ {name}
Termin        │ 10m    │ Termin bestätigt am [date] [time]  │ {name}, {date}, {time}, {address}
Angebot       │ 15m    │ Angebot fertig, Link: [url]        │ {name}, {link}
Bestellt      │ 10m    │ Material bestellt, Lieferung KW[X] │ {name}, {week}
Installation  │ 10m    │ Installation geplant am [date]     │ {name}, {date}, {time_start}, {time_end}
Abgeschlossen │ 30m    │ Danke! Bewerte uns hier: [link]    │ {name}, {review_link}


┌─────────────────────────────────────────────────────────────────────────────┐
│                        CONFIGURATION ENV VARS                                │
└─────────────────────────────────────────────────────────────────────────────┘

Google Sheets:
- GOOGLE_SHEET_ID          CRM spreadsheet ID
- GOOGLE_CREDENTIALS_ID    n8n Google API credentials ID

WhatsApp (Waha):
- WAHA_URL                 Waha server URL (e.g., http://localhost:3000)
- WAHA_API_KEY             Waha API key
- WAHA_AUTH_ID             n8n header auth credential ID

SMS (Twilio):
- TWILIO_API_URL           Twilio API base URL
- TWILIO_ACCOUNT_SID       Twilio Account SID
- TWILIO_PHONE_NUMBER      Twilio sender number
- TWILIO_CREDENTIALS_ID    n8n Twilio credentials ID

General:
- WEBHOOK_ID               Webhook ID for incoming messages


┌─────────────────────────────────────────────────────────────────────────────┐
│                           CRM SHEET COLUMNS                                  │
└─────────────────────────────────────────────────────────────────────────────┘

Required columns:
- id / customer_id         Unique identifier
- name / customer_name     Customer name
- phone / telephone        Phone number (international format)
- status                   Current status (Received, Qualified, etc.)
- previous_status          Previous status (for comparison)
- opt_out                  Boolean flag (true/false)
- opt_out_date             Timestamp when opted out
- last_sent                Last message sent timestamp
- last_sent_status         Last status that triggered message

Optional columns (used in templates):
- date                     Appointment/Installation date
- time                     Appointment time
- time_start               Installation window start
- time_end                 Installation window end
- address                  Appointment address
- link                     Offer/Quote link
- week                     Delivery calendar week
- review_link              Review page link


┌─────────────────────────────────────────────────────────────────────────────┐
│                        ERROR HANDLING                                        │
└─────────────────────────────────────────────────────────────────────────────┘

1. WhatsApp send fails → Retry via SMS fallback
2. Missing template data → Use simplified message
3. Missing phone number → Skip customer, log warning
4. Google Sheets API error → Continue to next row
5. Template load error → Use default "Received" template


┌─────────────────────────────────────────────────────────────────────────────┐
│                           TESTING CHECKLIST                                   │
└─────────────────────────────────────────────────────────────────────────────┘

□ Schedule trigger activates every 5 minutes
□ Status change detection works (previous vs current)
□ Message templates load correctly from config
□ Placeholders are replaced with customer data
□ Delay is applied before sending
□ WhatsApp message sent successfully
□ SMS fallback triggers on WhatsApp error
□ Opt-out works with "STOP" keyword
□ CRM sheet updated with opt_out flag
□ Confirmation message sent after opt-out
□ Message logging captures all sends
□ Phone number format handling works