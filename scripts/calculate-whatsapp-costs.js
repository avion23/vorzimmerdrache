#!/usr/bin/env node

const readline = require('readline');

const TWILIO_WHATSAPP_COST_PER_CONVERSATION = 0.0156;
const TWILIO_WHATSAPP_COST_PER_MESSAGE = 0.0058;
const WAHA_COST_PER_MESSAGE = 0;
const RISK_FINE_AMOUNT = 5000;
const RISK_PROBABILITY_PERCENT = 5;

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

function question(prompt) {
  return new Promise(resolve => {
    rl.question(prompt, resolve);
  });
}

function formatCurrency(amount) {
  return new Intl.NumberFormat('de-DE', {
    style: 'currency',
    currency: 'EUR'
  }).format(amount);
}

function calculateTwilioCosts(leadsPerMonth, conversationsPerLead = 2) {
  const conversationsPerMonth = leadsPerMonth * conversationsPerLead;
  const monthlyCost = conversationsPerMonth * TWILIO_WHATSAPP_COST_PER_CONVERSATION;
  const annualCost = monthlyCost * 12;
  return { monthlyCost, annualCost, conversationsPerMonth };
}

function calculateRiskAdjustedCost(twilioAnnualCost, probabilityPercent) {
  const expectedFine = RISK_FINE_AMOUNT * (probabilityPercent / 100);
  return twilioAnnualCost + expectedFine;
}

function calculateBreakEven(twilioAnnualCost, riskAnnualCost) {
  return {
    withoutRisk: twilioAnnualCost,
    withRisk: riskAnnualCost
  };
}

function displayComparison(leadsPerMonth, twilio, riskAnnualCost, breakEven) {
  console.log('\n=== WhatsApp Cost Analysis ===\n');

  console.log('Input Parameters:');
  console.log(`  Leads per month: ${leadsPerMonth}`);
  console.log(`  Conversations per lead: 2`);
  console.log(`  Risk probability: ${RISK_PROBABILITY_PERCENT}%`);
  console.log(`  Potential fine: ${formatCurrency(RISK_FINE_AMOUNT)}\n`);

  console.log('WAHA (Self-Hosted):');
  console.log(`  Cost per message: ${formatCurrency(WAHA_COST_PER_MESSAGE)}`);
  console.log(`  Monthly cost: ${formatCurrency(0)}`);
  console.log(`  Annual cost: ${formatCurrency(0)}\n`);

  console.log('Twilio WhatsApp Business API:');
  console.log(`  Cost per conversation: ${formatCurrency(TWILIO_WHATSAPP_COST_PER_CONVERSATION)}`);
  console.log(`  Cost per additional message: ${formatCurrency(TWILIO_WHATSAPP_COST_PER_MESSAGE)}`);
  console.log(`  Conversations per month: ${twilio.conversationsPerMonth}`);
  console.log(`  Monthly cost: ${formatCurrency(twilio.monthlyCost)}`);
  console.log(`  Annual cost: ${formatCurrency(twilio.annualCost)}\n`);

  console.log('Risk-Adjusted Analysis (WAHA):');
  console.log(`  Expected risk cost per year: ${formatCurrency(RISK_FINE_AMOUNT * (RISK_PROBABILITY_PERCENT / 100))}`);
  console.log(`  Total annual cost: ${formatCurrency(riskAnnualCost)}\n`);

  console.log('Break-Even Point:');
  console.log(`  Twilio is cheaper than WAHA (with risk):`);
  console.log(`    ${formatCurrency(twilio.annualCost)} < ${formatCurrency(riskAnnualCost)}`);
  console.log(`  Savings per year (with Twilio): ${formatCurrency(riskAnnualCost - twilio.annualCost)}\n`);

  const twilioCheaper = twilio.annualCost < riskAnnualCost;
  console.log('Recommendation:');
  if (twilioCheaper) {
    console.log('  ✅ Use Twilio WhatsApp - cheaper even when accounting for compliance risk');
  } else {
    console.log('  ℹ️  WAHA is cheaper, but consider:');
    console.log('     - Legal compliance requirements (GDPR, WhatsApp ToS)');
    console.log('     - Maintenance and hosting costs for WAHA');
    console.log('     - Risk of message delivery issues');
  }

  console.log('\nAdditional Considerations:');
  console.log('  - WAHA: Requires infrastructure, maintenance, legal compliance');
  console.log('  - Twilio: Fully managed, compliant, enterprise support');
  console.log('  - WAHA risk: Violates WhatsApp Business API ToS (banned approach)');
}

async function main() {
  console.log('\nTwilio WhatsApp Cost Calculator');

  let leadsPerMonth;

  if (process.argv[2] && !isNaN(parseInt(process.argv[2]))) {
    leadsPerMonth = parseInt(process.argv[2]);
    console.log(`Using ${leadsPerMonth} leads/month from command line\n`);
  } else {
    const input = await question('Enter number of leads per month: ');
    leadsPerMonth = parseInt(input);
  }

  if (isNaN(leadsPerMonth) || leadsPerMonth < 0) {
    console.error('Invalid input. Please enter a positive number.');
    rl.close();
    process.exit(1);
  }

  const twilio = calculateTwilioCosts(leadsPerMonth);
  const riskAnnualCost = calculateRiskAdjustedCost(twilio.annualCost, RISK_PROBABILITY_PERCENT);

  displayComparison(leadsPerMonth, twilio, riskAnnualCost, null);

  rl.close();
}

main().catch(err => {
  console.error('Error:', err.message);
  rl.close();
  process.exit(1);
});
