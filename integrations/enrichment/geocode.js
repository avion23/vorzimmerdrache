const https = require('https');

class GeocodeService {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.baseUrl = 'maps.googleapis.com';
    this.rateLimit = {
      maxRequests: 50,
      windowMs: 1000,
      requests: []
    };
  }

  checkRateLimit() {
    const now = Date.now();
    this.rateLimit.requests = this.rateLimit.requests.filter(
      timestamp => now - timestamp < this.rateLimit.windowMs
    );

    if (this.rateLimit.requests.length >= this.rateLimit.maxRequests) {
      const waitTime = this.rateLimit.windowMs - (now - this.rateLimit.requests[0]);
      throw new Error(`Rate limit exceeded. Wait ${waitTime}ms.`);
    }

    this.rateLimit.requests.push(now);
  }

  async geocode(address) {
    this.checkRateLimit();

    const encodedAddress = encodeURIComponent(address);
    const path = `/maps/api/geocode/json?address=${encodedAddress}&language=de&key=${this.apiKey}`;

    return new Promise((resolve, reject) => {
      https.get({
        hostname: this.baseUrl,
        path: path,
        method: 'GET'
      }, (res) => {
        let data = '';

        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const response = JSON.parse(data);
            resolve(this.parseResponse(response));
          } catch (error) {
            reject(new Error(`Parse error: ${error.message}`));
          }
        });
      }).on('error', reject);
    });
  }

  parseResponse(response) {
    if (response.status !== 'OK') {
      return {
        success: false,
        address: null,
        error: this.getErrorMessage(response.status)
      };
    }

    const result = response.results[0];
    const components = this.extractAddressComponents(result.address_components);
    const geometry = result.geometry;

    return {
      success: true,
      address: result.formatted_address,
      components: components,
      coordinates: {
        lat: geometry.location.lat,
        lng: geometry.location.lng
      },
      locationType: geometry.location_type,
      placeId: result.place_id,
      viewport: geometry.viewport,
      types: result.types
    };
  }

  extractAddressComponents(components) {
    const result = {};

    for (const component of components) {
      for (const type of component.types) {
        switch (type) {
          case 'street_number':
            result.streetNumber = component.long_name;
            break;
          case 'route':
            result.street = component.long_name;
            break;
          case 'postal_code':
            result.postalCode = component.long_name;
            break;
          case 'locality':
            result.city = component.long_name;
            break;
          case 'administrative_area_level_2':
            result.district = component.long_name;
            break;
          case 'administrative_area_level_1':
            result.state = component.long_name;
            break;
          case 'country':
            result.country = component.long_name;
            result.countryCode = component.short_name;
            break;
        }
      }
    }

    return result;
  }

  getErrorMessage(status) {
    const errors = {
      'ZERO_RESULTS': 'Address not found',
      'OVER_DAILY_LIMIT': 'API quota exceeded',
      'OVER_QUERY_LIMIT': 'Rate limit exceeded',
      'REQUEST_DENIED': 'API request denied',
      'INVALID_REQUEST': 'Invalid request parameters',
      'UNKNOWN_ERROR': 'Unknown error occurred'
    };
    return errors[status] || status;
  }

  async reverseGeocode(lat, lng) {
    this.checkRateLimit();

    const path = `/maps/api/geocode/json?latlng=${lat},${lng}&language=de&key=${this.apiKey}`;

    return new Promise((resolve, reject) => {
      https.get({
        hostname: this.baseUrl,
        path: path,
        method: 'GET'
      }, (res) => {
        let data = '';

        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const response = JSON.parse(data);
            resolve(this.parseResponse(response));
          } catch (error) {
            reject(new Error(`Parse error: ${error.message}`));
          }
        });
      }).on('error', reject);
    });
  }

  validateAddress(address) {
    if (!address || typeof address !== 'string' || address.trim().length < 5) {
      return {
        valid: false,
        error: 'Address too short or empty'
      };
    }

    const germanAddressPattern = /^[A-Za-zÄÖÜäöüß\s\d.,-]+$/;
    if (!germanAddressPattern.test(address)) {
      return {
        valid: false,
        error: 'Invalid characters in address'
      };
    }

    return {
      valid: true
    };
  }
}

module.exports = GeocodeService;
