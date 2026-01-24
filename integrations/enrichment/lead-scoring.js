const regionalWeights = require('../../config/regional-scoring-weights.json');

class LeadScoringService {
  constructor() {
    this.urgentKeywords = new RegExp(regionalWeights.urgent_keywords.join('|'), 'i');
    this.budgetSignals = new RegExp(regionalWeights.budget_signals.join('|'), 'i');
    this.freemailDomains = new Set(regionalWeights.freemail_domains);
    this.subsidyRegions = new Set(Object.keys(regionalWeights.subsidy_regions));
  }

  calculateLeadScore(lead) {
    let score = 0;
    const breakdown = {};

    breakdown.location = this.scoreLocation(lead);
    score += breakdown.location;

    breakdown.roofSize = this.scoreRoofSize(lead);
    score += breakdown.roofSize;

    breakdown.urgency = this.scoreUrgency(lead);
    score += breakdown.urgency;

    breakdown.contactQuality = this.scoreContactQuality(lead);
    score += breakdown.contactQuality;

    breakdown.responseTime = this.scoreResponseTime(lead);
    score += breakdown.responseTime;

    breakdown.budget = this.scoreBudget(lead);
    score += breakdown.budget;

    const finalScore = Math.min(score, 100);
    const priority = this.getPriority(finalScore);
    const category = this.getCategory(finalScore);

    return {
      score: finalScore,
      breakdown,
      priority,
      category,
      shouldAlert: finalScore > 80,
      autoLowPriority: finalScore < 30
    };
  }

  scoreLocation(lead) {
    const state = lead.address_state || '';
    if (this.subsidyRegions.has(state)) {
      const regionData = regionalWeights.subsidy_regions[state];
      return Math.round(30 * regionData.weight);
    }
    return 10;
  }

  scoreRoofSize(lead) {
    const roofArea = lead.roof_area_sqm || 0;
    if (roofArea > 80) return 25;
    if (roofArea > 60) return 20;
    if (roofArea > 40) return 15;
    if (roofArea > 20) return 10;
    return 0;
  }

  scoreUrgency(lead) {
    const notes = (lead.notes || '').toLowerCase();
    if (this.urgentKeywords.test(notes)) {
      return 20;
    }
    return 0;
  }

  scoreContactQuality(lead) {
    const email = (lead.email || '').toLowerCase();
    const domain = email.split('@')[1];

    if (!email || !domain) return 0;

    if (this.freemailDomains.has(domain)) {
      return 5;
    }

    if (domain.includes('.de')) {
      return 15;
    }

    return 12;
  }

  scoreResponseTime(lead) {
    const responseTime = lead.response_time_seconds || Infinity;
    if (responseTime < 180) return 15;
    if (responseTime < 300) return 10;
    if (responseTime < 600) return 5;
    return 0;
  }

  scoreBudget(lead) {
    const notes = (lead.notes || '').toLowerCase();
    if (this.budgetSignals.test(notes)) {
      return 20;
    }
    return 0;
  }

  getPriority(score) {
    if (score >= 80) return 'critical';
    if (score >= 60) return 'high';
    if (score >= 40) return 'medium';
    return 'low';
  }

  getCategory(score) {
    if (score >= 80) return 'hot-lead';
    if (score >= 60) return 'qualified';
    if (score >= 40) return 'warm-lead';
    return 'cold-lead';
  }

  getRegionalData(state) {
    return regionalWeights.subsidy_regions[state] || null;
  }

  getEstimatedProjectValue(lead) {
    const regionData = this.getRegionalData(lead.address_state);
    const baseValue = regionData?.avg_project_value || 15000;
    const roofMultiplier = Math.min(lead.roof_area_sqm / 60, 2);
    const scoreMultiplier = (this.calculateLeadScore(lead).score / 50);

    return Math.round(baseValue * roofMultiplier * scoreMultiplier);
  }
}

module.exports = LeadScoringService;
