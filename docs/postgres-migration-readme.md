# PostgreSQL Migration for CRM Leads

Complete migration toolkit for moving from Google Sheets to PostgreSQL database.

## Files Overview

### SQL Migration
- `migrations/002_create_leads_schema.sql` - PostgreSQL table schema with indexes, triggers, and GDPR compliance

### Scripts
- `scripts/migrate-sheets-to-postgres.js` - One-time migration script
- `scripts/rollback-to-sheets.sh` - Rollback script (PostgreSQL → Google Sheets)

### Services
- `integrations/crm/sheets-postgres-sync.js` - Bidirectional sync service

### Documentation
- `docs/n8n-postgres-migration-guide.md` - n8n workflow conversion guide

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

Ensure `.env` contains:
```
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=your_password

GOOGLE_SHEETS_ID=your_sheet_id
GOOGLE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
```

### 3. Run Migration

```bash
npm run migrate:sheets-to-postgres
```

### 4. Start Sync Service (Optional)

For transition period - syncs between Sheets and PostgreSQL:

```bash
npm run sync:start
```

Or run sync once:
```bash
npm run sync:once
```

### 5. Rollback (if needed)

```bash
npm run rollback:to-sheets
```

## Schema Features

### Columns

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key, auto-generated |
| created_at | TIMESTAMPTZ | Creation timestamp |
| updated_at | TIMESTAMPTZ | Last update timestamp (auto) |
| name | VARCHAR(255) | Lead name (required) |
| phone | VARCHAR(20) | E.164 format, unique |
| email | VARCHAR(255) | Email address |
| address_* | Various | Normalized address fields |
| latitude/longitude | DECIMAL | Geocoded coordinates |
| status | VARCHAR(50) | Lead status (new, qualified, contacted, etc.) |
| priority | INTEGER | 0=normal, 1=high, 2=urgent |
| opted_in/out | BOOLEAN | Consent flags |
| roof_area_sqm | INTEGER | Solar roof area |
| estimated_kwp | DECIMAL(5,2) | Estimated kilowatt-peak |
| source | VARCHAR(100) | Lead source |
| gdpr_delete_at | TIMESTAMPTZ | Auto-delete timestamp |

### Indexes

- Primary: `id` (UUID)
- Unique: `phone`
- Performance: `status`, `created_at DESC`
- Optional: `email`, `gdpr_delete_at`

### Triggers

- `update_leads_updated_at` - Auto-updates `updated_at` on row modification

## Migration Process

The migration script:

1. Creates PostgreSQL backup before migration
2. Reads all rows from Google Sheets
3. Normalizes phone numbers to E.164 format
4. Parses addresses into structured fields
5. Inserts into PostgreSQL with conflict handling (ON CONFLICT DO NOTHING)
6. Verifies row counts match
7. Reports summary statistics

## Sync Service

The bidirectional sync service:

- Runs on cron schedule (default: every 5 minutes)
- **Sheets → PostgreSQL**: Reads new/updated rows, inserts/updates in PostgreSQL
- **PostgreSQL → Sheets**: Pushes updates from PostgreSQL back to Sheets
- Preserves data integrity during transition

## GDPR Compliance

### Features

- Phone numbers stored as E.164 (no personal identifiers in format)
- `gdpr_delete_at` column for auto-deletion scheduling
- `opted_out` and `opted_in` consent flags
- Index on `gdpr_delete_at` for efficient cleanup queries

### Queries

**Mark for deletion (12 months):**
```sql
UPDATE leads
SET opted_out = TRUE,
    gdpr_delete_at = NOW() + INTERVAL '12 months'
WHERE phone = $1
```

**Find leads pending deletion:**
```sql
SELECT * FROM leads WHERE gdpr_delete_at <= NOW()
```

**Delete expired leads:**
```sql
DELETE FROM leads WHERE gdpr_delete_at <= NOW()
```

## n8n Integration

After migration, update n8n workflows:

1. Add PostgreSQL credentials in n8n
2. Replace "Google Sheets" nodes with "PostgreSQL" nodes
3. Update queries for new schema

See `docs/n8n-postgres-migration-guide.md` for detailed instructions with before/after examples.

## Testing

### Verify Migration

```bash
docker exec -it <postgres_container> psql -U n8n -d n8n
```

```sql
SELECT COUNT(*) FROM leads;
SELECT status, COUNT(*) FROM leads GROUP BY status;
SELECT * FROM leads ORDER BY created_at DESC LIMIT 5;
```

### Test Sync

```bash
npm run sync:once
```

Check logs for:
- Imported new leads count
- Synced existing leads count
- Any errors

## Troubleshooting

### Connection Errors

- Verify PostgreSQL is running: `docker ps | grep postgres`
- Check credentials in `.env`
- Test connection: `psql -h localhost -U n8n -d n8n`

### Phone Normalization

Invalid phone numbers are skipped. Check skipped count in migration output.

### Google Sheets API Errors

- Verify `GOOGLE_SERVICE_ACCOUNT_JSON` is valid
- Ensure service account has edit access to the sheet
- Check `GOOGLE_SHEETS_ID` matches your sheet

### Sync Conflicts

The sync uses PostgreSQL as source of truth. Manual changes in Sheets will be overwritten by PostgreSQL updates.

## Rollback

If migration fails or you need to revert:

```bash
npm run rollback:to-sheets
```

This will:
1. Export PostgreSQL to CSV
2. Import CSV to Google Sheets
3. Provide instructions to restore n8n workflows
4. Keep backups of all data

## Next Steps After Migration

1. Update all n8n workflows to use PostgreSQL
2. Stop the sync service: `pkill -f sheets-postgres-sync`
3. Test all workflows with PostgreSQL backend
4. Remove Google Sheets dependencies (optional)
5. Set up automated GDPR deletion job (cron)
6. Configure database backups
