#!/bin/bash
set -e

echo "=== PostgreSQL → Google Sheets Rollback Script ==="
echo "This script exports PostgreSQL data to Google Sheets"
echo "WARNING: This will overwrite Google Sheets data!"
echo ""

read -p "Are you sure? (type 'yes' to continue): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Rollback cancelled."
  exit 1
fi

export $(grep -v '^#' .env | xargs)

BACKUP_DIR="backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/postgres-export-$TIMESTAMP.csv"

mkdir -p "$BACKUP_DIR"

echo "Step 1: Exporting PostgreSQL to CSV..."
PGPASSWORD=$POSTGRES_PASSWORD psql \
  -h "${POSTGRES_HOST:-localhost}" \
  -p "${POSTGRES_PORT:-5432}" \
  -U "${POSTGRES_USER:-n8n}" \
  -d "${POSTGRES_DB:-n8n}" \
  -c "COPY (
    SELECT
      COALESCE(created_at::text, '') as timestamp,
      name,
      phone,
      COALESCE(email, '') as email,
      COALESCE(address_raw, '') as address,
      status,
      COALESCE(notes, '') as notes
    FROM leads
    ORDER BY created_at
  ) TO STDOUT WITH CSV HEADER DELIMITER ','" > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
  echo "Error: Export file is empty or was not created."
  exit 1
fi

ROWS=$(wc -l < "$BACKUP_FILE")
echo "Exported $ROWS rows to $BACKUP_FILE"

echo ""
echo "Step 2: Preparing Google Sheets import..."

TEMP_DIR=$(mktemp -d)
CLEANED_CSV="$TEMP_DIR/leads_clean.csv"

head -n 1 "$BACKUP_FILE" > "$CLEANED_CSV"
tail -n +2 "$BACKUP_FILE" >> "$CLEANED_CSV"

echo "CSV prepared at: $CLEANED_CSV"

echo ""
echo "Step 3: Creating Node.js import script..."

IMPORT_SCRIPT="$TEMP_DIR/import-to-sheets.js"
cat > "$IMPORT_SCRIPT" << 'EOFSCRIPT'
const { GoogleSpreadsheet } = require('google-spreadsheet');
const fs = require('fs');
const csv = require('csv-parser');

require('dotenv').config();

async function importToSheets(csvFile) {
  const doc = new GoogleSpreadsheet(process.env.GOOGLE_SHEETS_ID);

  const creds = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
  await doc.useServiceAccountAuth(creds);
  await doc.loadInfo();

  const sheet = doc.sheetsByIndex[0];

  console.log(`Connected to sheet: ${doc.title}`);

  const rows = await parseCSV(csvFile);
  console.log(`Read ${rows.length} rows from CSV`);

  const batchSize = 50;
  let processed = 0;

  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);

    const rowData = batch.map(row => ({
      timestamp: row.timestamp || '',
      name: row.name || '',
      phone: row.phone || '',
      email: row.email || '',
      address: row.address || '',
      status: row.status || 'new',
      notes: row.notes || ''
    }));

    await sheet.addRows(rowData);
    processed += batch.length;

    console.log(`Imported ${processed} / ${rows.length} rows`);

    if (i + batchSize < rows.length) {
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }

  console.log('Import completed!');
}

function parseCSV(file) {
  return new Promise((resolve, reject) => {
    const results = [];
    fs.createReadStream(file)
      .pipe(csv())
      .on('data', (data) => results.push(data))
      .on('end', () => resolve(results))
      .on('error', (error) => reject(error));
  });
}

const csvFile = process.argv[2];
if (!csvFile) {
  console.error('Usage: node import-to-sheets.js <csv-file>');
  process.exit(1);
}

importToSheets(csvFile)
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Error:', error);
    process.exit(1);
  });
EOFSCRIPT

echo "Step 4: Importing to Google Sheets..."

if ! command -v node &> /dev/null; then
  echo "Error: Node.js not found in PATH"
  exit 1
fi

if [ ! -f "node_modules/google-spreadsheet/package.json" ]; then
  echo "Installing required dependencies..."
  npm install --silent google-spreadsheet csv-parser
fi

if [ ! -f "node_modules/csv-parser/package.json" ]; then
  echo "Installing csv-parser..."
  npm install --silent csv-parser
fi

node "$IMPORT_SCRIPT" "$CLEANED_CSV"

echo ""
echo "Step 5: Restoring n8n workflow backups..."

WORKFLOW_BACKUPS=$(find "$BACKUP_DIR" -name "workflow-backup-*.json" -type f 2>/dev/null | head -1)

if [ -z "$WORKFLOW_BACKUPS" ]; then
  echo "Warning: No workflow backups found in $BACKUP_DIR"
  echo "You may need to manually restore workflows."
else
  echo "Found workflow backup: $WORKFLOW_BACKUPS"
  echo "To restore: n8n import:workflow --input=$WORKFLOW_BACKUPS"
fi

echo ""
echo "=== Rollback Summary ==="
echo "PostgreSQL data exported to: $BACKUP_FILE"
echo "Imported to Google Sheets successfully"
echo ""

read -p "Clean up temporary files? (y/n): " cleanup
if [ "$cleanup" = "y" ]; then
  rm -rf "$TEMP_DIR"
  echo "Temporary files cleaned up."
fi

echo ""
echo "Rollback completed!"
echo ""
echo "Next steps:"
echo "1. Verify data in Google Sheets"
echo "2. Update n8n workflows to use Google Sheets nodes again"
echo "3. Stop the sync service if running: pkill -f sheets-postgres-sync"
echo "4. Optionally: DROP TABLE IF EXISTS leads CASCADE;"
