const GeocodeService = require('../enrichment/geocode');
const RedisCache = require('./redis-cache');

class CachedGeocodeService {
  constructor(options = {}) {
    this.geocodeService = new GeocodeService(options.apiKey);
    this.cache = new RedisCache({
      prefix: 'geo:',
      defaultTTL: 3600
    });
  }

  async geocode(address) {
    const cacheKey = `address:${Buffer.from(address).toString('base64')}`;

    return await this.cache.getOrSet(cacheKey, async () => {
      return await this.geocodeService.geocode(address);
    }, 3600);
  }

  async reverseGeocode(lat, lng) {
    const cacheKey = `coords:${lat},${lng}`;

    return await this.cache.getOrSet(cacheKey, async () => {
      return await this.geocodeService.reverseGeocode(lat, lng);
    }, 3600);
  }

  async validateAddress(address) {
    return this.geocodeService.validateAddress(address);
  }

  async clearCache() {
    await this.cache.deletePattern('*');
  }

  async disconnect() {
    await this.cache.disconnect();
  }
}

module.exports = CachedGeocodeService;
