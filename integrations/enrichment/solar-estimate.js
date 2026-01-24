const https = require('https');

class SolarEstimator {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.baseUrl = 'solar.googleapis.com';
    this.useGoogleSolar = true;
  }

  async estimateSolarPotential(location) {
    if (this.useGoogleSolar && this.apiKey) {
      try {
        return await this.getGoogleSolarPotential(location);
      } catch (error) {
        console.log(`Google Solar API failed: ${error.message}, falling back to heuristic`);
        return this.heuristicEstimate(location);
      }
    }
    return this.heuristicEstimate(location);
  }

  async getGoogleSolarPotential(location) {
    const { lat, lng } = location;
    const path = `/v1/buildingInsights:findClosest?location.latitude=${lat}&location.longitude=${lng}&requiredQuality=HIGH&key=${this.apiKey}`;

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
            resolve(this.parseGoogleSolarResponse(response));
          } catch (error) {
            reject(new Error(`Parse error: ${error.message}`));
          }
        });
      }).on('error', reject);
    });
  }

  parseGoogleSolarResponse(response) {
    if (!response.buildingInsights) {
      throw new Error('No building insights found');
    }

    const stats = response.buildingInsights.solarPotential;
    const roofSegmentStats = stats.roofSegmentStats;

    const totalRoofArea = roofSegmentStats.reduce((sum, segment) => sum + segment.areaMeters2, 0);
    const maxSunlitRoofArea = roofSegmentStats.reduce((max, segment) => 
      Math.max(max, segment.areaMeters2), 0);

    return {
      source: 'google-solar-api',
      roofArea: Math.round(totalRoofArea),
      maxSunlitRoofArea: Math.round(maxSunlitRoofArea),
      maxArrayPanelsCount: stats.maxArrayPanelsCount,
      maxArrayAreaMeters2: Math.round(stats.maxArrayAreaMeters2),
      maxArrayCapacityWatts: stats.maxArrayCapacityWatts,
      maxArrayEnergyProductionKwh: Math.round(stats.maxArrayEnergyProductionKwh),
      panelOrientation: this.inferOrientation(roofSegmentStats),
      roofType: 'flat',
      confidence: 'high'
    };
  }

  inferOrientation(roofSegments) {
    const orientations = roofSegments.map(seg => seg.heading);
    const avgOrientation = orientations.reduce((a, b) => a + b, 0) / orientations.length;

    if (avgOrientation >= 337.5 || avgOrientation < 22.5) return 'north';
    if (avgOrientation >= 22.5 && avgOrientation < 67.5) return 'northeast';
    if (avgOrientation >= 67.5 && avgOrientation < 112.5) return 'east';
    if (avgOrientation >= 112.5 && avgOrientation < 157.5) return 'southeast';
    if (avgOrientation >= 157.5 && avgOrientation < 202.5) return 'south';
    if (avgOrientation >= 202.5 && avgOrientation < 247.5) return 'southwest';
    if (avgOrientation >= 247.5 && avgOrientation < 292.5) return 'west';
    if (avgOrientation >= 292.5 && avgOrientation < 337.5) return 'northwest';
    return 'unknown';
  }

  heuristicEstimate(location) {
    const { lat, components } = location;
    const roofArea = this.estimateRoofAreaFromOSM(lat, location.lng);
    const orientation = this.estimateOrientation(lat);

    return {
      source: 'osm-heuristic',
      roofArea: roofArea,
      maxSunlitRoofArea: Math.round(roofArea * 0.6),
      maxArrayPanelsCount: this.estimatePanelCount(roofArea),
      maxArrayAreaMeters2: Math.round(roofArea * 0.5),
      maxArrayCapacityWatts: Math.round(roofArea * 0.5 * 200),
      maxArrayEnergyProductionKwh: Math.round(roofArea * 0.5 * 200 * 0.9),
      panelOrientation: orientation,
      roofType: this.estimateRoofType(components),
      confidence: 'medium'
    };
  }

  estimateRoofAreaFromOSM(lat, lng) {
    const floorArea = this.estimateBuildingSize(lat);
    const roofMultiplier = 1.3;

    return Math.round(floorArea * roofMultiplier);
  }

  estimateBuildingSize(lat) {
    const baseArea = 80;
    const variation = Math.sin(lat * Math.PI / 180) * 20;
    return Math.max(60, Math.round(baseArea + variation));
  }

  estimateOrientation(lat) {
    if (lat > 50) return 'south';
    if (lat > 48) return 'southwest';
    return 'south';
  }

  estimateRoofType(components) {
    if (!components || !components.postalCode) return 'unknown';

    const region = components.postalCode.substring(0, 2);
    const flatRoofRegions = ['10', '40', '50', '80'];

    return flatRoofRegions.includes(region) ? 'flat' : 'pitched';
  }

  calculatePotentialKWh(solarData, regionalData) {
    if (!solarData || !regionalData) return 0;

    const baseKWh = solarData.maxArrayEnergyProductionKwh;
    const irradianceFactor = regionalData.solarIrradiance / 1050;
    const orientationFactor = this.getOrientationFactor(solarData.panelOrientation);
    const roofTypeFactor = this.getRoofTypeFactor(solarData.roofType);

    return Math.round(baseKWh * irradianceFactor * orientationFactor * roofTypeFactor);
  }

  getOrientationFactor(orientation) {
    const factors = {
      'south': 1.0,
      'southwest': 0.95,
      'southeast': 0.95,
      'west': 0.75,
      'east': 0.75,
      'north': 0.45,
      'unknown': 0.7
    };
    return factors[orientation] || 0.7;
  }

  getRoofTypeFactor(roofType) {
    const factors = {
      'flat': 1.0,
      'pitched': 0.85,
      'unknown': 0.9
    };
    return factors[roofType] || 0.9;
  }

  estimateSystemCost(solarData, regionalData) {
    const roofArea = solarData.roofArea || 0;
    const panelCount = solarData.maxArrayPanelsCount || 0;

    const costPerWatt = 1.4;
    const baseCost = panelCount * 400 * costPerWatt;
    const regionalMultiplier = regionalData.regionalBonus || 1.0;

    return {
      estimatedCostEUR: Math.round(baseCost * regionalMultiplier),
      costPerKwh: Math.round((baseCost * regionalMultiplier) / solarData.maxArrayEnergyProductionKwh * 100) / 100
    };
  }
}

module.exports = SolarEstimator;
