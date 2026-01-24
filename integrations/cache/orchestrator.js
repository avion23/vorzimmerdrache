const RedisCache = require('./redis-cache');
const CachedCRMLookup = require('./cached-crm');
const CachedGeocodeService = require('./cached-geocode');
const CachedPhoneNormalization = require('./cached-phone');

class CacheOrchestrator {
  constructor(options = {}) {
    this.crm = new CachedCRMLookup(options);
    this.geo = new CachedGeocodeService({
      apiKey: options.apiKey || options.googleMapsApiKey
    });
    this.phone = new CachedPhoneNormalization();
    this.cache = new RedisCache(options);
  }

  async init() {
    await this.crm.connect();
  }

  async disconnect() {
    await this.crm.disconnect();
    await this.geo.disconnect();
    await this.phone.disconnect();
    await this.cache.disconnect();
  }

  async processIncomingLead(data) {
    const { phone, address, email } = data;

    const results = {
      original: data,
      phone: null,
      customer: null,
      geocode: null,
      processedAt: new Date().toISOString()
    };

    const tasks = [];

    if (phone) {
      tasks.push(
        this.phone.normalize(phone).then(result => {
          results.phone = result;
        })
      );

      tasks.push(
        this.phone.validate(phone).then(result => {
          results.phoneValid = result.valid;
        })
      );
    }

    if (address) {
      tasks.push(
        this.geo.geocode(address).then(result => {
          results.geocode = result;
        })
      );
    }

    await Promise.all(tasks);

    if (results.phone) {
      results.customer = await this.crm.findByPhone(results.phone);
    }

    return results;
  }

  async processIncomingCall(data) {
    const { phone: originalPhone, address } = data;

    const results = {
      originalPhone,
      normalizedPhone: null,
      customer: null,
      geocode: null,
      processedAt: new Date().toISOString()
    };

    const tasks = [];

    if (originalPhone) {
      const normalized = await this.phone.normalize(originalPhone);
      results.normalizedPhone = normalized;

      if (normalized) {
        tasks.push(
          this.crm.findByPhone(normalized).then(customer => {
            results.customer = customer;
          })
        );
      }
    }

    if (address) {
      tasks.push(
        this.geo.geocode(address).then(result => {
          results.geocode = result;
        })
      );
    }

    await Promise.all(tasks);

    return results;
  }

  async invalidateLead(leadData) {
    const { phone, email } = leadData;

    if (phone) {
      await this.crm.invalidatePhone(phone);
    }

    if (email) {
      await this.crm.invalidateEmail(email);
    }
  }

  async invalidateAll() {
    await this.crm.invalidateAll();
    await this.cache.flush();
  }

  async getStats() {
    return {
      crm: await this.crm.getCacheStats(),
      cache: this.cache.getStats()
    };
  }
}

module.exports = CacheOrchestrator;

if (require.main === module) {
  (async () => {
    const orchestrator = new CacheOrchestrator({
      googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY
    });

    await orchestrator.init();

    const testData = {
      phone: '0171 23456789',
      address: 'Alexanderplatz 1, 10178 Berlin',
      email: 'test@example.com'
    };

    console.log('Processing test lead...');
    const result = await orchestrator.processIncomingLead(testData);
    console.log(JSON.stringify(result, null, 2));

    await orchestrator.disconnect();
  })();
}
