# Vorzimmerdrache 🐉

## 📋 1GB Ultra-Light Setup

Dies ist die minimale Version für deinen **1GB VPS**. Kein Schnickschnack.

**Was läuft:**
- ⚡ n8n (Workflow-Engine)
- 🌐 Traefik (SSL/HTTPS)
- 📄 SQLite (interne Datenbank in n8n)

**Was WEGGELASSEN:**
- ❌ WAHA (nutze Twilio API)
- ❌ PostgreSQL (zu schwer für 1GB)
- ❌ Redis (nicht nötig ohne Worker)
- ❌ Baserow (Java-Stack frisst RAM)

---

## 🚀 Quick Start (10 Minuten)

### 1. Server vorbereiten

```bash
# SSH auf deinen 1GB VPS
ssh ralf_waldukat@instance1.duckdns.org

# Swap einrichten (Lebensversicherung für 1GB RAM)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 2. Deployen

```bash
# Vom lokalen Rechner aus
cd vorzimmerdrache

# .env konfigurieren
cp .env.example .env
nano .env  # Deine Keys eintragen

# Deployen
./scripts/deploy-1gb.sh
```

### 3. Twilio Setup (einmalig)

**Schritt 1: Twilio Account** [twilio.com/try-twilio](https://twilio.com/try-twilio)
- Kosten: ~€10 Startguthaben
- Du brauchst: Voice + WhatsApp

**Schritt 2: WhatsApp Sender** [Twilio Console](https://console.twilio.com/us1/develop/sms/whatsapp/learn)
- Beantrage "Sender: WhatsApp"
- Business-Verifizierung (Handelsregister/Gewerbeschein)
- Genehmigen Template: "Moin! Bin auf dem Dach. Worum geht's?"
- Wartezeit: 5-20 Tage (WICHTIG!)

**Schritt 3: Nummer kaufen** [Twilio Console](https://console.twilio.com/us1/develop/phone-numbers/manage/incoming)
- Kaufe eine deutsche Nummer (+49...)

---

## 🏗️ Architektur

```
   Kunde ruft an
         │
         ▼
   ┌──────────────────┐
   │ Twilio Voice   │ "Moin! Wir sind auf dem Dach..."
   │ (DE)          │
   └─────┬──────────┘
         │
         ▼
   ┌──────────────────┐
   │ n8n Webhook    │ → Google Sheets API
   │ /webhook/call    │   → Twilio WhatsApp
   │                  │   → Telegram Alert
   └──────────────────┘
         │
         ▼
   Kunde erhält WhatsApp + Du kriegst Telegram
```

**Spezifikation:**
- RAM: ~200MB (n8n) + ~50MB (Traefik) = 250MB
- Swap: 4GB (für Spikes)
- Datenbank: SQLite in n8n (0MB extra)
- SSL: Let's Encrypt via Traefik (kostenlos)

---

## 📊 Kostenrechnung (Realistisch)

| Komponente | Kosten | Notizen |
|------------|-------|----------|
| 1GB VPS | €4.15 | Hetzner CX11 |
| Twilio Voice | €1.50 | 30 Min Dach-Modus @ €0.05/Min |
| Twilio WhatsApp | €0.80 | 100 Templates @ €0.008/Tpl |
| Twilio Nummer | €1.00 | +49-Nummer pro Monat |
| Twilio Startguthaben | €10.00 | Einmalig |
| **GESAMT MONAT 1** | **€16.95** | Ohne Startguthaben |
| Monat 2+ | €6.95 | Nur WhatsApp + Voice + Nummer |

**ROI:**
- Ein verlorener Lead = €1.500-15.000
- 1 Lead retten = System bezahlt sich 88x (Monat 1)
- **Break-even:** 1 Extra-Auftrag alle 1.1 Monate

---

## ⚙️ Konfiguration

### n8n Einstellungen

Nach dem ersten Login:
1. Credentials → Twilio API hinzufügen
2. Credentials → Google Sheets API hinzufügen
3. Workflows importieren: `workflows/roof-mode.json`
4. Testanruf machen

### Google Sheets als "CRM"

**Warum kein PostgreSQL?**
- Postgres = 150MB RAM minimum
- Auf 1GB VPS = OOM-Kill garantiert
- Google Sheets API = 0MB RAM (externer Service)

**Google Sheets Setup:**
1. Neues Sheet: "Leads"
2. Spalten: Timestamp, Phone, Name, Address, Status, Notes
3. Teilen: Share → "Jeder mit Link"
4. API Key: [Google Cloud Console](https://console.cloud.google.com/apis/library)

---

## 🔍 Monitoring

**Spezifisch für 1GB VPS:**

```bash
# RAM check
free -h

# Swap check
swapon --show

# Container check
docker stats

# n8n Logs
docker logs n8n -f --tail 50
```

**Grenzwerte:**
- RAM < 100MB frei: 🔴 Kritisch (OOM droht)
- RAM < 200MB frei: 🟡 Warnung
- RAM >= 200MB frei: 🟢 OK
- Swap > 50% genutzt: 🟡 Aktiv (RAM voll)
- Swap > 80% genutzt: 🔴 Kritisch

---

## 🛠️ Troubleshooting

### Probleme & Lösungen

**Problem: n8n startet nicht**
```bash
docker logs n8n --tail 100
# Prüfe: N8N_ENCRYPTION_KEY korrekt?
# Prüfe: WEBHOOK_URL korrekt?
```

**Problem: Twilio Webhook timeout**
```bash
curl -v https://deine-domain.de/webhook/incoming-call
# Von Lokal aus testen
```

**Problem: RAM geht zur Neige**
```bash
# SQLite-Logs leeren (n8n hat internen Log-Bucket)
docker exec n8n sh -c "rm -rf /home/node/.n8n/logs/*.log"
docker restart n8n
```

---

## 📝 Dateistruktur

```
vorzimmerdrache/
├── docker-compose.yml          # Traefik + n8n (nur 2 Services!)
├── .env.example               # Alle Keys hier
├── scripts/
│   ├── deploy-1gb.sh        # Deployment (ein Befehl!)
│   └── monitor.sh           # RAM/Disk Monitoring
├── workflows/
│   └── roof-mode.json        # Der EINZIGE Workflow
├── tests/
│   └── validation/           # Unit-Tests
└── README.md                # Dieses Dokument
```

---

## 💡 Tipps für 1GB VPS

1. **Swap ist dein Freund:**
   - 4GB Swap ist Pflicht auf 1GB RAM
   - Ohne Swap = OOM-Kill in <10 Min

2. **SQLite ist genial:**
   - 0MB RAM extra
   - Filesystem-Speicher (schnell genug)
   - n8n verwaltet es automatisch

3. **Google Sheets statt DB:**
   - 0MB RAM (externer Service)
   - Du kannst alles per Web ändern
   - Exports als CSV möglich

4. **Keine Worker:**
   - `N8N_EXECUTIONS_MODE=main` (nicht `queue`)
   - Ein Prozess statt 5

5. **Logs regelmäßig löschen:**
   - n8n sammelt Logs automatisch
   - Alle 7 Tage löschen oder RAM ist voll

---

## 📞 Support

- Twilio Support: https://support.twilio.com
- n8n Community: https://community.n8n.io
- Hetzner Support: https://www.hetzner.com/support

---

## 📄 Lizenz

MIT License - siehe LICENSE Datei

---

**Hergestellt für deutsche Solarteure.**
Einfach, schnell, stabil. Auf deinem 1GB VPS.
