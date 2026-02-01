# n8n Workflow Recreation Solution

## Current State Analysis

**From Database Check:**
- Workflows: Only 2 "Timeout Handler" workflows exist (duplicates)
- Webhooks: Empty (no entries in webhook_entity)
- Credentials: Empty (no entries in credentials_entity)

## Solution Overview

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Create Credentials (via n8n UI - REQUIRED)               │
│    - Google Sheets OAuth2 API                               │
│    - Twilio API                                             │
├─────────────────────────────────────────────────────────────┤
│ 2. Import Workflows (via API)                               │
│    - sms-working.json  → SMS Opt-In - Working               │
│    - roof-mode-simple.json → Roof-Mode                      │
├─────────────────────────────────────────────────────────────┤
│ 3. Activate Workflows (via API)                             │
│    - PATCH /workflows/{id} with {"active": true}            │
├─────────────────────────────────────────────────────────────┤
│ 4. Verify Webhook Registration                              │
│    - Check webhook_entity table                             │
├─────────────────────────────────────────────────────────────┤
│ 5. Test Webhooks                                            │
│    - POST to /webhook/sms-response                          │
│    - POST to /webhook/incoming-call                         │
└─────────────────────────────────────────────────────────────┘
```

## Step 1: Create Credentials (UI Required)

**CRITICAL:** n8n API cannot create encrypted credentials. Use UI:

1. Login: https://instance1.duckdns.org
2. Go to Credentials → Add Credential

### Google Sheets
- Type: `Google Sheets OAuth2 API`
- Name: `Google Sheets account` (must match workflow reference)
- OAuth2 flow required

### Twilio
- Type: `Twilio API`
- Name: `Twilio API` (must match workflow reference)
- Account SID: `AC...` (from your Twilio console)
- Auth Token: `...` (from your Twilio console)

## Step 2: Import & Activate Workflows

```bash
# Set API key from n8n UI (Settings → API → Create API Key)
export N8N_API_KEY=<your-api-key>

# Run recreation script
./scripts/recreate-workflows.sh
```

## Step 3: Verify

```bash
./scripts/verify-workflows.sh
```

Expected output:
```
Active workflows:
  SMS Opt-In - Working (xxx-xxx-xxx)
  Roof-Mode (xxx-xxx-xxx)

Webhooks:
  sms-response|POST
  incoming-call|POST
```

## Step 4: Test Webhooks

```bash
./scripts/test-webhooks.sh
```

## Twilio Configuration

Update Twilio phone number (+19135654323) webhooks:

| Type | URL |
|------|-----|
| Voice | https://instance1.duckdns.org/webhook/incoming-call |
| SMS | https://instance1.duckdns.org/webhook/sms-response |

## Manual SQL Verification

```bash
# List workflows
ssh ralf_waldukat@instance1.duckdns.org \
  "sudo sqlite3 /var/lib/docker/volumes/vorzimmerdrache_n8n_data/_data/database.sqlite \
  'SELECT id, name, active FROM workflow_entity;'"

# List webhooks
ssh ralf_waldukat@instance1.duckdns.org \
  "sudo sqlite3 /var/lib/docker/volumes/vorzimmerdrache_n8n_data/_data/database.sqlite \
  'SELECT workflowId, webhookPath, method FROM webhook_entity;'"

# List credentials
ssh ralf_waldukat@instance1.duckdns.org \
  "sudo sqlite3 /var/lib/docker/volumes/vorzimmerdrache_n8n_data/_data/database.sqlite \
  'SELECT id, name, type FROM credentials_entity;'"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Import succeeds but workflows fail | Credentials missing or wrong name |
| Webhook returns 404 | Workflow not active |
| Webhook returns 500 | Check execution logs in n8n UI |
| Credentials error | Recreate via UI with exact names |

## Workflow JSON Files

| File | Workflow | Webhook Path | Nodes |
|------|----------|--------------|-------|
| `sms-working.json` | SMS Opt-In - Working | sms-response | Webhook, Code, IF, Google Sheets, Twilio, Respond |
| `roof-mode-simple.json` | Roof-Mode | incoming-call | Webhook, Code, Google Sheets, Twilio, Respond |
