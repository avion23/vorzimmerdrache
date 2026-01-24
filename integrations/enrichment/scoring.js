const regionalSolarData = require('../../config/regional-solar-data.json');

class ScoringService {
  constructor() {
    this.weights = {
      addressValid: 3,
      roofSize: 2.5,
      regionalFactor: 2,
      orientation: 1.5,
      roofType: 1
    };
  }

  calculateLeadScore(geocodeResult, solarEstimate) {
    const scores = {
      addressValid: this.scoreAddressValid(geocodeResult),
      roofSize: this.scoreRoofSize(solarEstimate),
      regionalFactor: this.scoreRegionalFactor(geocodeResult),
      orientation: this.scoreOrientation(solarEstimate),
      roofType: this.scoreRoofType(solarEstimate)
    };

    const totalScore = Object.entries(scores).reduce((sum, [key, value]) => {
      return sum + (value * this.weights[key]);
    }, 0);

    const maxScore = Object.values(this.weights).reduce((sum, w) => sum + (10 * w), 0);
    const normalizedScore = Math.min(10, Math.round((totalScore / maxScore) * 10));

    return {
      totalScore: normalizedScore,
      breakdown: scores,
      category: this.getCategory(normalizedScore),
      recommendation: this.getRecommendation(normalizedScore),
      priority: this.getPriority(normalizedScore)
    };
  }

  scoreAddressValid(geocodeResult) {
    if (!geocodeResult || !geocodeResult.success) {
      return 0;
    }

    if (geocodeResult.locationType === 'ROOFTOP') {
      return 10;
    }

    if (['RANGE_INTERPOLATED', 'GEOMETRIC_CENTER'].includes(geocodeResult.locationType)) {
      return 7;
    }

    if (geocodeResult.locationType === 'APPROXIMATE') {
      return 4;
    }

    return 5;
  }

  scoreRoofSize(solarEstimate) {
    if (!solarEstimate || !solarEstimate.roofArea) {
      return 0;
    }

    const roofArea = solarEstimate.roofArea;
    const minArea = regionalSolarData.minimumRoofArea;
    const optimalArea = regionalSolarData.optimalRoofArea;

    if (roofArea < minArea) {
      return 0;
    }

    if (roofArea >= optimalArea) {
      return 10;
    }

    const ratio = (roofArea - minArea) / (optimalArea - minArea);
    return Math.round(ratio * 10);
  }

  scoreRegionalFactor(geocodeResult) {
    if (!geocodeResult || !geocodeResult.components || !geocodeResult.components.state) {
      return 5;
    }

    const state = geocodeResult.components.state;
    const stateData = regionalSolarData.states[state];

    if (!stateData) {
      return 5;
    }

    return stateData.suitabilityScore;
  }

  scoreOrientation(solarEstimate) {
    if (!solarEstimate || !solarEstimate.panelOrientation) {
      return 5;
    }

    const orientationFactors = {
      'south': 10,
      'southwest': 9,
      'southeast': 9,
      'west': 7,
      'east': 7,
      'north': 3,
      'unknown': 5
    };

    return orientationFactors[solarEstimate.panelOrientation] || 5;
  }

  scoreRoofType(solarEstimate) {
    if (!solarEstimate || !solarEstimate.roofType) {
      return 7;
    }

    const roofTypeScores = {
      'flat': 10,
      'pitched': 7,
      'unknown': 5
    };

    return roofTypeScores[solarEstimate.roofType] || 5;
  }

  getCategory(score) {
    if (score >= 8) return 'excellent';
    if (score >= 6) return 'good';
    if (score >= 4) return 'moderate';
    return 'poor';
  }

  getRecommendation(score) {
    const recommendations = {
      10: 'Immediate contact - highest potential',
      9: 'Priority contact - excellent opportunity',
      8: 'High priority - schedule consultation',
      7: 'Good opportunity - standard follow-up',
      6: 'Qualified lead - add to pipeline',
      5: 'Moderate potential - assess with site visit',
      4: 'Below average - requires additional qualification',
      3: 'Low priority - optional follow-up',
      2: 'Poor fit - consider declining',
      1: 'Not suitable - do not pursue',
      0: 'Invalid - address verification failed'
    };

    return recommendations[score] || 'Assess individually';
  }

  getPriority(score) {
    if (score >= 8) return 'P0 - Critical';
    if (score >= 6) return 'P1 - High';
    if (score >= 4) return 'P2 - Medium';
    return 'P3 - Low';
  }

  enrichLeadData(lead, geocodeResult, solarEstimate, scoring) {
    const regionalData = this.getRegionalData(geocodeResult);
    const potentialKWh = solarEstimate ? this.calculatePotentialKWh(solarEstimate, regionalData) : 0;
    const systemCost = solarEstimate ? this.estimateSystemCost(solarEstimate, regionalData) : null;

    return {
      ...lead,
      address: {
        original: lead.address || '',
        validated: geocodeResult?.address || null,
        coordinates: geocodeResult?.coordinates || null,
        components: geocodeResult?.components || {},
        valid: geocodeResult?.success || false
      },
      solar: {
        roofArea: solarEstimate?.roofArea || 0,
        panelCount: solarEstimate?.maxArrayPanelsCount || 0,
        estimatedKwhPerYear: potentialKWh,
        estimatedCapacityKw: solarEstimate?.maxArrayCapacityWatts ? Math.round(solarEstimate.maxArrayCapacityWatts / 1000) : 0,
        orientation: solarEstimate?.panelOrientation || 'unknown',
        roofType: solarEstimate?.roofType || 'unknown',
        dataSource: solarEstimate?.source || 'unknown',
        confidence: solarEstimate?.confidence || 'low'
      },
      system: {
        estimatedCostEUR: systemCost?.estimatedCostEUR || 0,
        costPerKwh: systemCost?.costPerKwh || 0
      },
      qualification: {
        score: scoring?.totalScore || 0,
        category: scoring?.category || 'unknown',
        priority: scoring?.priority || 'P3 - Low',
        recommendation: scoring?.recommendation || ''
      },
      regional: {
        state: geocodeResult?.components?.state || '',
        solarIrradiance: regionalData?.solarIrradiance || 0,
        regionalBonus: regionalData?.regionalBonus || 1.0
      },
      enrichedAt: new Date().toISOString()
    };
  }

  getRegionalData(geocodeResult) {
    if (!geocodeResult || !geocodeResult.components || !geocodeResult.components.state) {
      return null;
    }

    const state = geocodeResult.components.state;
    return regionalSolarData.states[state] || null;
  }

  calculatePotentialKWh(solarEstimate, regionalData) {
    if (!solarEstimate || !regionalData) return 0;

    const baseKWh = solarEstimate.maxArrayEnergyProductionKwh || 0;
    const irradianceFactor = regionalData.solarIrradiance / 1050;
    const orientationFactor = this.getOrientationFactor(solarEstimate.panelOrientation);
    const roofTypeFactor = this.getRoofTypeFactor(solarEstimate.roofType);

    return Math.round(baseKWh * irradianceFactor * orientationFactor * roofTypeFactor);
  }

  estimateSystemCost(solarEstimate, regionalData) {
    const panelCount = solarEstimate?.maxArrayPanelsCount || 0;
    const baseCost = panelCount * 400 * 1.4;
    const regionalMultiplier = regionalData?.regionalBonus || 1.0;

    return {
      estimatedCostEUR: Math.round(baseCost * regionalMultiplier),
      costPerKwh: Math.round((baseCost * regionalMultiplier) / (solarEstimate?.maxArrayEnergyProductionKwh || 1) * 100) / 100
    };
  }
}

module.exports = ScoringService;
