const RedisCache = require('./redis-cache');

class CachedPhoneNormalization {
  constructor(options = {}) {
    this.cache = new RedisCache({
      prefix: 'phone:',
      defaultTTL: 86400
    });
  }

  async normalize(phone) {
    if (!phone) {
      return null;
    }

    const cacheKey = `norm:${phone}`;

    return await this.cache.getOrSet(cacheKey, () => {
      return this.doNormalize(phone);
    }, 86400);
  }

  doNormalize(phone) {
    const cleaned = String(phone).replace(/[^\d+]/g, '');

    if (cleaned.startsWith('+49')) {
      return cleaned;
    }

    if (cleaned.startsWith('0049')) {
      return '+49' + cleaned.substring(4);
    }

    if (cleaned.startsWith('0')) {
      return '+49' + cleaned.substring(1);
    }

    if (cleaned.startsWith('+')) {
      return cleaned;
    }

    if (/^\d{10,11}$/.test(cleaned)) {
      return '+49' + cleaned;
    }

    return null;
  }

  async validate(phone) {
    const normalized = await this.normalize(phone);

    if (!normalized) {
      return {
        valid: false,
        error: 'Invalid phone number format'
      };
    }

    const isValid = /^\+\d{11,14}$/.test(normalized);

    return {
      valid: isValid,
      normalized: normalized,
      error: isValid ? null : 'Invalid E.164 format'
    };
  }

  async invalidate(phone) {
    const cacheKey = `norm:${phone}`;
    await this.cache.delete(cacheKey);
  }

  async disconnect() {
    await this.cache.disconnect();
  }
}

module.exports = CachedPhoneNormalization;
