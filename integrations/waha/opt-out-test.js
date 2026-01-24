const MessageService = require('./message-service');
const { Pool } = require('pg');

const config = {
  wahaBaseUrl: process.env.WAHA_API_URL || 'http://localhost:3000',
  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID,
    authToken: process.env.TWILIO_AUTH_TOKEN,
    phoneNumber: process.env.TWILIO_PHONE_NUMBER
  },
  sessionId: 'default',
  pgPool: new Pool({
    host: process.env.PGHOST || 'localhost',
    port: process.env.PGPORT || 5432,
    database: process.env.PGDATABASE || 'vorzimmerdrache',
    user: process.env.PGUSER || 'postgres',
    password: process.env.PGPASSWORD
  })
};

const messageService = new MessageService(config);

async function testOptOutStatus() {
  const testPhones = [
    '+491701234567',
    '+4915112345678'
  ];

  console.log('Testing opt-out status checks...\n');

  for (const phone of testPhones) {
    const status = await messageService.checkOptOutStatus(phone);
    console.log(`Phone: ${phone}`);
    console.log(`  Opted out: ${status.optedOut}`);
    console.log(`  Lead exists: ${status.leadExists}`);
    console.log();
  }

  await config.pgPool.end();
}

async function simulateOptOutWorkflow(phone) {
  console.log(`\nSimulating opt-out workflow for ${phone}...`);

  try {
    const result = await config.pgPool.query(
      'UPDATE leads SET opted_out = TRUE, opted_out_at = NOW() WHERE phone = $1 RETURNING id, name',
      [phone]
    );

    if (result.rows.length > 0) {
      console.log(`  ✓ Marked ${result.rows[0].name} as opted out`);
      
      await config.pgPool.query(
        'INSERT INTO opt_out_events (lead_id, channel, keyword_used) VALUES ($1, $2, $3)',
        [result.rows[0].id, 'test', 'STOP']
      );
      console.log(`  ✓ Logged opt-out event`);
    } else {
      console.log(`  ! Lead not found`);
    }
  } catch (error) {
    console.error(`  ✗ Error: ${error.message}`);
  } finally {
    await config.pgPool.end();
  }
}

const args = process.argv.slice(2);
const command = args[0];
const phone = args[1];

if (command === 'status') {
  testOptOutStatus();
} else if (command === 'opt-out' && phone) {
  simulateOptOutWorkflow(phone);
} else {
  console.log('Usage: node opt-out-test.js status');
  console.log('       node opt-out-test.js opt-out +4912345678');
}
