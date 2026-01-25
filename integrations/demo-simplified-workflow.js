require('dotenv').config();

const { shouldCallNow, formatLeadSummary } = require('../integrations/enrichment/simple-lead-filter');
const { buildGoogleMapsLink, estimateDrivingTime, buildMultiStopRoute } = require('../integrations/telegram/maps-link');
const { optimizeRoute, formatRouteSummary } = require('../integrations/crm/route-optimizer');

const fs = require('fs');

async function demoSimplifiedWorkflow() {
  console.log('🔧 Simplified Installer Workflow Demo\n');

  const sampleLead = {
    id: '123e4567-e89b-12d3-a456-426614174000',
    name: 'Max Mustermann',
    phone: '+491721234567',
    roof_area_sqm: 45,
    distance_km: 12,
    is_owner: true,
    missed_calls: 0,
    interested: true,
    appointment_today: true,
    appointment_time: '14:30',
    latitude: 48.1351,
    longitude: 11.5820
  };

  console.log('1️⃣ Simple Lead Scoring');
  console.log('------------------------');
  const shouldCall = shouldCallNow(sampleLead);
  console.log(`Should call now? ${shouldCall ? '✅ YES' : '❌ NO'}`);
  console.log(`Summary: ${formatLeadSummary(sampleLead)}\n`);

  console.log('2️⃣ Google Maps Integration');
  console.log('---------------------------');
  const mapsUrl = buildGoogleMapsLink(sampleLead.latitude, sampleLead.longitude);
  console.log(`Maps Link: ${mapsUrl}`);
  
  const baseLocation = { lat: 48.1374, lon: 11.5755 };
  const drivingTime = await estimateDrivingTime(
    baseLocation.lat, baseLocation.lon,
    sampleLead.latitude, sampleLead.longitude
  );
  console.log(`Estimated driving time: ${drivingTime}\n`);

  console.log('3️⃣ Actionable Telegram Alert');
  console.log('-----------------------------');
  console.log('Alert would include:');
  console.log('  • One-line summary: ' + formatLeadSummary(sampleLead));
  console.log('  • Inline keyboard with buttons:');
  console.log('    - [Jetzt anrufen 📞] → tel:// link');
  console.log('    - [Google Maps 🗺️] → Maps link');
  console.log('    - [Später ⏰] → Schedule reminder');
  console.log('    - [Ablehnen ❌] → Mark as rejected');
  console.log('    - [Termin heute ✅] → Confirm appointment\n');

  console.log('4️⃣ Route Optimization');
  console.log('----------------------');
  const sampleAppointments = [
    {
      id: '1',
      name: 'Max Mustermann',
      address_street: 'Münchner Str. 12',
      latitude: 48.1351,
      longitude: 11.5820,
      appointment_time: '09:00'
    },
    {
      id: '2',
      name: 'Erika Musterfrau',
      address_street: 'Sendlinger Str. 45',
      latitude: 48.1308,
      longitude: 11.5748,
      appointment_time: '11:00'
    },
    {
      id: '3',
      name: 'Hans Schmidt',
      address_street: 'Tal 23',
      latitude: 48.1374,
      longitude: 11.5755,
      appointment_time: '14:00'
    }
  ];

  const routeResult = await optimizeRoute(sampleAppointments);
  console.log(formatRouteSummary(routeResult));
  const coordinates = routeResult.optimizedRoute.map(a => ({ lat: a.latitude, lon: a.longitude }));
  console.log(`Google Maps Multi-Stop URL: ${buildMultiStopRoute(coordinates)}\n`);

  console.log('5️⃣ Appointment Flags');
  console.log('---------------------');
  console.log('Database fields added:');
  console.log('  • appointment_today: BOOLEAN');
  console.log('  • appointment_time: TIME');
  console.log('  • appointment_confirmed: BOOLEAN');
  console.log('  • distance_km: DECIMAL');
  console.log('  • is_owner: BOOLEAN');
  console.log('  • missed_calls: INTEGER');
  console.log('  • interested: BOOLEAN\n');

  console.log('6️⃣ Google Sheets Export');
  console.log('------------------------');
  console.log('One-click export with:');
  console.log('  • Status-based colored rows');
  console.log('  • All lead data');
  console.log('  • Appointment views');
  console.log('  • Familiar interface for wife\n');

  console.log('✅ Demo Complete!');
  console.log('\nKey Improvements for Installers:');
  console.log('  • Binary decision: Call now/later/skip (no 100-point scoring)');
  console.log('  • One-click actions in Telegram (no reading long messages)');
  console.log('  • Google Maps integration (no manual address entry)');
  console.log('  • Route optimization (save fuel/time)');
  console.log('  • Appointment today flag (quick daily overview)');
  console.log('  • Google Sheets export (wife-friendly)');
}

if (require.main === module) {
  demoSimplifiedWorkflow().catch(console.error);
}

module.exports = { demoSimplifiedWorkflow };
