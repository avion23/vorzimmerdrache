# n8n Workflow Migration Guide: Google Sheets → PostgreSQL

This guide explains how to update existing n8n workflows to use PostgreSQL instead of Google Sheets.

## Prerequisites

Ensure PostgreSQL node credentials are configured in n8n:
1. Go to n8n → Credentials → Add Credential
2. Select "Postgres"
3. Configure with your PostgreSQL connection details from `.env`

## Node Replacement Patterns

### 1. Reading Leads

**Before (Google Sheets):**
```json
{
  "name": "Get Leads from Sheet",
  "type": "n8n-nodes-base.googleSheets",
  "typeVersion": 4,
  "parameters": {
    "operation": "getAll",
    "sheetId": "{{ $env.GOOGLE_SHEETS_ID }}"
  }
}
```

**After (PostgreSQL):**
```json
{
  "name": "Get Leads",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2,
  "parameters": {
    "operation": "executeQuery",
    "query": "SELECT * FROM leads WHERE status = $1 ORDER BY created_at DESC",
    "options": {}
  },
  "position": [250, 300]
}
```

### 2. Create New Lead

**Before (Google Sheets):**
```json
{
  "name": "Add Lead to Sheet",
  "type": "n8n-nodes-base.googleSheets",
  "typeVersion": 4,
  "parameters": {
    "operation": "append",
    "sheetId": "{{ $env.GOOGLE_SHEETS_ID }}",
    "columns": {
      "mappingMode": "defineBelow",
      "value": {
        "timestamp": "={{ $now.toISO() }}",
        "name": "={{ $json.name }}",
        "phone": "={{ $json.phone }}",
        "email": "={{ $json.email }}",
        "address": "={{ $json.address }}",
        "status": "new",
        "notes": "={{ $json.notes }}"
      }
    }
  }
}
```

**After (PostgreSQL):**
```json
{
  "name": "Create Lead",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2,
  "parameters": {
    "operation": "insert",
    "table": "leads",
    "columns": "name,phone,email,address_raw,status,notes,source,opted_in",
    "data": "={{ JSON.stringify([$json.name, $json.phone, $json.email, $json.address, 'new', $json.notes, 'website', false]) }}"
  }
}
```

Or using parameters:
```json
{
  "name": "Create Lead",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2,
  "parameters": {
    "operation": "executeQuery",
    "query": "INSERT INTO leads (name, phone, email, address_raw, status, notes, source, opted_in) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *",
    "parameters": {
      "parameters": [
        { "name": "name", "value": "={{ $json.name }}" },
        { "name": "phone", "value": "={{ $json.phone }}" },
        { "name": "email", "value": "={{ $json.email }}" },
        { "name": "address", "value": "={{ $json.address }}" },
        { "name": "status", "value": "new" },
        { "name": "notes", "value": "={{ $json.notes }}" },
        { "name": "source", "value": "website" },
        { "name": "opted_in", "value": "false" }
      ]
    }
  }
}
```

### 3. Update Lead Status

**Before (Google Sheets):**
```json
{
  "name": "Update Lead Status",
  "type": "n8n-nodes-base.googleSheets",
  "typeVersion": 4,
  "parameters": {
    "operation": "update",
    "sheetId": "{{ $env.GOOGLE_SHEETS_ID }}",
    "lookupColumn": "phone",
    "lookupValue": "={{ $json.phone }}",
    "values": {
      "status": "={{ $json.newStatus }}"
    }
  }
}
```

**After (PostgreSQL):**
```json
{
  "name": "Update Lead Status",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2,
  "parameters": {
    "operation": "executeQuery",
    "query": "UPDATE leads SET status = $1, updated_at = NOW() WHERE phone = $2 RETURNING *",
    "parameters": {
      "parameters": [
        { "name": "status", "value": "={{ $json.newStatus }}" },
        { "name": "phone", "value": "={{ $json.phone }}" }
      ]
    }
  }
}
```

### 4. Check for Duplicates

**Before (Google Sheets):**
```json
{
  "name": "Check Duplicate",
  "type": "n8n-nodes-base.googleSheets",
  "typeVersion": 4,
  "parameters": {
    "operation": "lookup",
    "sheetId": "{{ $env.GOOGLE_SHEETS_ID }}",
    "lookupColumn": "phone",
    "lookupValue": "={{ $json.phone }}"
  }
}
```

**After (PostgreSQL):**
```json
{
  "name": "Check for Existing Lead",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2,
  "parameters": {
    "operation": "executeQuery",
    "query": "SELECT * FROM leads WHERE phone = $1 LIMIT 1",
    "parameters": {
      "parameters": [
        { "name": "phone", "value": "={{ $json.phone }}" }
      ]
    }
  }
}
```

### 5. Get Leads by Status

**Before (Google Sheets):**
```json
{
  "name": "Filter by Status",
  "type": "n8n-nodes-base.googleSheets",
  "typeVersion": 4,
  "parameters": {
    "operation": "getAll",
    "sheetId": "{{ $env.GOOGLE_SHEETS_ID }}"
  }
}
// + IF node to filter by status
```

**After (PostgreSQL):**
```json
{
  "name": "Get Qualified Leads",
  "type": "n8n-nodes-base.postgres",
  "typeVersion": 2,
  "parameters": {
    "operation": "executeQuery",
    "query": "SELECT * FROM leads WHERE status = $1 AND opted_out = FALSE ORDER BY created_at DESC LIMIT 100",
    "parameters": {
      "parameters": [
        { "name": "status", "value": "qualified" }
      ]
    }
  }
}
```

## Common Query Patterns

### Enrich Lead with Geocoding Data
```sql
UPDATE leads
SET address_street = $1,
    address_city = $2,
    address_postal_code = $3,
    latitude = $4,
    longitude = $5
WHERE id = $6
RETURNING *
```

### Add Solar Estimates
```sql
UPDATE leads
SET roof_area_sqm = $1,
    estimated_kwp = $2,
    estimated_annual_kwh = $3,
    subsidy_eligible = $4
WHERE id = $5
RETURNING *
```

### GDPR: Mark for Deletion
```sql
UPDATE leads
SET opted_out = TRUE,
    opted_out_at = NOW(),
    gdpr_delete_at = NOW() + INTERVAL '12 months'
WHERE phone = $1
```

### GDPR: Get Leads Pending Deletion
```sql
SELECT * FROM leads
WHERE gdpr_delete_at <= NOW()
  AND gdpr_delete_at IS NOT NULL
```

### Get Leads for Installer Assignment
```sql
SELECT * FROM leads
WHERE status IN ('qualified', 'contacted')
  AND opted_out = FALSE
  AND assigned_to IS NULL
ORDER BY
  CASE priority
    WHEN 2 THEN 1
    WHEN 1 THEN 2
    ELSE 3
  END,
  created_at ASC
LIMIT 50
```

## Migration Checklist

- [ ] Create PostgreSQL credentials in n8n
- [ ] Replace all "Google Sheets" nodes with "PostgreSQL" nodes
- [ ] Update queries to use new schema (address_raw, status enum, etc.)
- [ ] Test each workflow after conversion
- [ ] Update webhook/form submissions to write to PostgreSQL
- [ ] Remove Google Sheets nodes after verification
- [ ] Archive old Google Sheet workflows as backup

## Workflow Files to Update

Based on your project structure, these workflows likely need updating:

1. `workflows/speed-to-lead-main.json` - Lead entry point
2. `workflows/inbound-handler.json` - Form/webhook processing
3. `workflows/installer-notification.json` - Status updates
4. `workflows/enrichment-subflow.json` - Geocoding/solar data
5. `workflows/status-loop.json` - Status transitions

## Testing Approach

1. **Dry Run**: Test workflows with sample data without affecting production
2. **Parallel Run**: Run both Sheets and PostgreSQL nodes temporarily to verify
3. **Gradual Rollout**: Convert one workflow at a time
4. **Monitor**: Check PostgreSQL data integrity after each workflow conversion
