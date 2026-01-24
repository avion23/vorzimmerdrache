const SubsidyCalculator = require('../integrations/enrichment/subsidy-calculator');
const KfWApiService = require('../integrations/enrichment/kfw-api');

describe('SubsidyCalculator', () => {
  let calculator;

  beforeEach(() => {
    calculator = new SubsidyCalculator();
  });

  describe('calculateAnnuity', () => {
    test('should calculate monthly payment for loan', () => {
      const result = calculator.calculateAnnuity(100000, 0.015, 10);
      expect(result).toBeGreaterThan(0);
      expect(result).toBeLessThan(10000);
    });

    test('should return zero for zero principal', () => {
      const result = calculator.calculateAnnuity(0, 0.015, 10);
      expect(result).toBe(0);
    });

    test('should return zero for zero interest rate', () => {
      const result = calculator.calculateAnnuity(100000, 0, 10);
      expect(result).toBe(833.33);
    });

    test('should return zero for negative principal', () => {
      const result = calculator.calculateAnnuity(-100000, 0.015, 10);
      expect(result).toBe(0);
    });

    test('should return zero for zero years', () => {
      const result = calculator.calculateAnnuity(100000, 0.015, 0);
      expect(result).toBe(0);
    });
  });

  describe('calculateKfW270', () => {
    test('should calculate KfW 270 loan for PV system', () => {
      const result = calculator.calculateKfW270(25000, 10, 'pv');

      expect(result.eligible).toBe(true);
      expect(result.maxLoan).toBeLessThanOrEqual(25000 * 0.8);
      expect(result.maxLoan).toBeLessThanOrEqual(10 * 10000);
      expect(result.maxLoan).toBeLessThanOrEqual(50000000);
      expect(result.interestRate).toBe(0.015);
      expect(result.term).toBe(10);
      expect(result.monthlyPayment).toBeGreaterThan(0);
    });

    test('should limit loan to 80% of project cost', () => {
      const result = calculator.calculateKfW270(30000, 5, 'pv');

      expect(result.maxLoan).toBe(24000);
    });

    test('should limit loan to 10000 per kWp', () => {
      const result = calculator.calculateKfW270(100000, 8, 'pv');

      expect(result.maxLoan).toBe(80000);
    });

    test('should limit loan to 50M maximum', () => {
      const result = calculator.calculateKfW270(100000000, 6000, 'pv');

      expect(result.maxLoan).toBe(50000000);
    });

    test('should reject ineligible system type', () => {
      const result = calculator.calculateKfW270(25000, 10, 'solar_thermal');

      expect(result.eligible).toBe(false);
      expect(result.maxLoan).toBe(0);
      expect(result.reason).toContain('not eligible');
    });

    test('should handle battery system', () => {
      const result = calculator.calculateKfW270(15000, 5, 'battery');

      expect(result.eligible).toBe(true);
      expect(result.systemType).toBe('battery');
    });

    test('should handle heat pump system', () => {
      const result = calculator.calculateKfW270(20000, 8, 'heat_pump');

      expect(result.eligible).toBe(true);
      expect(result.systemType).toBe('heat_pump');
    });

    test('should return correct interest rate percentage', () => {
      const result = calculator.calculateKfW270(25000, 10, 'pv');

      expect(result.interestRatePercent).toBe(1.5);
    });

    test('should handle zero project cost', () => {
      const result = calculator.calculateKfW270(0, 10, 'pv');

      expect(result.maxLoan).toBe(0);
    });

    test('should handle zero roof size', () => {
      const result = calculator.calculateKfW270(25000, 0, 'pv');

      expect(result.maxLoan).toBe(0);
    });
  });

  describe('calculateBAFA', () => {
    test('should calculate BAFA subsidy for solar thermal', () => {
      const result = calculator.calculateBAFA(10);

      expect(result.eligible).toBe(true);
      expect(result.subsidy).toBe(3000);
      expect(result.subsidyPerKW).toBe(300);
      expect(result.systemSizeKW).toBe(10);
    });

    test('should cap subsidy at 30000', () => {
      const result = calculator.calculateBAFA(200);

      expect(result.eligible).toBe(true);
      expect(result.subsidy).toBe(30000);
      expect(result.maxSubsidy).toBe(30000);
    });

    test('should handle exactly 100 kW (max before cap)', () => {
      const result = calculator.calculateBAFA(100);

      expect(result.eligible).toBe(true);
      expect(result.subsidy).toBe(30000);
    });

    test('should handle just under 100 kW', () => {
      const result = calculator.calculateBAFA(99);

      expect(result.eligible).toBe(true);
      expect(result.subsidy).toBe(29700);
    });

    test('should reject zero system size', () => {
      const result = calculator.calculateBAFA(0);

      expect(result.eligible).toBe(false);
      expect(result.subsidy).toBe(0);
      expect(result.reason).toContain('greater than 0');
    });

    test('should reject negative system size', () => {
      const result = calculator.calculateBAFA(-10);

      expect(result.eligible).toBe(false);
      expect(result.subsidy).toBe(0);
    });

    test('should handle small system size', () => {
      const result = calculator.calculateBAFA(2);

      expect(result.eligible).toBe(true);
      expect(result.subsidy).toBe(600);
    });

    test('should return program details', () => {
      const result = calculator.calculateBAFA(10);

      expect(result.program).toContain('BAFA');
      expect(result.url).toContain('bafa.de');
    });
  });

  describe('calculateCombinedSubsidies', () => {
    test('should calculate both KfW and BAFA subsidies', () => {
      const result = calculator.calculateCombinedSubsidies(25000, 10, 'pv', true);

      expect(result.kfw.eligible).toBe(true);
      expect(result.bafa.eligible).toBe(true);
      expect(result.totalBenefit).toBe(result.kfw.maxLoan);
      expect(result.totalSubsidy).toBe(result.bafa.subsidy);
      expect(result.combinedValue).toBe(result.kfw.maxLoan + result.bafa.subsidy);
    });

    test('should calculate only KfW when BAFA is disabled', () => {
      const result = calculator.calculateCombinedSubsidies(25000, 10, 'pv', false);

      expect(result.kfw.eligible).toBe(true);
      expect(result.bafa.eligible).toBe(false);
      expect(result.totalSubsidy).toBe(0);
      expect(result.combinedValue).toBe(result.kfw.maxLoan);
    });

    test('should handle ineligible KfW system', () => {
      const result = calculator.calculateCombinedSubsidies(25000, 10, 'invalid_system', true);

      expect(result.kfw.eligible).toBe(false);
      expect(result.bafa.eligible).toBe(true);
      expect(result.totalBenefit).toBe(0);
      expect(result.combinedValue).toBe(result.bafa.subsidy);
    });

    test('should generate notes for eligible subsidies', () => {
      const result = calculator.calculateCombinedSubsidies(25000, 10, 'pv', true);

      expect(result.notes.length).toBeGreaterThan(0);
      expect(result.notes[0]).toContain('KfW 270');
      expect(result.notes[1]).toContain('BAFA');
    });

    test('should generate notes for only eligible subsidy', () => {
      const result = calculator.calculateCombinedSubsidies(25000, 10, 'pv', false);

      expect(result.notes.length).toBe(1);
      expect(result.notes[0]).toContain('KfW 270');
    });
  });

  describe('generateNotes', () => {
    test('should generate KfW note when eligible', () => {
      const kfwResult = {
        eligible: true,
        maxLoan: 20000,
        interestRatePercent: 1.5
      };
      const bafaResult = { eligible: false };

      const notes = calculator.generateNotes(kfwResult, bafaResult);

      expect(notes.length).toBe(1);
      expect(notes[0]).toContain('KfW 270');
      expect(notes[0]).toContain('20.000');
      expect(notes[0]).toContain('1.5%');
    });

    test('should generate BAFA note when eligible', () => {
      const kfwResult = { eligible: false };
      const bafaResult = {
        eligible: true,
        subsidy: 5000
      };

      const notes = calculator.generateNotes(kfwResult, bafaResult);

      expect(notes.length).toBe(1);
      expect(notes[0]).toContain('BAFA Zuschuss');
      expect(notes[0]).toContain('5.000');
    });

    test('should generate both notes when both eligible', () => {
      const kfwResult = {
        eligible: true,
        maxLoan: 20000,
        interestRatePercent: 1.5
      };
      const bafaResult = {
        eligible: true,
        subsidy: 5000
      };

      const notes = calculator.generateNotes(kfwResult, bafaResult);

      expect(notes.length).toBe(2);
      expect(notes[0]).toContain('KfW 270');
      expect(notes[1]).toContain('BAFA');
    });

    test('should return empty array when none eligible', () => {
      const kfwResult = { eligible: false };
      const bafaResult = { eligible: false };

      const notes = calculator.generateNotes(kfwResult, bafaResult);

      expect(notes.length).toBe(0);
    });
  });

  describe('validateEligibility', () => {
    test('should validate eligible PV system', () => {
      const result = calculator.validateEligibility('pv', 10);

      expect(result.kfw270).toBe(true);
      expect(result.bafa).toBe(false);
      expect(result.anyEligible).toBe(true);
    });

    test('should validate eligible battery system', () => {
      const result = calculator.validateEligibility('battery', 5);

      expect(result.kfw270).toBe(true);
      expect(result.bafa).toBe(false);
      expect(result.anyEligible).toBe(true);
    });

    test('should validate eligible heat pump system', () => {
      const result = calculator.validateEligibility('heat_pump', 8);

      expect(result.kfw270).toBe(true);
      expect(result.bafa).toBe(false);
      expect(result.anyEligible).toBe(true);
    });

    test('should validate eligible solar thermal system', () => {
      const result = calculator.validateEligibility('solar_thermal', 10);

      expect(result.kfw270).toBe(false);
      expect(result.bafa).toBe(true);
      expect(result.anyEligible).toBe(true);
    });

    test('should reject invalid system type', () => {
      const result = calculator.validateEligibility('invalid_type', 10);

      expect(result.kfw270).toBe(false);
      expect(result.bafa).toBe(false);
      expect(result.anyEligible).toBe(false);
    });

    test('should reject zero system size', () => {
      const result = calculator.validateEligibility('pv', 0);

      expect(result.kfw270).toBe(false);
      expect(result.bafa).toBe(false);
      expect(result.anyEligible).toBe(false);
    });

    test('should reject negative system size', () => {
      const result = calculator.validateEligibility('pv', -10);

      expect(result.kfw270).toBe(false);
      expect(result.bafa).toBe(false);
      expect(result.anyEligible).toBe(false);
    });
  });

  describe('formatForWhatsApp', () => {
    test('should format message with KfW only', () => {
      const subsidyResult = {
        kfw: { eligible: true, maxLoan: 20000 },
        bafa: { eligible: false }
      };

      const message = calculator.formatForWhatsApp('Hans', 8.5, subsidyResult);

      expect(message).toContain('Hans');
      expect(message).toContain('8.5');
      expect(message).toContain('20.000');
      expect(message).toContain('KfW 270 Kredit');
      expect(message).not.toContain('BAFA Zuschuss');
    });

    test('should format message with both subsidies', () => {
      const subsidyResult = {
        kfw: { eligible: true, maxLoan: 20000 },
        bafa: { eligible: true, subsidy: 3000 }
      };

      const message = calculator.formatForWhatsApp('Anna', 10, subsidyResult);

      expect(message).toContain('Anna');
      expect(message).toContain('10');
      expect(message).toContain('20.000');
      expect(message).toContain('3.000');
      expect(message).toContain('KfW 270 Kredit');
      expect(message).toContain('BAFA Zuschuss');
    });

    test('should handle ineligible case', () => {
      const subsidyResult = {
        kfw: { eligible: false, maxLoan: 0 },
        bafa: { eligible: false, subsidy: 0 }
      };

      const message = calculator.formatForWhatsApp('Peter', 5, subsidyResult);

      expect(message).toContain('Peter');
      expect(message).toContain('5');
      expect(message).toContain('0');
    });
  });

  describe('formatForLeadNotes', () => {
    test('should format KfW note', () => {
      const kfwResult = {
        eligible: true,
        maxLoan: 20000,
        interestRatePercent: 1.5
      };
      const bafaResult = { eligible: false };
      const subsidyResult = {
        kfw: kfwResult,
        bafa: bafaResult,
        notes: calculator.generateNotes(kfwResult, bafaResult)
      };

      const notes = calculator.formatForLeadNotes(subsidyResult);

      expect(notes).toContain('KfW 270');
      expect(notes).toContain('20.000');
      expect(notes).toContain('1.5%');
    });

    test('should format both KfW and BAFA notes', () => {
      const kfwResult = {
        eligible: true,
        maxLoan: 20000,
        interestRatePercent: 1.5
      };
      const bafaResult = {
        eligible: true,
        subsidy: 5000
      };
      const subsidyResult = {
        kfw: kfwResult,
        bafa: bafaResult,
        notes: calculator.generateNotes(kfwResult, bafaResult)
      };

      const notes = calculator.formatForLeadNotes(subsidyResult);

      expect(notes).toContain('KfW 270');
      expect(notes).toContain('BAFA Zuschuss');
    });

    test('should return empty string when none eligible', () => {
      const kfwResult = { eligible: false };
      const bafaResult = { eligible: false };
      const subsidyResult = {
        kfw: kfwResult,
        bafa: bafaResult,
        notes: calculator.generateNotes(kfwResult, bafaResult)
      };

      const notes = calculator.formatForLeadNotes(subsidyResult);

      expect(notes).toBe('');
    });
  });

  describe('loadConfig', () => {
    test('should load default config if file missing', () => {
      const config = calculator.config;

      expect(config.kfw_270).toBeDefined();
      expect(config.bafa_solar).toBeDefined();
      expect(config.kfw_270.max_loan_per_kwp).toBe(10000);
      expect(config.bafa_solar.subsidy_per_kw).toBe(300);
    });
  });

  describe('getCurrentInterestRate', () => {
    test('should return default rate when cache empty', () => {
      const rate = calculator.getCurrentInterestRate();

      expect(rate).toBe(0.015);
    });

    test('should return cached rate when available', () => {
      calculator.ratesCache = 0.018;
      calculator.ratesCacheTimestamp = Date.now();

      const rate = calculator.getCurrentInterestRate();

      expect(rate).toBe(0.018);
    });

    test('should return default rate when cache expired', () => {
      calculator.ratesCache = 0.018;
      calculator.ratesCacheTimestamp = Date.now() - (8 * 24 * 60 * 60 * 1000);

      const rate = calculator.getCurrentInterestRate();

      expect(rate).toBe(0.015);
    });
  });

  describe('edge cases', () => {
    test('should handle very large project cost', () => {
      const result = calculator.calculateKfW270(1000000000, 1000, 'pv');

      expect(result.maxLoan).toBe(10000000);
      expect(result.eligible).toBe(true);
    });

    test('should handle very small project cost', () => {
      const result = calculator.calculateKfW270(1000, 0.1, 'pv');

      expect(result.maxLoan).toBeLessThanOrEqual(800);
    });

    test('should handle floating point kWp values', () => {
      const result = calculator.calculateKfW270(25000, 8.5, 'pv');

      expect(result.eligible).toBe(true);
      expect(result.maxLoan).toBe(20000);
    });

    test('should handle BAFA with fractional kW', () => {
      const result = calculator.calculateBAFA(8.5);

      expect(result.eligible).toBe(true);
      expect(result.subsidy).toBe(2550);
    });

    test('should handle combined calculation with edge values', () => {
      const result = calculator.calculateCombinedSubsidies(1, 0.01, 'pv', false);

      expect(result.kfw.eligible).toBe(true);
      expect(result.combinedValue).toBeLessThanOrEqual(1);
    });
  });
});

describe('KfWApiService', () => {
  let apiService;

  beforeEach(() => {
    apiService = new KfWApiService();
  });

  describe('constructor', () => {
    test('should initialize with correct base URL', () => {
      expect(apiService.baseUrl).toBe('https://www.kfw.de');
    });

    test('should initialize cache TTL', () => {
      expect(apiService.cacheTTL).toBe(7 * 24 * 60 * 60 * 1000);
    });

    test('should load or create cache', () => {
      expect(apiService.cache).toBeDefined();
      expect(apiService.cache.rates).toBeDefined();
      expect(apiService.cache.rates.kfw270).toBeDefined();
    });
  });

  describe('loadCache', () => {
    test('should create default cache if file missing', () => {
      const service = new KfWApiService();

      expect(service.cache.rates.kfw270.effectiveRate).toBe(0.015);
      expect(service.cache.timestamp).toBe(0);
    });
  });

  describe('isCacheValid', () => {
    test('should return false for new cache', () => {
      const service = new KfWApiService();

      expect(service.isCacheValid()).toBe(false);
    });

    test('should return true for fresh cache', () => {
      apiService.cache.timestamp = Date.now();

      expect(apiService.isCacheValid()).toBe(true);
    });

    test('should return false for expired cache', () => {
      apiService.cache.timestamp = Date.now() - (8 * 24 * 60 * 60 * 1000);

      expect(apiService.isCacheValid()).toBe(false);
    });
  });

  describe('parseInterestRate', () => {
    test('should parse rate from HTML with comma', () => {
      const html = 'Der Zinssatz beträgt 1,5% effektiv';

      const rate = apiService.parseInterestRate(html);

      expect(rate).toBe(0.015);
    });

    test('should parse rate from HTML with different patterns', () => {
      const html = 'effektiv: 1,8 %';

      const rate = apiService.parseInterestRate(html);

      expect(rate).toBeCloseTo(0.018, 10);
    });

    test('should return default rate when no match found', () => {
      const html = 'Keine Zinsinformationen vorhanden';

      const rate = apiService.parseInterestRate(html);

      expect(rate).toBe(0.015);
    });

    test('should ignore rates outside valid range', () => {
      const html = 'Der Zinssatz beträgt 50% effektiv';

      const rate = apiService.parseInterestRate(html);

      expect(rate).toBe(0.015);
    });
  });

  describe('getProgramDetails', () => {
    test('should return details for KfW 270', () => {
      const details = apiService.getProgramDetails('270');

      expect(details).toBeDefined();
      expect(details.code).toBe('270');
      expect(details.type).toBe('loan');
      expect(details.eligibility.pv).toBe(true);
      expect(details.eligibility.battery).toBe(true);
      expect(details.eligibility.heat_pump).toBe(true);
      expect(details.eligibility.solar_thermal).toBe(false);
    });

    test('should return null for unknown program', () => {
      const details = apiService.getProgramDetails('999');

      expect(details).toBeNull();
    });
  });

  describe('getBAFAInfo', () => {
    test('should return BAFA program details', async () => {
      const info = await apiService.getBAFAInfo();

      expect(info).toBeDefined();
      expect(info.name).toContain('BAFA');
      expect(info.type).toBe('grant');
      expect(info.subsidyPerKW).toBe(300);
      expect(info.maxSubsidy).toBe(30000);
      expect(info.eligibility.solar_thermal).toBe(true);
      expect(info.eligibility.pv).toBe(false);
    });
  });

  describe('checkProgramEligibility', () => {
    test('should validate eligible PV project', async () => {
      const projectDetails = {
        systemType: 'pv',
        capacityKW: 10,
        projectCost: 25000,
        location: 'DE'
      };

      const result = await apiService.checkProgramEligibility('270', projectDetails);

      expect(result.eligible).toBe(true);
      expect(result.maxLoan).toBeGreaterThan(0);
    });

    test('should reject ineligible system type', async () => {
      const projectDetails = {
        systemType: 'solar_thermal',
        capacityKW: 10,
        projectCost: 25000,
        location: 'DE'
      };

      const result = await apiService.checkProgramEligibility('270', projectDetails);

      expect(result.eligible).toBe(false);
      expect(result.reason).toContain('not eligible');
    });

    test('should reject capacity below minimum', async () => {
      const projectDetails = {
        systemType: 'pv',
        capacityKW: 0.5,
        projectCost: 25000,
        location: 'DE'
      };

      const result = await apiService.checkProgramEligibility('270', projectDetails);

      expect(result.eligible).toBe(false);
      expect(result.reason).toContain('too low');
    });

    test('should reject capacity above maximum', async () => {
      const projectDetails = {
        systemType: 'pv',
        capacityKW: 60000,
        projectCost: 25000,
        location: 'DE'
      };

      const result = await apiService.checkProgramEligibility('270', projectDetails);

      expect(result.eligible).toBe(false);
      expect(result.reason).toContain('too high');
    });

    test('should reject non-German location', async () => {
      const projectDetails = {
        systemType: 'pv',
        capacityKW: 10,
        projectCost: 25000,
        location: 'AT'
      };

      const result = await apiService.checkProgramEligibility('270', projectDetails);

      expect(result.eligible).toBe(false);
      expect(result.reason).toContain('Only German projects');
    });
  });

  describe('getCacheStatus', () => {
    test('should return cache status', () => {
      apiService.cache.timestamp = Date.now() - (2 * 60 * 60 * 1000);
      apiService.cache.rates.kfw270.effectiveRate = 0.018;
      apiService.cache.rates.kfw270.lastUpdated = '2025-01-25T00:00:00.000Z';

      const status = apiService.getCacheStatus();

      expect(status.valid).toBe(true);
      expect(status.ageHours).toBe(2);
      expect(status.currentRate).toBe(0.018);
      expect(status.lastUpdated).toBe('2025-01-25T00:00:00.000Z');
    });

    test('should show expired cache', () => {
      apiService.cache.timestamp = Date.now() - (10 * 24 * 60 * 60 * 1000);

      const status = apiService.getCacheStatus();

      expect(status.valid).toBe(false);
      expect(status.ageHours).toBeGreaterThan(168);
    });
  });

  describe('updateRateFromConfig', () => {
    test('should update rate with valid value', () => {
      const result = apiService.updateRateFromConfig(0.018);

      expect(result.rates.kfw270.effectiveRate).toBe(0.018);
      expect(result.rates.kfw270.lastUpdated).toBeDefined();
    });

    test('should reject rate above 1', () => {
      expect(() => apiService.updateRateFromConfig(1.5))
        .toThrow('Invalid interest rate');
    });

    test('should reject negative rate', () => {
      expect(() => apiService.updateRateFromConfig(-0.01))
        .toThrow('Invalid interest rate');
    });

    test('should reject non-numeric rate', () => {
      expect(() => apiService.updateRateFromConfig('invalid'))
        .toThrow('Invalid interest rate');
    });
  });
});
