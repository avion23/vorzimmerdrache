require('dotenv').config({ path: '.env' });
const { GoogleSpreadsheet } = require('google-spreadsheet');
const { Client } = require('pg');
const PhoneValidation = require('../integrations/utils/phone-validation');
const fs = require('fs').promises;
const path = require('path');

class SheetsToPostgresMigrator {
  constructor() {
    this.pgClient = new Client({
      host: process.env.POSTGRES_HOST || 'localhost',
      port: process.env.POSTGRES_PORT || 5432,
      database: process.env.POSTGRES_DB || 'n8n',
      user: process.env.POSTGRES_USER || 'n8n',
      password: process.env.POSTGRES_PASSWORD
    });

    this.backupDir = path.join(__dirname, '..', 'backups');
    this.stats = {
      total: 0,
      imported: 0,
      skipped: 0,
      errors: 0
    };
  }

  async connect() {
    await this.pgClient.connect();
    console.log('Connected to PostgreSQL');
  }

  async disconnect() {
    await this.pgClient.end();
    console.log('Disconnected from PostgreSQL');
  }

  async initGoogleSheets() {
    const doc = new GoogleSpreadsheet(process.env.GOOGLE_SHEETS_ID);

    const creds = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
    await doc.useServiceAccountAuth(creds);
    await doc.loadInfo();

    console.log(`Loaded Google Sheet: ${doc.title}`);

    const sheet = doc.sheetsByIndex[0];
    await sheet.loadHeaderRow();

    return sheet;
  }

  async createBackup() {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupPath = path.join(this.backupDir, `postgres-leads-backup-${timestamp}.sql`);

    console.log('Creating PostgreSQL backup...');

    const { exec } = require('child_process');
    const pgDumpCmd = `pg_dump -h ${process.env.POSTGRES_HOST || 'localhost'} ` +
      `-U ${process.env.POSTGRES_USER || 'n8n'} ` +
      `-d ${process.env.POSTGRES_DB || 'n8n'} ` +
      `-t leads -f "${backupPath}"`;

    return new Promise((resolve, reject) => {
      exec(pgDumpCmd, { env: { ...process.env, PGPASSWORD: process.env.POSTGRES_PASSWORD } }, (error) => {
        if (error) {
          console.warn('Backup failed:', error.message);
          resolve(null);
        } else {
          console.log(`Backup created: ${backupPath}`);
          resolve(backupPath);
        }
      });
    });
  }

  normalizePhone(phone) {
    if (!phone) return null;

    const result = PhoneValidation.validateGermanPhone(phone);
    return result.valid ? result.normalized : null;
  }

  parseAddress(addressRaw) {
    if (!addressRaw) {
      return {
        address_raw: addressRaw,
        address_street: null,
        address_city: null,
        address_postal_code: null,
        address_state: null
      };
    }

    let street = null;
    let city = null;
    let postalCode = null;

    const patterns = [
      { regex: /^(.+?),\s*(\d{5})\s*(.+)$/, groups: ['street', 'postalCode', 'city'] },
      { regex: /^(\d{5})\s+(.+?),\s*(.+)$/, groups: ['postalCode', 'city', 'street'] },
      { regex: /^(.+?),\s*(.+)$/, groups: ['street', 'city'] }
    ];

    for (const { regex, groups } of patterns) {
      const match = addressRaw.match(regex);
      if (match) {
        if (groups[0] === 'street') {
          street = match[1]?.trim() || null;
          postalCode = groups.includes('postalCode') ? (match[2]?.trim() || null) : null;
          city = groups.includes('city') ? (match[groups.length === 3 ? 3 : 2]?.trim() || null) : null;
        } else if (groups[0] === 'postalCode') {
          postalCode = match[1]?.trim() || null;
          city = match[2]?.trim() || null;
          street = groups.includes('street') ? (match[3]?.trim() || null) : null;
        }
        break;
      }
    }

    if (!street && !city) {
      const parts = addressRaw.split(',').map(p => p.trim());
      if (parts.length >= 2) {
        street = parts[0] || null;
        city = parts.slice(1).join(', ') || null;
      } else {
        street = addressRaw;
      }
    }

    return {
      address_raw: addressRaw,
      address_street: street,
      address_city: city,
      address_postal_code: postalCode,
      address_state: null
    };
  }

  mapRowToLead(row, headers) {
    const rawAddress = row.address || row.Address || '';
    const address = this.parseAddress(rawAddress);
    const normalizedPhone = this.normalizePhone(row.phone || row.Phone);

    const phone = row.phone || row.Phone || '';
    const email = row.email || row.Email || '';
    const name = row.name || row.Name || `${row.firstName || ''} ${row.lastName || ''}`.trim();

    return {
      name: name || 'Unknown',
      phone: normalizedPhone,
      email: email || null,
      ...address,
      status: (row.status || row.Status || 'new').toLowerCase(),
      priority: this.parsePriority(row.priority || row.Priority),
      source: row.source || row.Source || null,
      notes: row.notes || row.Notes || null,
      assigned_to: row.assignedTo || row.AssignedTo || null,
      roof_area_sqm: this.parseNumber(row.roofArea || row.RoofArea),
      estimated_kwp: this.parseDecimal(row.estimatedKwp || row.EstimatedKwp),
      estimated_annual_kwh: this.parseNumber(row.estimatedAnnualKwh || row.EstimatedAnnualKwh),
      subsidy_eligible: this.parseBoolean(row.subsidyEligible || row.SubsidyEligible),
      opted_in: this.parseBoolean(row.optedIn || row.OptedIn),
      opted_out: this.parseBoolean(row.optedOut || row.OptedOut),
      original_phone: phone,
      original_email: email
    };
  }

  parsePriority(value) {
    if (!value) return 0;
    const normalized = String(value).toLowerCase();
    if (normalized === 'urgent' || normalized === '2') return 2;
    if (normalized === 'high' || normalized === '1') return 1;
    return 0;
  }

  parseNumber(value) {
    if (!value) return null;
    const num = parseInt(String(value).replace(/\D/g, ''), 10);
    return isNaN(num) ? null : num;
  }

  parseDecimal(value) {
    if (!value) return null;
    const num = parseFloat(String(value).replace(',', '.'));
    return isNaN(num) ? null : num;
  }

  parseBoolean(value) {
    if (!value) return false;
    const normalized = String(value).toLowerCase();
    return ['true', 'yes', '1', 'ja', 'si'].includes(normalized);
  }

  async insertLead(lead) {
    const query = `
      INSERT INTO leads (
        name, phone, email,
        address_raw, address_street, address_city, address_postal_code,
        status, priority, source, notes, assigned_to,
        roof_area_sqm, estimated_kwp, estimated_annual_kwh, subsidy_eligible,
        opted_in, opted_out
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
      ON CONFLICT (phone) DO NOTHING
    `;

    const values = [
      lead.name,
      lead.phone,
      lead.email,
      lead.address_raw,
      lead.address_street,
      lead.address_city,
      lead.address_postal_code,
      lead.status,
      lead.priority,
      lead.source,
      lead.notes,
      lead.assigned_to,
      lead.roof_area_sqm,
      lead.estimated_kwp,
      lead.estimated_annual_kwh,
      lead.subsidy_eligible,
      lead.opted_in,
      lead.opted_out
    ];

    try {
      await this.pgClient.query(query, values);
      return { success: true };
    } catch (error) {
      return { success: false, error: error.message };
    }
  }

  async migrate() {
    try {
      await this.connect();

      const backupPath = await this.createBackup();

      const sheet = await this.initGoogleSheets();
      const rows = await sheet.getRows();

      this.stats.total = rows.length;
      console.log(`Found ${rows.length} rows to migrate`);

      const batchSize = 50;
      for (let i = 0; i < rows.length; i += batchSize) {
        const batch = rows.slice(i, i + batchSize);
        const batchPromises = batch.map(row => this.processRow(row));
        await Promise.all(batchPromises);

        console.log(`Processed ${Math.min(i + batchSize, rows.length)} / ${rows.length} rows`);
      }

      console.log('\n=== Migration Summary ===');
      console.log(`Total rows: ${this.stats.total}`);
      console.log(`Imported: ${this.stats.imported}`);
      console.log(`Skipped (duplicates): ${this.stats.skipped}`);
      console.log(`Errors: ${this.stats.errors}`);

      const countResult = await this.pgClient.query('SELECT COUNT(*) as count FROM leads');
      console.log(`\nLeads in database: ${countResult.rows[0].count}`);

      await this.disconnect();

      return {
        success: true,
        stats: this.stats,
        backup: backupPath
      };

    } catch (error) {
      console.error('Migration failed:', error);
      await this.disconnect();
      return { success: false, error: error.message };
    }
  }

  async processRow(row) {
    this.stats.total++;

    const lead = this.mapRowToLead(row);

    if (!lead.phone) {
      console.warn(`Skipping row without valid phone: ${lead.name}`);
      this.stats.skipped++;
      return;
    }

    const result = await this.insertLead(lead);

    if (result.success) {
      this.stats.imported++;
    } else {
      if (result.error.includes('duplicate key')) {
        this.stats.skipped++;
      } else {
        console.error(`Error inserting lead ${lead.name}:`, result.error);
        this.stats.errors++;
      }
    }
  }
}

if (require.main === module) {
  const migrator = new SheetsToPostgresMigrator();
  migrator.migrate()
    .then(result => {
      process.exit(result.success ? 0 : 1);
    })
    .catch(error => {
      console.error('Fatal error:', error);
      process.exit(1);
    });
}

module.exports = SheetsToPostgresMigrator;
