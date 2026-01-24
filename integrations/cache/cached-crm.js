require('dotenv').config({ path: '../../.env' });
const { Client } = require('pg');
const RedisCache = require('./redis-cache');

class CachedCRMLookup {
  constructor(options = {}) {
    this.pgClient = new Client({
      host: options.host || process.env.POSTGRES_HOST || 'localhost',
      port: options.port || process.env.POSTGRES_PORT || 5432,
      database: options.database || process.env.POSTGRES_DB || 'n8n',
      user: options.user || process.env.POSTGRES_USER || 'n8n',
      password: options.password || process.env.POSTGRES_PASSWORD
    });

    this.cache = new RedisCache({
      prefix: 'crm:',
      defaultTTL: 300
    });
  }

  async connect() {
    await this.pgClient.connect();
  }

  async disconnect() {
    await this.pgClient.end();
    await this.cache.disconnect();
  }

  async findByPhone(phone) {
    const normalizedPhone = this.normalizePhone(phone);

    if (!normalizedPhone) {
      return null;
    }

    const cacheKey = `phone:${normalizedPhone}`;

    return await this.cache.getOrSet(cacheKey, async () => {
      const query = `
        SELECT id, name, phone, email, address_raw, status, priority,
               created_at, updated_at, opted_out
        FROM leads
        WHERE phone = $1
        LIMIT 1
      `;

      const result = await this.pgClient.query(query, [normalizedPhone]);
      return result.rows[0] || null;
    }, 300);
  }

  async findByEmail(email) {
    if (!email) {
      return null;
    }

    const cacheKey = `email:${email.toLowerCase()}`;

    return await this.cache.getOrSet(cacheKey, async () => {
      const query = `
        SELECT id, name, phone, email, address_raw, status, priority,
               created_at, updated_at
        FROM leads
        WHERE email = $1
        LIMIT 1
      `;

      const result = await this.pgClient.query(query, [email.toLowerCase()]);
      return result.rows[0] || null;
    }, 300);
  }

  async findRecentLeads(limit = 10, status = 'new') {
    const cacheKey = `recent:${status}:${limit}`;

    return await this.cache.getOrSet(cacheKey, async () => {
      const query = `
        SELECT id, name, phone, email, status, priority, created_at
        FROM leads
        WHERE status = $1 AND opted_out = FALSE
        ORDER BY created_at DESC
        LIMIT $2
      `;

      const result = await this.pgClient.query(query, [status, limit]);
      return result.rows;
    }, 60);
  }

  async findHighPriorityLeads(limit = 10) {
    const cacheKey = `priority:${limit}`;

    return await this.cache.getOrSet(cacheKey, async () => {
      const query = `
        SELECT id, name, phone, email, status, priority, created_at
        FROM leads
        WHERE priority > 0 AND opted_out = FALSE
        ORDER BY priority DESC, created_at DESC
        LIMIT $1
      `;

      const result = await this.pgClient.query(query, [limit]);
      return result.rows;
    }, 60);
  }

  async invalidatePhone(phone) {
    const normalizedPhone = this.normalizePhone(phone);
    if (normalizedPhone) {
      await this.cache.delete(`phone:${normalizedPhone}`);
    }
  }

  async invalidateEmail(email) {
    if (email) {
      await this.cache.delete(`email:${email.toLowerCase()}`);
    }
  }

  async invalidateRecent(status) {
    await this.cache.deletePattern(`recent:${status}:*`);
  }

  async invalidatePriority() {
    await this.cache.deletePattern('priority:*');
  }

  async invalidateAll() {
    await this.cache.flush();
  }

  normalizePhone(phone) {
    if (!phone) return null;
    const cleaned = String(phone).replace(/[^\d+]/g, '');
    if (cleaned.startsWith('+49')) return cleaned;
    if (cleaned.startsWith('0049')) return '+49' + cleaned.substring(4);
    if (cleaned.startsWith('0')) return '+49' + cleaned.substring(1);
    return cleaned.startsWith('+') ? cleaned : null;
  }

  async getCacheStats() {
    return this.cache.getStats();
  }
}

module.exports = CachedCRMLookup;
