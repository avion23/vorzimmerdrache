require('dotenv').config({ path: '../../.env' });
const { GoogleSpreadsheet } = require('google-spreadsheet');
const { Client } = require('pg');
const cron = require('node-cron');

class SheetsPostgresSync {
  constructor() {
    this.pgClient = new Client({
      host: process.env.POSTGRES_HOST || 'localhost',
      port: process.env.POSTGRES_PORT || 5432,
      database: process.env.POSTGRES_DB || 'n8n',
      user: process.env.POSTGRES_USER || 'n8n',
      password: process.env.POSTGRES_PASSWORD
    });

    this.googleSheet = null;
    this.syncInterval = null;
    this.lastSync = null;
  }

  async connect() {
    await this.pgClient.connect();
    console.log('Sync service: Connected to PostgreSQL');

    const doc = new GoogleSpreadsheet(process.env.GOOGLE_SHEETS_ID);
    const creds = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
    await doc.useServiceAccountAuth(creds);
    await doc.loadInfo();

    this.googleSheet = doc.sheetsByIndex[0];
    console.log(`Sync service: Connected to Google Sheet: ${doc.title}`);
  }

  async disconnect() {
    await this.pgClient.end();
    console.log('Sync service: Disconnected');
  }

  async getPostgresLeads(after = null) {
    let query = 'SELECT * FROM leads';
    const params = [];

    if (after) {
      query += ' WHERE updated_at > $1';
      params.push(after);
    }

    query += ' ORDER BY updated_at ASC';

    const result = await this.pgClient.query(query, params);
    return result.rows;
  }

  async getSheetRows() {
    await this.googleSheet.loadHeaderRow();
    const rows = await this.googleSheet.getRows();
    return rows;
  }

  async syncToSheet(leads) {
    const batchSize = 50;
    let synced = 0;

    for (let i = 0; i < leads.length; i += batchSize) {
      const batch = leads.slice(i, i + batchSize);

      const values = batch.map(lead => [
        lead.created_at?.toISOString() || '',
        lead.name || '',
        lead.phone || '',
        lead.email || '',
        lead.address_raw || '',
        lead.status || 'new',
        lead.notes || ''
      ]);

      const range = `A${i + 2}:G${i + 1 + batch.length}`;

      try {
        await this.googleSheet.addRows(batch.map(lead => ({
          timestamp: lead.created_at?.toISOString(),
          name: lead.name,
          phone: lead.phone,
          email: lead.email,
          address: lead.address_raw,
          status: lead.status,
          notes: lead.notes
        })));

        synced += batch.length;
        console.log(`Synced ${synced} / ${leads.length} leads to Google Sheets`);

        await this.sleep(1000);
      } catch (error) {
        console.error(`Error syncing batch starting at row ${i}:`, error.message);
      }
    }

    return synced;
  }

  async syncFromSheet() {
    const rows = await this.getSheetRows();
    let imported = 0;
    let skipped = 0;

    for (const row of rows) {
      const phone = this.normalizePhone(row.phone);
      if (!phone) {
        skipped++;
        continue;
      }

      const existsResult = await this.pgClient.query(
        'SELECT id FROM leads WHERE phone = $1',
        [phone]
      );

      if (existsResult.rows.length > 0) {
        await this.updateLeadFromSheet(row, phone);
      } else {
        await this.insertLeadFromSheet(row, phone);
        imported++;
      }
    }

    console.log(`Imported ${imported} new leads, skipped ${skipped} invalid rows`);

    return { imported, skipped };
  }

  normalizePhone(phone) {
    if (!phone) return null;
    const cleaned = String(phone).replace(/[^\d+]/g, '');
    if (cleaned.startsWith('+49')) return cleaned;
    if (cleaned.startsWith('0049')) return '+49' + cleaned.substring(4);
    if (cleaned.startsWith('0')) return '+49' + cleaned.substring(1);
    return cleaned.startsWith('+') ? cleaned : null;
  }

  async insertLeadFromSheet(row, phone) {
    const query = `
      INSERT INTO leads (
        name, phone, email, address_raw, status, notes, source
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
    `;

    await this.pgClient.query(query, [
      row.name || 'Unknown',
      phone,
      row.email || null,
      row.address || null,
      (row.status || 'new').toLowerCase(),
      row.notes || null,
      'google-sheets'
    ]);
  }

  async updateLeadFromSheet(row, phone) {
    const query = `
      UPDATE leads SET
        name = $1,
        email = COALESCE($2, email),
        address_raw = COALESCE($3, address_raw),
        status = $4,
        notes = COALESCE($5, notes),
        updated_at = NOW()
      WHERE phone = $6
    `;

    await this.pgClient.query(query, [
      row.name,
      row.email || null,
      row.address || null,
      (row.status || 'new').toLowerCase(),
      row.notes || null,
      phone
    ]);
  }

  async bidirectionalSync() {
    console.log(`\n[${new Date().toISOString()}] Starting bidirectional sync...`);

    try {
      await this.connect();

      const pgLeads = await this.getPostgresLeads(this.lastSync);
      console.log(`Found ${pgLeads.length} updated leads in PostgreSQL`);

      if (pgLeads.length > 0) {
        await this.syncToSheet(pgLeads);
        this.lastSync = pgLeads[pgLeads.length - 1].updated_at;
      }

      await this.syncFromSheet();

      console.log(`[${new Date().toISOString()}] Sync completed`);

    } catch (error) {
      console.error('Sync error:', error.message);
    } finally {
      await this.disconnect();
    }
  }

  startCron(intervalMinutes = 5) {
    console.log(`Starting sync service (every ${intervalMinutes} minutes)`);
    this.syncInterval = cron.schedule(`*/${intervalMinutes} * * * *`, () => {
      this.bidirectionalSync();
    });
  }

  stopCron() {
    if (this.syncInterval) {
      this.syncInterval.stop();
      console.log('Sync service stopped');
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

module.exports = SheetsPostgresSync;

if (require.main === module) {
  const sync = new SheetsPostgresSync();

  const args = process.argv.slice(2);
  const command = args[0] || 'once';

  if (command === 'once') {
    sync.bidirectionalSync()
      .then(() => process.exit(0))
      .catch(error => {
        console.error(error);
        process.exit(1);
      });
  } else if (command === 'daemon') {
    const minutes = parseInt(args[1]) || 5;
    sync.startCron(minutes);
  } else {
    console.log('Usage: node sheets-postgres-sync.js [once|daemon] [minutes]');
    process.exit(1);
  }
}
