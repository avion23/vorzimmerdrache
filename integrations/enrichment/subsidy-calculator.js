const fs = require('fs');
const path = require('path');
const https = require('https');

class SubsidyCalculator {
  constructor() {
    this.configPath = path.join(__dirname, '../../config/subsidy-programs.json');
    this.config = this.loadConfig();
    this.ratesCache = null;
    this.ratesCacheTimestamp = null;
    this.ratesCacheTTL = 7 * 24 * 60 * 60 * 1000;
  }

  loadConfig() {
    try {
      const configData = fs.readFileSync(this.configPath, 'utf8');
      return JSON.parse(configData);
    } catch (error) {
      return this.getDefaultConfig();
    }
  }

  getDefaultConfig() {
    return {
      kfw_270: {
        name: 'KfW 270 - Erneuerbare Energien - Standard',
        url: 'https://www.kfw.de/inlandsfoerderung/Privatpersonen/Bestehende-Immobilie/F%C3%B6rderprodukte/Erneuerbare-Energien-Standard-(270)/',
        max_loan_per_kwp: 10000,
        interest_rate_range: [0.01, 0.025],
        eligible_systems: ['pv', 'battery', 'heat_pump'],
        default_interest_rate: 0.015
      },
      bafa_solar: {
        name: 'BAFA - Bundesförderung für effiziente Gebäude',
        url: 'https://www.bafa.de/DE/Energie/Effiziente_Gebaeude/effiziente_gebaeude_node.html',
        subsidy_per_kw: 300,
        max_subsidy: 30000
      }
    };
  }

  calculateAnnuity(principal, annualRate, years) {
    if (principal <= 0 || years <= 0) {
      return 0;
    }

    const monthlyRate = annualRate / 12;
    const numPayments = years * 12;

    if (monthlyRate === 0) {
      return Math.round((principal / numPayments) * 100) / 100;
    }

    const annuity = principal * (monthlyRate * Math.pow(1 + monthlyRate, numPayments)) / (Math.pow(1 + monthlyRate, numPayments) - 1);
    return Math.round(annuity * 100) / 100;
  }

  calculateKfW270(projectCost, roofSizeKWp, systemType = 'pv') {
    const kfwConfig = this.config.kfw_270;

    if (!kfwConfig.eligible_systems.includes(systemType)) {
      return {
        eligible: false,
        reason: `System type '${systemType}' is not eligible for KfW 270`,
        maxLoan: 0,
        interestRate: kfwConfig.default_interest_rate,
        monthlyPayment: 0
      };
    }

    const maxLoanByKwp = roofSizeKWp * kfwConfig.max_loan_per_kwp;
    const maxLoanByCost = projectCost * 0.8;
    const maxLoan = Math.min(maxLoanByKwp, maxLoanByCost, 50000000);

    const interestRate = this.getCurrentInterestRate() || kfwConfig.default_interest_rate;
    const term = 10;
    const monthlyPayment = this.calculateAnnuity(maxLoan, interestRate, term);

    return {
      eligible: true,
      program: kfwConfig.name,
      url: kfwConfig.url,
      maxLoan: Math.round(maxLoan),
      interestRate: interestRate,
      interestRatePercent: Math.round(interestRate * 10000) / 100,
      term: term,
      monthlyPayment: monthlyPayment,
      systemType: systemType
    };
  }

  calculateBAFA(systemSizeKW) {
    const bafaConfig = this.config.bafa_solar;

    if (systemSizeKW <= 0) {
      return {
        eligible: false,
        reason: 'System size must be greater than 0',
        subsidy: 0
      };
    }

    const baseSubsidy = systemSizeKW * bafaConfig.subsidy_per_kw;
    const subsidy = Math.min(baseSubsidy, bafaConfig.max_subsidy);

    return {
      eligible: true,
      program: bafaConfig.name,
      url: bafaConfig.url,
      subsidy: subsidy,
      subsidyPerKW: bafaConfig.subsidy_per_kw,
      maxSubsidy: bafaConfig.max_subsidy,
      systemSizeKW: systemSizeKW
    };
  }

  calculateCombinedSubsidies(projectCost, roofSizeKWp, systemType = 'pv', includeBAFA = false) {
    const kfwResult = this.calculateKfW270(projectCost, roofSizeKWp, systemType);
    const bafaResult = includeBAFA ? this.calculateBAFA(roofSizeKWp) : { eligible: false };

    const totalBenefit = kfwResult.eligible ? kfwResult.maxLoan : 0;
    const totalSubsidy = bafaResult.eligible ? bafaResult.subsidy : 0;

    return {
      kfw: kfwResult,
      bafa: bafaResult,
      totalBenefit: totalBenefit,
      totalSubsidy: totalSubsidy,
      combinedValue: totalBenefit + totalSubsidy,
      notes: this.generateNotes(kfwResult, bafaResult)
    };
  }

  generateNotes(kfwResult, bafaResult) {
    const notes = [];

    if (kfwResult.eligible) {
      notes.push(`KfW 270: bis €${kfwResult.maxLoan.toLocaleString('de-DE')} verfügbar bei ${kfwResult.interestRatePercent}% Zinsen`);
    }

    if (bafaResult.eligible) {
      notes.push(`BAFA Zuschuss: bis €${bafaResult.subsidy.toLocaleString('de-DE')}`);
    }

    return notes;
  }

  async fetchCurrentRates() {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: 'www.kfw.de',
        path: '/api/interest-rates',
        method: 'GET',
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json'
        }
      };

      https.get(options, (res) => {
        let data = '';

        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const response = JSON.parse(data);
            resolve(this.parseRatesResponse(response));
          } catch (error) {
            reject(new Error(`Failed to parse rates: ${error.message}`));
          }
        });
      }).on('error', (error) => {
        reject(error);
      });
    });
  }

  parseRatesResponse(response) {
    if (response.kfw270 && response.kfw270.effectiveRate) {
      return response.kfw270.effectiveRate;
    }

    return null;
  }

  getCurrentInterestRate() {
    if (this.ratesCache && Date.now() - this.ratesCacheTimestamp < this.ratesCacheTTL) {
      return this.ratesCache;
    }

    return this.config.kfw_270.default_interest_rate;
  }

  async updateRates() {
    try {
      const rate = await this.fetchCurrentRates();
      if (rate && rate >= this.config.kfw_270.interest_rate_range[0] && rate <= this.config.kfw_270.interest_rate_range[1]) {
        this.ratesCache = rate;
        this.ratesCacheTimestamp = Date.now();
        return rate;
      }
    } catch (error) {
      console.log(`Failed to update rates: ${error.message}`);
    }

    return this.config.kfw_270.default_interest_rate;
  }

  formatForWhatsApp(leadName, kwp, subsidyResult) {
    const kfw = subsidyResult.kfw;
    const bafa = subsidyResult.bafa;
    const kfwAmount = kfw.eligible ? kfw.maxLoan.toLocaleString('de-DE') : '0';
    const bafaAmount = bafa.eligible ? bafa.subsidy.toLocaleString('de-DE') : '0';

    return `👋 Moin ${leadName}!

Gute Nachrichten: Dein Dach eignet sich für ~${kwp} kWp Solaranlage!

💶 Förderung möglich:
• KfW 270 Kredit: bis €${kfwAmount} zu 1.5% Zinsen${bafa.eligible ? `\n• BAFA Zuschuss: bis €${bafaAmount}` : ''}

Interesse? Ich ruf dich an sobald ich vom Dach runter bin! ☀️`;
  }

  formatForLeadNotes(subsidyResult) {
    if (!subsidyResult || !subsidyResult.notes || !Array.isArray(subsidyResult.notes)) {
      return '';
    }
    return subsidyResult.notes.join('\n');
  }

  validateEligibility(systemType, systemSizeKW) {
    const kfwEligible = this.config.kfw_270.eligible_systems.includes(systemType) && systemSizeKW > 0;
    const bafaEligible = systemType === 'solar_thermal' && systemSizeKW > 0;

    return {
      kfw270: kfwEligible,
      bafa: bafaEligible,
      anyEligible: kfwEligible || bafaEligible
    };
  }
}

module.exports = SubsidyCalculator;
