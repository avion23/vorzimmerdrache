require('dotenv').config({ path: '../../.env' });
const Redis = require('ioredis');

class RedisCache {
  constructor(options = {}) {
    this.redis = new Redis({
      host: options.host || process.env.REDIS_HOST || 'localhost',
      port: options.port || process.env.REDIS_PORT || 6379,
      password: options.password || process.env.REDIS_PASSWORD,
      maxRetriesPerRequest: 3,
      retryStrategy: (times) => Math.min(times * 50, 2000),
      enableOfflineQueue: false,
      db: options.db || 0
    });

    this.defaultTTL = options.defaultTTL || 300;
    this.prefix = options.prefix || 'vzd:';
    this.stats = {
      hits: 0,
      misses: 0,
      sets: 0,
      deletes: 0
    };

    this.redis.on('error', (err) => {
      console.error('Redis error:', err.message);
    });
  }

  async get(key) {
    try {
      const cacheKey = this.prefix + key;
      const data = await this.redis.get(cacheKey);

      if (data !== null) {
        this.stats.hits++;
        return JSON.parse(data);
      }

      this.stats.misses++;
      return null;
    } catch (error) {
      console.error(`Cache get error for ${key}:`, error.message);
      return null;
    }
  }

  async set(key, value, ttl = this.defaultTTL) {
    try {
      const cacheKey = this.prefix + key;
      const serialized = JSON.stringify(value);

      if (ttl > 0) {
        await this.redis.setex(cacheKey, ttl, serialized);
      } else {
        await this.redis.set(cacheKey, serialized);
      }

      this.stats.sets++;
      return true;
    } catch (error) {
      console.error(`Cache set error for ${key}:`, error.message);
      return false;
    }
  }

  async delete(key) {
    try {
      const cacheKey = this.prefix + key;
      await this.redis.del(cacheKey);
      this.stats.deletes++;
      return true;
    } catch (error) {
      console.error(`Cache delete error for ${key}:`, error.message);
      return false;
    }
  }

  async deletePattern(pattern) {
    try {
      const cachePattern = this.prefix + pattern;
      const keys = await this.redis.keys(cachePattern);
      if (keys.length > 0) {
        await this.redis.del(keys);
        this.stats.deletes += keys.length;
      }
      return keys.length;
    } catch (error) {
      console.error(`Cache delete pattern error for ${pattern}:`, error.message);
      return 0;
    }
  }

  async getOrSet(key, fetchFn, ttl = this.defaultTTL) {
    const cached = await this.get(key);

    if (cached !== null) {
      return cached;
    }

    const value = await fetchFn();
    await this.set(key, value, ttl);

    return value;
  }

  async mget(keys) {
    try {
      const cacheKeys = keys.map(k => this.prefix + k);
      const values = await this.redis.mget(cacheKeys);

      const results = {};
      keys.forEach((key, i) => {
        results[key] = values[i] !== null ? JSON.parse(values[i]) : null;
      });

      return results;
    } catch (error) {
      console.error('Cache mget error:', error.message);
      return {};
    }
  }

  async mset(keyValuePairs, ttl = this.defaultTTL) {
    try {
      const multi = this.redis.multi();
      
      for (const [key, value] of Object.entries(keyValuePairs)) {
        const cacheKey = this.prefix + key;
        const serialized = JSON.stringify(value);

        if (ttl > 0) {
          multi.setex(cacheKey, ttl, serialized);
        } else {
          multi.set(cacheKey, serialized);
        }
      }

      await multi.exec();
      this.stats.sets += Object.keys(keyValuePairs).length;
      return true;
    } catch (error) {
      console.error('Cache mset error:', error.message);
      return false;
    }
  }

  async flush() {
    try {
      const keys = await this.redis.keys(this.prefix + '*');
      if (keys.length > 0) {
        await this.redis.del(keys);
      }
      return keys.length;
    } catch (error) {
      console.error('Cache flush error:', error.message);
      return 0;
    }
  }

  async disconnect() {
    await this.redis.quit();
  }

  getStats() {
    return { ...this.stats };
  }

  async resetStats() {
    this.stats = { hits: 0, misses: 0, sets: 0, deletes: 0 };
  }

  async getInfo() {
    try {
      const info = await this.redis.info('stats');
      return {
        keyspace: await this.redis.info('keyspace'),
        memory: await this.redis.info('memory'),
        stats: info
      };
    } catch (error) {
      return null;
    }
  }
}

module.exports = RedisCache;
