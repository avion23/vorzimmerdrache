require('dotenv').config({ path: '../../.env' });
const { Client } = require('pg');
const axios = require('axios');
const cron = require('node-cron');
const FormData = require('form-data');

class BaserowSync {
  constructor() {
    this.pgClient = new Client({
      host: process.env.POSTGRES_HOST || 'localhost',
      port: process.env.POSTGRES_PORT || 5432,
      database: process.env.POSTGRES_DB || 'n8n',
      user: process.env.POSTGRES_USER || 'n8n',
      password: process.env.POSTGRES_PASSWORD
    });

    this.baserowUrl = process.env.BASEROW_PUBLIC_URL?.replace(/\/$/, '') || 'http://localhost:8000';
    this.baserowApiToken = process.env.BASEROW_API_TOKEN;
    this.baserowTableId = process.env.BASEROW_TABLE_ID;
    this.baserowAuth = `Token ${this.baserowApiToken}`;

    this.syncInterval = null;
    this.lastSync = null;
    this.fieldMap = {
      'ID': 'id',
      'Created At': 'created_at',
      'Name': 'name',
      'Phone': 'phone',
      'Email': 'email',
      'Address': 'address_raw',
      'City': 'address_city',
      'Postal Code': 'address_postal_code',
      'State': 'address_state',
      'Latitude': 'latitude',
      'Longitude': 'longitude',
      'Status': 'status',
      'Priority': 'priority',
      'Opted In': 'opted_in',
      'Opted Out': 'opted_out',
      'Roof Area (sqm)': 'roof_area_sqm',
      'Estimated kWp': 'estimated_kwp',
      'Estimated Annual kWh': 'estimated_annual_kwh',
      'Subsidy Eligible': 'subsidy_eligible',
      'Source': 'source',
      'Notes': 'notes',
      'Assigned To': 'assigned_to',
      'Meeting Date': 'meeting_date'
    };

    this.reverseFieldMap = Object.fromEntries(
      Object.entries(this.fieldMap).map(([k, v]) => [v, k])
    );
  }

  async connect() {
    await this.pgClient.connect();
    console.log('Sync service: Connected to PostgreSQL');

    if (!this.baserowApiToken) {
      throw new Error('BASEROW_API_TOKEN not set in .env');
    }

    if (!this.baserowTableId) {
      await this.discoverTableId();
    }

    console.log(`Sync service: Connected to Baserow (Table ID: ${this.baserowTableId})`);
  }

  async discoverTableId() {
    try {
      const response = await axios.get(
        `${this.baserowUrl}/api/database/tables/`,
        { headers: { Authorization: this.baserowAuth } }
      );

      for (const db of response.data) {
        if (db.type === 'database') {
          const tablesResponse = await axios.get(
            `${this.baserowUrl}/api/database/tables/database/${db.id}/tables/`,
            { headers: { Authorization: this.baserowAuth } }
          );

          const leadsTable = tablesResponse.data.find(t => t.name === 'Leads');
          if (leadsTable) {
            this.baserowTableId = leadsTable.id;
            console.log(`Discovered Baserow table ID: ${this.baserowTableId}`);
            return;
          }
        }
      }

      throw new Error('Could not find "Leads" table in Baserow');
    } catch (error) {
      throw new Error(`Failed to discover table ID: ${error.message}`);
    }
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

  async getBaserowRows() {
    const response = await axios.get(
      `${this.baserowUrl}/api/database/rows/table/${this.baserowTableId}/?user_field_names=true`,
      { headers: { Authorization: this.baserowAuth } }
    );
    return response.data.results;
  }

  pgToBaserowRow(lead) {
    const row = {};

    for (const [baserowField, pgField] of Object.entries(this.fieldMap)) {
      let value = lead[pgField];

      if (value === null || value === undefined) {
        continue;
      }

      if (pgField === 'created_at' || pgField === 'meeting_date' || pgField === 'opted_out_at') {
        if (value instanceof Date || typeof value === 'string') {
          value = new Date(value).toISOString();
        }
      }

      if (pgField === 'opted_in' || pgField === 'opted_out' || pgField === 'subsidy_eligible') {
        value = value === true ? 'true' : 'false';
      }

      row[baserowField] = value;
    }

    return row;
  }

  baserowToPgRow(baserowRow) {
    const lead = {};

    for (const [baserowField, pgField] of Object.entries(this.fieldMap)) {
      let value = baserowRow[baserowField];

      if (value === null || value === undefined || value === '') {
        continue;
      }

      if (pgField === 'created_at' || pgField === 'meeting_date') {
        if (typeof value === 'string') {
          value = new Date(value);
        }
      }

      if (pgField === 'opted_in' || pgField === 'opted_out' || pgField === 'subsidy_eligible') {
        value = value === 'true' || value === true;
      }

      if (pgField === 'latitude' || pgField === 'longitude' || pgField === 'estimated_kwp') {
        if (typeof value === 'string') {
          value = parseFloat(value);
        }
      }

      if (pgField === 'roof_area_sqm' || pgField === 'estimated_annual_kwh' || pgField === 'priority') {
        if (typeof value === 'string') {
          value = parseInt(value, 10);
        }
      }

      lead[pgField] = value;
    }

    return lead;
  }

  async syncToBaserow(leads) {
    const batchSize = 50;
    let synced = 0;
    let errors = 0;

    for (let i = 0; i < leads.length; i += batchSize) {
      const batch = leads.slice(i, i + batchSize);

      try {
        const baserowRows = await this.getBaserowRows();
        const baserowIndex = new Map();

        for (const row of baserowRows) {
          if (row.ID) {
            baserowIndex.set(row.ID, row);
          }
        }

        for (const lead of batch) {
          const baserowRow = this.pgToBaserowRow(lead);
          const existingRow = baserowIndex.get(lead.id.toString());

          try {
            if (existingRow) {
              await axios.patch(
                `${this.baserowUrl}/api/database/rows/table/${this.baserowTableId}/${existingRow.id}/?user_field_names=true`,
                baserowRow,
                { headers: { Authorization: this.baserowAuth } }
              );
            } else {
              await axios.post(
                `${this.baserowUrl}/api/database/rows/table/${this.baserowTableId}/?user_field_names=true`,
                baserowRow,
                { headers: { Authorization: this.baserowAuth } }
              );
            }

            synced++;
          } catch (error) {
            console.error(`Error syncing lead ${lead.id}:`, error.response?.data || error.message);
            errors++;
          }
        }

        console.log(`Synced ${synced} / ${leads.length} leads to Baserow`);
        await this.sleep(500);
      } catch (error) {
        console.error(`Error syncing batch starting at index ${i}:`, error.message);
        errors += batch.length;
      }
    }

    return { synced, errors };
  }

  async syncFromBaserow() {
    const baserowRows = await this.getBaserowRows();
    let imported = 0;
    let updated = 0;
    let skipped = 0;
    let errors = 0;

    for (const baserowRow of baserowRows) {
      if (!baserowRow.ID) {
        skipped++;
        continue;
      }

      try {
        const lead = this.baserowToPgRow(baserowRow);
        const phone = lead.phone;

        if (!phone) {
          skipped++;
          continue;
        }

        const existsResult = await this.pgClient.query(
          'SELECT id, updated_at FROM leads WHERE id = $1',
          [lead.id]
        );

        if (existsResult.rows.length > 0) {
          const existingLead = existsResult.rows[0];

          if (new Date(baserowRow.created_at) <= new Date(existingLead.updated_at)) {
            skipped++;
            continue;
          }

          await this.updateLeadFromBaserow(lead);
          updated++;
        } else {
          await this.insertLeadFromBaserow(lead);
          imported++;
        }
      } catch (error) {
        console.error(`Error processing Baserow row ${baserowRow.id}:`, error.message);
        errors++;
      }
    }

    console.log(`Imported ${imported}, updated ${updated}, skipped ${skipped}, errors ${errors}`);

    return { imported, updated, skipped, errors };
  }

  async insertLeadFromBaserow(lead) {
    const query = `
      INSERT INTO leads (
        id, created_at, updated_at, name, phone, email, address_raw, address_city,
        address_postal_code, address_state, latitude, longitude, status, priority,
        opted_in, opted_out, roof_area_sqm, estimated_kwp, estimated_annual_kwh,
        subsidy_eligible, source, notes, assigned_to
      ) VALUES ($1, $2, NOW(), $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22)
    `;

    await this.pgClient.query(query, [
      lead.id,
      lead.created_at || new Date(),
      lead.name,
      lead.phone,
      lead.email,
      lead.address_raw,
      lead.address_city,
      lead.address_postal_code,
      lead.address_state,
      lead.latitude,
      lead.longitude,
      lead.status,
      lead.priority,
      lead.opted_in,
      lead.opted_out,
      lead.roof_area_sqm,
      lead.estimated_kwp,
      lead.estimated_annual_kwh,
      lead.subsidy_eligible,
      lead.source,
      lead.notes,
      lead.assigned_to
    ]);
  }

  async updateLeadFromBaserow(lead) {
    const fields = Object.keys(lead).filter(k => k !== 'id');
    const setClause = fields.map((f, i) => `${f} = $${i + 2}`).join(', ');
    const values = fields.map(f => lead[f]);

    const query = `
      UPDATE leads SET ${setClause}, updated_at = NOW()
      WHERE id = $1
    `;

    await this.pgClient.query(query, [lead.id, ...values]);
  }

  async handleWhatsAppAttachment(rowId, attachmentUrl) {
    try {
      const response = await axios.get(attachmentUrl, {
        responseType: 'stream'
      });

      const filename = attachmentUrl.split('/').pop();
      const formData = new FormData();
      formData.append('file', response.data, filename);

      await axios.post(
        `${this.baserowUrl}/api/database/rows/table/${this.baserowTableId}/${rowId}/`,
        formData,
        {
          headers: {
            Authorization: this.baserowAuth,
            ...formData.getHeaders()
          }
        }
      );

      console.log(`Attached WhatsApp media to row ${rowId}`);
    } catch (error) {
      console.error(`Error attaching WhatsApp media to row ${rowId}:`, error.message);
    }
  }

  async bidirectionalSync() {
    console.log(`\n[${new Date().toISOString()}] Starting bidirectional sync...`);

    try {
      await this.connect();

      const pgLeads = await this.getPostgresLeads(this.lastSync);
      console.log(`Found ${pgLeads.length} updated leads in PostgreSQL`);

      if (pgLeads.length > 0) {
        const { synced, errors: syncErrors } = await this.syncToBaserow(pgLeads);
        if (syncErrors === 0 && pgLeads.length > 0) {
          this.lastSync = pgLeads[pgLeads.length - 1].updated_at;
        }
      }

      const { imported, updated, skipped, errors } = await this.syncFromBaserow();

      console.log(`[${new Date().toISOString()}] Sync completed`);
      console.log(`PostgreSQL → Baserow: ${synced || 0} synced`);
      console.log(`Baserow → PostgreSQL: ${imported} imported, ${updated} updated, ${skipped} skipped, ${errors} errors`);

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

module.exports = BaserowSync;

if (require.main === module) {
  const sync = new BaserowSync();

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
    console.log('Usage: node baserow-sync.js [once|daemon] [minutes]');
    process.exit(1);
  }
}
