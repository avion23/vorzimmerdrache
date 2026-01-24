const fs = require('fs');
const path = require('path');
const https = require('https');
const axios = require('axios');

class KfWApiService {
  constructor() {
    this.baseUrl = 'https://www.kfw.de';
    this.cachePath = path.join(__dirname, '../../config/.kfw-rates-cache.json');
    this.cache = this.loadCache();
    this.cacheTTL = 7 * 24 * 60 * 60 * 1000;
  }

  loadCache() {
    try {
      const cacheData = fs.readFileSync(this.cachePath, 'utf8');
      const parsed = JSON.parse(cacheData);

      if (Date.now() - parsed.timestamp < this.cacheTTL) {
        return parsed;
      }
    } catch (error) {
    }

    return {
      timestamp: 0,
      rates: {
        kfw270: {
          effectiveRate: 0.015,
          lastUpdated: null
        }
      }
    };
  }

  saveCache() {
    try {
      this.cache.timestamp = Date.now();
      fs.writeFileSync(this.cachePath, JSON.stringify(this.cache, null, 2));
    } catch (error) {
      console.log(`Failed to save cache: ${error.message}`);
    }
  }

  async getCurrentRates() {
    if (this.isCacheValid()) {
      return this.cache.rates;
    }

    try {
      const freshRates = await this.fetchRates();
      this.cache.rates = freshRates;
      this.saveCache();
      return freshRates;
    } catch (error) {
      console.log(`Using cached rates due to fetch failure: ${error.message}`);
      return this.cache.rates;
    }
  }

  isCacheValid() {
    return this.cache.timestamp > 0 && (Date.now() - this.cache.timestamp) < this.cacheTTL;
  }

  async fetchRates() {
    try {
      const htmlData = await this.fetchPage('/inlandsfoerderung/Privatpersonen/Bestehende-Immobilie/F%C3%B6rderprodukte/Erneuerbare-Energien-Standard-(270)/');
      const rate = this.parseInterestRate(htmlData);

      return {
        kfw270: {
          effectiveRate: rate,
          lastUpdated: new Date().toISOString()
        }
      };
    } catch (error) {
      throw new Error(`Failed to fetch KfW rates: ${error.message}`);
    }
  }

  async fetchPage(relativePath) {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: 'www.kfw.de',
        path: relativePath,
        method: 'GET',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive'
        }
      };

      https.get(options, (res) => {
        let data = '';

        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            resolve(data);
          } else {
            reject(new Error(`HTTP ${res.statusCode}`));
          }
        });
      }).on('error', reject);
    });
  }

  parseInterestRate(html) {
    const ratePatterns = [
      /effektiv[\s:]*([0-9]+,[0-9]+)\s*%/i,
      /zinssatz[\s:]*([0-9]+,[0-9]+)\s*%/i,
      /([0-9],[0-9]{1,2})\s*%\s*effektiv/i,
      /kondition.*?([0-9]+,[0-9]+)\s*%/i
    ];

    for (const pattern of ratePatterns) {
      const match = html.match(pattern);
      if (match && match[1]) {
        const rateString = match[1].replace(',', '.');
        const rate = parseFloat(rateString);
        if (!isNaN(rate) && rate >= 0.5 && rate <= 10) {
          return rate / 100;
        }
      }
    }

    return 0.015;
  }

  async checkProgramEligibility(programCode, projectDetails) {
    const eligibilityRules = {
      '270': {
        name: 'KfW 270 - Erneuerbare Energien - Standard',
        requires: {
          systemType: ['pv', 'battery', 'heat_pump'],
          minCapacity: 1,
          maxCapacity: 50000,
          location: 'DE'
        },
        limits: {
          maxLoanPerKWp: 10000,
          maxTotalLoan: 50000000
        }
      }
    };

    const program = eligibilityRules[programCode];

    if (!program) {
      return {
        eligible: false,
        reason: 'Unknown program code'
      };
    }

    if (!program.requires.systemType.includes(projectDetails.systemType)) {
      return {
        eligible: false,
        reason: `System type '${projectDetails.systemType}' not eligible`
      };
    }

    if (projectDetails.capacityKW < program.requires.minCapacity) {
      return {
        eligible: false,
        reason: `Capacity too low (min ${program.requires.minCapacity} kW)`
      };
    }

    if (projectDetails.capacityKW > program.requires.maxCapacity) {
      return {
        eligible: false,
        reason: `Capacity too high (max ${program.requires.maxCapacity} kW)`
      };
    }

    if (projectDetails.location && projectDetails.location !== 'DE') {
      return {
        eligible: false,
        reason: 'Only German projects eligible'
      };
    }

    const maxLoan = Math.min(
      projectDetails.capacityKW * program.limits.maxLoanPerKWp,
      program.limits.maxTotalLoan,
      projectDetails.projectCost * 0.8
    );

    return {
      eligible: true,
      program: program.name,
      maxLoan: maxLoan,
      details: program
    };
  }

  getProgramDetails(programCode) {
    const programs = {
      '270': {
        code: '270',
        name: 'Erneuerbare Energien - Standard',
        fullName: 'KfW 270 - Erneuerbare Energien - Standard',
        url: 'https://www.kfw.de/inlandsfoerderung/Privatpersonen/Bestehende-Immobilie/F%C3%B6rderprodukte/Erneuerbare-Energien-Standard-(270)/',
        type: 'loan',
        description: 'Günstige Kredite für Photovoltaikanlagen, Batteriespeicher und Wärmepumpen',
        eligibility: {
          pv: true,
          battery: true,
          heat_pump: true,
          solar_thermal: false
        },
        terms: {
          maxLoan: 50000000,
          maxLoanPerKWp: 10000,
          termYears: 10,
          repaymentFreeYears: 2
        },
        documents: [
          'Antrag',
          'Kostenvoranschlag',
          'Nachweis über Eigentum'
        ]
      }
    };

    return programs[programCode] || null;
  }

  async getBAFAInfo() {
    return {
      name: 'BAFA - Bundesförderung für effiziente Gebäude',
      url: 'https://www.bafa.de/DE/Energie/Effiziente_Gebaeude/effiziente_gebaeude_node.html',
      type: 'grant',
      description: 'Zuschüsse für Solarthermie und effiziente Gebäudetechnik',
      subsidyPerKW: 300,
      maxSubsidy: 30000,
      eligibility: {
        solar_thermal: true,
        pv: false,
        battery: false,
        heat_pump: true
      },
      terms: {
        maxSubsidy: 30000,
        maxSubsidyPercentage: 30,
        documents: [
          'Antrag',
          'Kostenvoranschlag',
          'Nachweis über Installateur'
        ]
      }
    };
  }

  updateRateFromConfig(manualRate) {
    if (typeof manualRate !== 'number' || manualRate < 0 || manualRate > 1) {
      throw new Error('Invalid interest rate. Must be between 0 and 1 (e.g., 0.015 for 1.5%)');
    }

    if (!this.cache.rates) {
      this.cache.rates = {
        kfw270: {
          effectiveRate: 0.015,
          lastUpdated: null
        }
      };
    }

    this.cache.rates.kfw270.effectiveRate = manualRate;
    this.cache.rates.kfw270.lastUpdated = new Date().toISOString();
    this.saveCache();

    return this.cache;
  }

  getCacheStatus() {
    const age = Date.now() - this.cache.timestamp;
    const valid = age < this.cacheTTL;
    const expiresAt = new Date(this.cache.timestamp + this.cacheTTL);

    return {
      valid,
      age,
      ageHours: Math.round(age / (1000 * 60 * 60)),
      expiresAt,
      currentRate: this.cache.rates.kfw270.effectiveRate,
      lastUpdated: this.cache.rates.kfw270.lastUpdated
    };
  }
}

module.exports = KfWApiService;
