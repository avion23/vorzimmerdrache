const assert = require('assert');
const LeadScoringService = require('../integrations/enrichment/lead-scoring');

describe('LeadScoringService', () => {
  let scorer;

  beforeEach(() => {
    scorer = new LeadScoringService();
  });

  describe('calculateLeadScore', () => {
    it('should score hot lead correctly', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 80,
        email: 'contact@solar-company.de',
        response_time_seconds: 120,
        notes: 'sofort möglich, finanzierung geklärt'
      };

      const result = scorer.calculateLeadScore(lead);

      assert(result.score > 80, 'Hot lead should score above 80');
      assert.strictEqual(result.priority, 'critical');
      assert.strictEqual(result.category, 'hot-lead');
      assert.strictEqual(result.shouldAlert, true);
    });

    it('should score cold lead correctly', () => {
      const lead = {
        address_state: 'Berlin',
        roof_area_sqm: 30,
        email: 'test@gmail.com',
        response_time_seconds: 1800,
        notes: 'vielleicht später'
      };

      const result = scorer.calculateLeadScore(lead);

      assert(result.score < 40, 'Cold lead should score below 40');
      assert.strictEqual(result.priority, 'low');
      assert.strictEqual(result.category, 'cold-lead');
    });

    it('should cap score at 100', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 150,
        email: 'contact@big-corp.de',
        response_time_seconds: 60,
        notes: 'sofort dringend, finanzierung geklärt, jetzt möglich'
      };

      const result = scorer.calculateLeadScore(lead);

      assert.strictEqual(result.score, 100, 'Score should be capped at 100');
    });

    it('should handle missing fields gracefully', () => {
      const lead = {
        address_state: null,
        roof_area_sqm: null,
        email: null,
        response_time_seconds: null,
        notes: null
      };

      const result = scorer.calculateLeadScore(lead);

      assert(result.score >= 0, 'Score should be non-negative');
      assert(result.score <= 100, 'Score should be capped at 100');
    });
  });

  describe('scoreLocation', () => {
    it('should give higher score to subsidy regions', () => {
      const bayern = { address_state: 'Bayern' };
      const berlin = { address_state: 'Berlin' };

      const bayernScore = scorer.scoreLocation(bayern);
      const berlinScore = scorer.scoreLocation(berlin);

      assert(bayernScore > berlinScore, 'Bayern should score higher than Berlin');
    });

    it('should apply regional weight correctly', () => {
      const bayern = { address_state: 'Bayern' };
      const nrw = { address_state: 'Nordrhein-Westfalen' };

      const bayernScore = scorer.scoreLocation(bayern);
      const nrwScore = scorer.scoreLocation(nrw);

      assert(bayernScore > nrwScore, 'Bayern weight (1.2) should be higher than NRW (1.1)');
    });
  });

  describe('scoreRoofSize', () => {
    it('should give higher scores for larger roofs', () => {
      const largeRoof = { roof_area_sqm: 100 };
      const mediumRoof = { roof_area_sqm: 50 };
      const smallRoof = { roof_area_sqm: 10 };

      assert.strictEqual(scorer.scoreRoofSize(largeRoof), 25);
      assert.strictEqual(scorer.scoreRoofSize(mediumRoof), 15);
      assert.strictEqual(scorer.scoreRoofSize(smallRoof), 0);
    });
  });

  describe('scoreUrgency', () => {
    it('should detect urgent keywords', () => {
      const urgentLead = { notes: 'Wir wollen sofort anfangen' };
      const normalLead = { notes: 'Wir überlegen uns das' };

      assert.strictEqual(scorer.scoreUrgency(urgentLead), 20);
      assert.strictEqual(scorer.scoreUrgency(normalLead), 0);
    });

    it('should be case insensitive', () => {
      const lead1 = { notes: 'SOFORT möglich' };
      const lead2 = { notes: 'sofort möglich' };
      const lead3 = { notes: 'SoFoRt möglich' };

      assert.strictEqual(scorer.scoreUrgency(lead1), 20);
      assert.strictEqual(scorer.scoreUrgency(lead2), 20);
      assert.strictEqual(scorer.scoreUrgency(lead3), 20);
    });
  });

  describe('scoreContactQuality', () => {
    it('should prefer business emails over freemail', () => {
      const businessEmail = { email: 'contact@solar-company.de' };
      const freemailEmail = { email: 'test@gmail.com' };

      assert(scorer.scoreContactQuality(businessEmail) > scorer.scoreContactQuality(freemailEmail));
    });

    it('should prefer German business domains', () => {
      const deDomain = { email: 'contact@firma.de' };
      const comDomain = { email: 'contact@company.com' };

      assert(scorer.scoreContactQuality(deDomain) > scorer.scoreContactQuality(comDomain));
    });

    it('should handle missing email', () => {
      const lead = { email: null };
      assert.strictEqual(scorer.scoreContactQuality(lead), 0);
    });
  });

  describe('scoreResponseTime', () => {
    it('should reward fast response times', () => {
      const fast = { response_time_seconds: 60 };
      const medium = { response_time_seconds: 240 };
      const slow = { response_time_seconds: 900 };

      assert(scorer.scoreResponseTime(fast) > scorer.scoreResponseTime(medium));
      assert(scorer.scoreResponseTime(medium) > scorer.scoreResponseTime(slow));
    });

    it('should cap at 15 points', () => {
      const instant = { response_time_seconds: 1 };
      assert.strictEqual(scorer.scoreResponseTime(instant), 15);
    });
  });

  describe('scoreBudget', () => {
    it('should detect budget signals', () => {
      const budgetReady = { notes: 'Finanzierung geklärt' };
      const noBudget = { notes: 'Wir müssen noch schauen' };

      assert.strictEqual(scorer.scoreBudget(budgetReady), 20);
      assert.strictEqual(scorer.scoreBudget(noBudget), 0);
    });
  });

  describe('getPriority', () => {
    it('should return correct priority levels', () => {
      assert.strictEqual(scorer.getPriority(90), 'critical');
      assert.strictEqual(scorer.getPriority(70), 'high');
      assert.strictEqual(scorer.getPriority(50), 'medium');
      assert.strictEqual(scorer.getPriority(20), 'low');
    });
  });

  describe('getCategory', () => {
    it('should return correct categories', () => {
      assert.strictEqual(scorer.getCategory(85), 'hot-lead');
      assert.strictEqual(scorer.getCategory(65), 'qualified');
      assert.strictEqual(scorer.getCategory(45), 'warm-lead');
      assert.strictEqual(scorer.getCategory(25), 'cold-lead');
    });
  });

  describe('getRegionalData', () => {
    it('should return correct regional data', () => {
      const bayernData = scorer.getRegionalData('Bayern');

      assert(bayernData !== null);
      assert.strictEqual(bayernData.weight, 1.2);
      assert.strictEqual(bayernData.avg_project_value, 18000);
    });

    it('should return null for unknown region', () => {
      const result = scorer.getRegionalData('UnknownState');
      assert.strictEqual(result, null);
    });
  });

  describe('getEstimatedProjectValue', () => {
    it('should calculate project value based on region and roof size', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 60
      };

      const value = scorer.getEstimatedProjectValue(lead);

      assert(value > 0);
      assert(value >= 18000, 'Bayern should have base value of 18000');
    });

    it('should adjust value based on roof size', () => {
      const smallRoof = {
        address_state: 'Bayern',
        roof_area_sqm: 30
      };
      const largeRoof = {
        address_state: 'Bayern',
        roof_area_sqm: 90
      };

      const smallValue = scorer.getEstimatedProjectValue(smallRoof);
      const largeValue = scorer.getEstimatedProjectValue(largeRoof);

      assert(largeValue > smallValue, 'Larger roof should have higher value');
    });
  });

  describe('edge cases', () => {
    it('should handle empty notes', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 60,
        email: 'test@gmail.com',
        response_time_seconds: 300,
        notes: ''
      };

      const result = scorer.calculateLeadScore(lead);

      assert(result.score >= 0);
      assert(result.score <= 100);
    });

    it('should handle zero roof area', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 0,
        email: 'test@gmail.com',
        response_time_seconds: 300,
        notes: ''
      };

      const result = scorer.calculateLeadScore(lead);

      assert.strictEqual(result.breakdown.roofSize, 0);
    });

    it('should handle null email domain correctly', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 60,
        email: null,
        response_time_seconds: 300,
        notes: ''
      };

      const result = scorer.calculateLeadScore(lead);

      assert.strictEqual(result.breakdown.contactQuality, 0);
    });

    it('should detect multiple budget signals', () => {
      const lead = {
        address_state: 'Bayern',
        roof_area_sqm: 60,
        email: 'contact@company.de',
        response_time_seconds: 120,
        notes: 'finanzierung geklärt, barzahlung möglich'
      };

      const result = scorer.calculateLeadScore(lead);

      assert.strictEqual(result.breakdown.budget, 20);
    });
  });
});
