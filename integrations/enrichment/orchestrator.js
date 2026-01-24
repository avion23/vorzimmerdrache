const GeocodeService = require('./geocode');
const SolarEstimator = require('./solar-estimate');
const ScoringService = require('./scoring');

class EnrichmentOrchestrator {
  constructor(config) {
    this.geocodeService = new GeocodeService(config.geocodingApiKey);
    this.solarEstimator = new SolarEstimator(config.solarApiKey);
    this.scoringService = new ScoringService();
    this.config = config;
  }

  async enrichLead(lead) {
    const address = this.extractAddress(lead);

    if (!address) {
      return this.errorResult(lead, 'No address provided');
    }

    const validation = this.geocodeService.validateAddress(address);
    if (!validation.valid) {
      return this.errorResult(lead, validation.error);
    }

    try {
      const geocodeResult = await this.geocodeService.geocode(address);

      if (!geocodeResult.success) {
        return this.errorResult(lead, geocodeResult.error);
      }

      if (geocodeResult.components.countryCode !== 'DE') {
        return this.errorResult(lead, 'Address is not in Germany');
      }

      const solarEstimate = await this.solarEstimator.estimateSolarPotential(
        geocodeResult.coordinates
      );

      const scoring = this.scoringService.calculateLeadScore(
        geocodeResult,
        solarEstimate
      );

      const enrichedLead = this.scoringService.enrichLeadData(
        lead,
        geocodeResult,
        solarEstimate,
        scoring
      );

      return {
        success: true,
        lead: enrichedLead,
        metadata: {
          enrichedAt: new Date().toISOString(),
          enrichmentVersion: '1.0.0'
        }
      };

    } catch (error) {
      return this.errorResult(lead, error.message);
    }
  }

  async enrichBatch(leads) {
    const results = [];
    const batchSize = this.config.batchSize || 10;
    const batchDelay = this.config.batchDelay || 1000;

    for (let i = 0; i < leads.length; i += batchSize) {
      const batch = leads.slice(i, i + batchSize);
      const batchPromises = batch.map(lead => this.enrichLead(lead));

      const batchResults = await Promise.all(batchPromises);
      results.push(...batchResults);

      if (i + batchSize < leads.length) {
        await this.sleep(batchDelay);
      }
    }

    return results;
  }

  extractAddress(lead) {
    if (typeof lead === 'string') {
      return lead;
    }

    if (lead.address) {
      return lead.address;
    }

    if (lead.street && lead.city) {
      return `${lead.street}, ${lead.postalCode || ''} ${lead.city}`;
    }

    if (lead.components) {
      const { street, streetNumber, postalCode, city } = lead.components;
      return [street, streetNumber, postalCode, city].filter(Boolean).join(' ');
    }

    return null;
  }

  errorResult(lead, error) {
    return {
      success: false,
      lead: {
        ...lead,
        address: {
          original: this.extractAddress(lead) || '',
          validated: null,
          valid: false,
          error: error
        },
        qualification: {
          score: 0,
          category: 'invalid',
          priority: 'P3 - Low',
          recommendation: error
        },
        enrichedAt: new Date().toISOString()
      },
      error: error
    };
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  validateConfig() {
    if (!this.config.geocodingApiKey) {
      throw new Error('Google Geocoding API key is required');
    }

    return {
      valid: true,
      services: {
        geocoding: true,
        solar: !!this.config.solarApiKey
      }
    };
  }
}

module.exports = EnrichmentOrchestrator;
