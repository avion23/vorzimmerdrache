const EnrichmentOrchestrator = require('./orchestrator');

async function main() {
  const config = {
    geocodingApiKey: process.env.GOOGLE_MAPS_API_KEY,
    solarApiKey: process.env.GOOGLE_SOLAR_API_KEY,
    batchSize: 10,
    batchDelay: 1000
  };

  const orchestrator = new EnrichmentOrchestrator(config);

  const validation = orchestrator.validateConfig();
  console.log('Config validation:', validation);

  const sampleLead = {
    id: 'lead-001',
    name: 'Max Mustermann',
    email: 'max@example.com',
    phone: '+49 123 456789',
    address: 'Musterstraße 42, 80331 München',
    leadSource: 'website'
  };

  console.log('Enriching lead:', sampleLead.id);

  try {
    const result = await orchestrator.enrichLead(sampleLead);

    if (result.success) {
      console.log('Enrichment successful!');
      console.log('Score:', result.lead.qualification.score);
      console.log('Category:', result.lead.qualification.category);
      console.log('Priority:', result.lead.qualification.priority);
      console.log('Roof Area:', result.lead.solar.roofArea, 'm²');
      console.log('Est. Annual Production:', result.lead.solar.estimatedKwhPerYear, 'kWh');
      console.log('Est. System Cost:', result.lead.system.estimatedCostEUR, 'EUR');
    } else {
      console.log('Enrichment failed:', result.error);
    }
  } catch (error) {
    console.error('Error:', error.message);
  }
}

if (require.main === module) {
  main();
}

module.exports = main;
