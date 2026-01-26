# Additional Scripts

This directory contains helper scripts beyond the main deployment.

## Scripts

### configure-system.sh
Automates initial system configuration without requiring API credentials:
- Fixes SSL_EMAIL to use domain-based email (prevents Let's Encrypt failures)
- Creates automated backup system (retains 7 backups)
- Creates configuration validation script (checks for placeholder values)
- Updates .env.example with real Google Sheets CRM ID

**Usage:**
```bash
./scripts/configure-system.sh
```

**What it configures:**
- ✅ Automated backups (scripts/backup-db.sh)
- ✅ Configuration validation (scripts/validate-env.sh)
- ✅ SSL email for Let's Encrypt
- ✅ Google Sheets CRM integration

**What it CANNOT configure:**
- ❌ API credentials (must be provided by you)
- ❌ n8n credentials (requires Web UI)
- ❌ Workflow activation (requires Web UI)

### backup-db.sh
Automated n8n database backup script (created by configure-system.sh).
Backs up database to `backups/` directory with timestamp.
Keeps only last 7 backups automatically.

**Usage:**
```bash
./scripts/backup-db.sh
```

### validate-env.sh
Validates .env configuration to ensure placeholders are replaced.

**Usage:**
```bash
./scripts/validate-env.sh
```

**What it checks:**
- Twilio Account SID (not placeholder)
- Twilio Auth Token (not placeholder)
- Telegram Bot Token (not placeholder)
- Telegram Chat ID (not placeholder)
- Twilio WhatsApp Template SID (not placeholder)
- SSL Email (not admin@example.com)

### import-workflows.sh
Imports both workflows into n8n via REST API.

**Usage:**
```bash
export N8N_API_KEY=<your-api-key>
./scripts/import-workflows.sh
```

**Note:** Workflows must still be activated via n8n Web UI after import.

### activate-workflows.sh
**NOT CURRENTLY FUNCTIONAL** - n8n sqlite3 module not available in container.
Workflows must be activated manually via n8n Web UI (2 clicks).

**Alternative:**
1. Open https://instance1.duckdns.org
2. Click "Workflows" in sidebar
3. Click "Roof-Mode" workflow
4. Click toggle in top-right corner to activate
5. Click "SMS Opt-In" workflow
6. Click toggle in top-right corner to activate