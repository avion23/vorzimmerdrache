# Baserow Integration for CRM

Self-hosted Airtable alternative for lead management with bidirectional sync to PostgreSQL.

## Features

- **Kanban Board**: Visual pipeline management with drag-and-drop
- **Calendar View**: Schedule meetings and appointments
- **Map View**: Geographic lead distribution
- **Grid View**: Full-featured table view
- **Bidirectional Sync**: PostgreSQL ↔ Baserow every 5 minutes
- **Webhook Integration**: Real-time updates via n8n
- **WhatsApp Attachments**: Media from WhatsApp linked to leads
- **Status Automation**: Actions triggered on status changes

## Quick Start

### 1. Setup Baserow

```bash
chmod +x scripts/setup-baserow.sh
./scripts/setup-baserow.sh --email admin@example.com --password yourpassword
```

This will:
- Add Baserow to docker-compose.yml
- Generate JWT signing key
- Create admin user
- Set up Leads database and table
- Configure fields matching PostgreSQL schema
- Generate API token
- Configure webhook to n8n
- Set up Kanban and Calendar views

### 2. Start Services

```bash
docker-compose up -d baserow
```

### 3. Access Baserow

- URL: `https://baserow.yourdomain.com`
- Login with credentials from setup

### 4. Start Sync Daemon

```bash
npm run sync:baserow:daemon
```

Or run once:
```bash
npm run sync:baserow:once
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `BASEROW_HOST` | Baserow domain | Yes |
| `BASEROW_PUBLIC_URL` | Full Baserow URL | Yes |
| `BASEROW_JWT_SIGNING_KEY` | JWT secret key | Auto-generated |
| `BASEROW_API_TOKEN` | API token for sync | Auto-generated |
| `BASEROW_TABLE_ID` | Leads table ID | Auto-discovered |

### Sync Settings

Edit `integrations/crm/baserow-sync.js`:

```javascript
// Change sync interval (default: 5 minutes)
sync.startCron(10); // Sync every 10 minutes
```

## Field Mapping

| PostgreSQL | Baserow | Type |
|-----------|---------|------|
| `id` | ID | Text (Primary) |
| `created_at` | Created At | Date |
| `name` | Name | Text |
| `phone` | Phone | Text |
| `email` | Email | Text |
| `address_raw` | Address | Text |
| `address_city` | City | Text |
| `address_postal_code` | Postal Code | Text |
| `address_state` | State | Text |
| `latitude` | Latitude | Number |
| `longitude` | Longitude | Number |
| `status` | Status | Single Select |
| `priority` | Priority | Number |
| `opted_in` | Opted In | Boolean |
| `opted_out` | Opted Out | Boolean |
| `roof_area_sqm` | Roof Area (sqm) | Number |
| `estimated_kwp` | Estimated kWp | Number |
| `estimated_annual_kwh` | Estimated Annual kWh | Number |
| `subsidy_eligible` | Subsidy Eligible | Boolean |
| `source` | Source | Text |
| `notes` | Notes | Long Text |
| `assigned_to` | Assigned To | Text |
| `meeting_date` | Meeting Date | Date |
| `attachments` | Attachments | File |

## Views

### Kanban Board (Lead Pipeline)

Status columns:
- New (blue)
- Qualified (green)
- Contacted (orange)
- Meeting (purple)
- Offer (cyan)
- Won (dark-green)
- Lost (red)

### Calendar View (Termine)

Shows meetings scheduled in `Meeting Date` field, grouped by `Assigned To`.

### Map View (Lead Karte)

Geographic visualization using `Latitude` and `Longitude` fields.

### Grid View (All Leads)

Complete table view with all fields.

## Webhook Workflow

The n8n webhook (`workflows/baserow-webhook.json`) handles:

1. **Validate** webhook events (created, updated, deleted)
2. **Transform** Baserow data to PostgreSQL format
3. **Insert/Update** leads in PostgreSQL
4. **Detect** status changes
5. **Notify** installer via SMS on status change
6. **Send** WhatsApp message when lead is won

## Conflict Resolution

PostgreSQL is the source of truth:

- If `updated_at` in PostgreSQL > Baserow `created_at`, skip Baserow update
- Always sync PostgreSQL → Baserow on any change
- Baserow → PostgreSQL only if newer

## WhatsApp Attachments

To attach WhatsApp media to leads:

```javascript
const sync = require('./integrations/crm/baserow-sync');
const baserowSync = new sync.BaserowSync();

await baserowSync.connect();
await baserowSync.handleWhatsAppAttachment(rowId, attachmentUrl);
```

## API Usage

### Direct API Calls

```javascript
const response = await axios.get(
  `${baserowUrl}/api/database/rows/table/${tableId}/`,
  { headers: { Authorization: `Token ${apiToken}` } }
);
```

### Create Lead

```javascript
await axios.post(
  `${baserowUrl}/api/database/rows/table/${tableId}/`,
  { Name: 'John Doe', Phone: '+49123456789', Status: 'new' },
  { headers: { Authorization: `Token ${apiToken}` } }
);
```

### Update Lead

```javascript
await axios.patch(
  `${baserowUrl}/api/database/rows/table/${tableId}/${rowId}/`,
  { Status: 'qualified' },
  { headers: { Authorization: `Token ${apiToken}` } }
);
```

## Troubleshooting

### Sync not running

Check logs:
```bash
npm run sync:baserow:once
```

### Baserow not accessible

Check container status:
```bash
docker-compose ps baserow
docker-compose logs baserow
```

### Webhook failing

Check n8n execution logs for webhook errors.

### Connection refused

Ensure BASEROW_HOST and BASEROW_PUBLIC_URL are correct in `.env`.

## Backup

Baserow data is stored in PostgreSQL (shared with n8n) and backed up via the backup service.

## Security

- API tokens should be rotated periodically
- Webhook URLs are only accessible from internal network
- JWT signing key should be kept secret
- Enable HTTPS via Traefik

## Performance

- Sync runs in batches of 50 records
- 500ms delay between batches to avoid rate limiting
- Uses connection pooling for PostgreSQL

## Customization

### Add Custom Views

Edit `config/baserow-views.json` and re-import via Baserow UI.

### Change Field Order

Modify `field_options` in view configuration.

### Add Custom Webhook Triggers

Edit `workflows/baserow-webhook.json` in n8n.

## Maintenance

### Restart Sync

```bash
# Stop sync
pkill -f baserow-sync

# Start again
npm run sync:baserow:daemon
```

### Recreate API Token

Delete token in Baserow UI and run setup script again.

### Reset Baserow

```bash
docker-compose down -v baserow
./scripts/setup-baserow.sh --email admin@example.com --password newpassword
```

## Support

For issues:
1. Check logs: `docker-compose logs baserow`
2. Check sync logs: `npm run sync:baserow:once`
3. Verify environment variables: `./scripts/validate-env.sh`
