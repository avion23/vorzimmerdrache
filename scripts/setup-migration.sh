#!/bin/bash
# Quick setup script for PostgreSQL migration

set -e

echo "=== PostgreSQL Migration Quick Setup ==="
echo ""

echo "Step 1: Installing dependencies..."
npm install --silent

echo ""
echo "Step 2: Creating migrations directory..."
mkdir -p migrations

echo ""
echo "Step 3: Creating CRM integration directory..."
mkdir -p integrations/crm

echo ""
echo "Step 4: Verifying schema file exists..."
if [ -f "migrations/002_create_leads_schema.sql" ]; then
  echo "✓ Schema migration file found"
else
  echo "✗ Schema migration file not found"
  exit 1
fi

echo ""
echo "Step 5: Verifying migration script exists..."
if [ -f "scripts/migrate-sheets-to-postgres.js" ]; then
  echo "✓ Migration script found"
else
  echo "✗ Migration script not found"
  exit 1
fi

echo ""
echo "Step 6: Verifying sync service exists..."
if [ -f "integrations/crm/sheets-postgres-sync.js" ]; then
  echo "✓ Sync service found"
else
  echo "✗ Sync service not found"
  exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Ensure your .env file contains:"
echo "   - POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD"
echo "   - GOOGLE_SHEETS_ID and GOOGLE_SERVICE_ACCOUNT_JSON"
echo ""
echo "2. Run the migration:"
echo "   npm run migrate:sheets-to-postgres"
echo ""
echo "3. (Optional) Start sync service during transition:"
echo "   npm run sync:start"
echo ""
echo "4. Update n8n workflows (see docs/n8n-postgres-migration-guide.md)"
echo ""
echo "5. (If needed) Rollback:"
echo "   npm run rollback:to-sheets"
