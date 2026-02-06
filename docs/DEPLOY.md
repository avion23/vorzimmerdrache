# Deployment Guide

## Übersicht

Dieses Projekt unterstützt zwei Deployment-Methoden:
1. **API Deployment** (empfohlen für Workflows)
2. **Rsync** (für Scripts und Dokumentation)

## Voraussetzungen

- SSH-Zugriff auf VPS (`instance1.duckdns.org`)
- n8n API Key (Settings → API → Erstellen)
- `export N8N_API_KEY=n8n_api_xxxxx`

## Schnellstart

```bash
# 1. Umgebungsvariablen setzen
export N8N_API_KEY="n8n_api_xxxxxxxx"
export VPS_HOST="root@instance1.duckdns.org"

# 2. Alles deployen
./scripts/sync-to-vps.sh   # Scripts + Docs
./scripts/deploy.sh        # Workflows via API
```

## Detaillierte Anleitung

### 1. Rsync (Scripts & Docs)

```bash
./scripts/sync-to-vps.sh
```

Das synchronisiert:
- `scripts/` → VPS:/opt/vorzimmerdrache/scripts/
- `docs/` → VPS:/opt/vorzimmerdrache/docs/
- `workflows/` → VPS:/opt/vorzimmerdrache/workflows-backup/ (nur Backup)

### 2. API Deployment (Workflows)

```bash
./scripts/deploy.sh [environment]
```

Importiert alle `.json` Workflows aus `workflows/` in n8n.

**Wichtig:** n8n speichert Workflows in der Datenbank (SQLite), 
deshalb nutzen wir die API, nicht rsync.

### 3. Manuelles UI Deployment (Fallback)

Falls API nicht funktioniert:

1. n8n UI öffnen: https://instance1.duckdns.org
2. Workflows → Import from File
3. `workflows/sms-opt-in.json` auswählen
4. Speichern & Aktivieren
5. Webhook URL prüfen: `/webhook/sms-response`

## 3-Question Flow Setup

Nach Deployment:

1. **.env aktualisieren** auf VPS:
```bash
ENABLE_3_QUESTION_FLOW=true
```

2. **Google Sheets Spalten** hinzufügen:
   - `conversation_state`
   - `plz`
   - `kwh_consumption`
   - `meter_photo_url`
   - `qualification_timestamp`
   - `last_state_change`

3. **Timeout Handler** aktivieren:
   - Workflows → timeout-handler.json importieren
   - Aktivieren (läuft automatisch stündlich)

4. **Testen**:
```bash
curl -X POST https://instance1.duckdns.org/webhook/sms-response \
  -d "From=+491711234567" \
  -d "Body=JA"
```

## Fehlerbehebung

**API Key ungültig:**
```bash
# Neuen Key in n8n UI erstellen
curl https://instance1.duckdns.org/api/v1/workflows \
  -H "X-N8N-API-KEY: $N8N_API_KEY"
```

**Workflow existiert bereits:**
- In n8n UI vorher löschen, oder
- API Update statt Create verwenden (Skript anpassen)

**Rsync Permission denied:**
```bash
ssh-copy-id root@instance1.duckdns.org
```
