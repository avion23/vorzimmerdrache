const PhoneValidation = require('./phone-validation');

function assertEqual(actual, expected, message) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`FAIL: ${message}\nExpected: ${JSON.stringify(expected)}\nActual: ${JSON.stringify(actual)}`);
  }
  console.log(`✓ ${message}`);
}

function testGroup(name) {
  console.log(`\n${name}`);
  console.log('='.repeat(50));
}

let passed = 0;
let failed = 0;

function runTest(fn, name) {
  try {
    fn();
    passed++;
  } catch (error) {
    failed++;
    console.log(`✗ ${name}: ${error.message}`);
  }
}

testGroup('Empty and Invalid Inputs');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('');
  assertEqual(result.valid, false, 'Empty string');
  assertEqual(result.error, 'Phone must be a non-empty string', 'Correct error for empty string');
}, 'Empty string');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone(null);
  assertEqual(result.valid, false, 'Null input');
  assertEqual(result.error, 'Phone must be a non-empty string', 'Correct error for null');
}, 'Null input');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone(undefined);
  assertEqual(result.valid, false, 'Undefined input');
}, 'Undefined input');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('   ');
  assertEqual(result.valid, false, 'Whitespace only');
  assertEqual(result.error, 'Phone number is empty after cleaning', 'Correct error for whitespace');
}, 'Whitespace only');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('abc');
  assertEqual(result.valid, false, 'Letters only');
  assertEqual(result.error, 'Phone number is empty after cleaning', 'Correct error for letters');
}, 'Letters only');

testGroup('Mobile Numbers - National Format (0xxx)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('015123456789');
  assertEqual(result.valid, true, 'Valid 015x mobile');
  assertEqual(result.normalized, '+4915123456789', 'Normalized correctly');
  assertEqual(result.type, 'mobile', 'Detected as mobile');
}, 'Mobile 0151xxxxxxxxx');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('016012345678');
  assertEqual(result.valid, true, 'Valid 016x mobile');
  assertEqual(result.normalized, '+4916012345678', 'Normalized correctly');
  assertEqual(result.type, 'mobile', 'Detected as mobile');
}, 'Mobile 0160xxxxxxxx');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('017912345678');
  assertEqual(result.valid, true, 'Valid 017x mobile');
  assertEqual(result.normalized, '+4917912345678', 'Normalized correctly');
  assertEqual(result.type, 'mobile', 'Detected as mobile');
}, 'Mobile 0179xxxxxxxx');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+49 151 234 567 89');
  assertEqual(result.valid, true, 'Valid mobile with spaces');
  assertEqual(result.normalized, '+4915123456789', 'Normalized correctly');
  assertEqual(result.type, 'mobile', 'Detected as mobile');
}, 'Mobile with spaces and +49');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0049 151 234 567 89');
  assertEqual(result.valid, true, 'Valid mobile with 0049');
  assertEqual(result.normalized, '+4915123456789', 'Normalized correctly');
  assertEqual(result.type, 'mobile', 'Detected as mobile');
}, 'Mobile with 0049');

testGroup('Landline Numbers - Major Cities');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0301234567');
  assertEqual(result.valid, true, 'Valid Berlin landline');
  assertEqual(result.normalized, '+49301234567', 'Normalized correctly');
  assertEqual(result.type, 'landline', 'Detected as landline');
}, 'Landline Berlin (030)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0401234567');
  assertEqual(result.valid, true, 'Valid Hamburg landline');
  assertEqual(result.normalized, '+49401234567', 'Normalized correctly');
  assertEqual(result.type, 'landline', 'Detected as landline');
}, 'Landline Hamburg (040)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0891234567');
  assertEqual(result.valid, true, 'Valid Munich landline');
  assertEqual(result.normalized, '+49891234567', 'Normalized correctly');
  assertEqual(result.type, 'landline', 'Detected as landline');
}, 'Landline Munich (089)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+49 30 1234567');
  assertEqual(result.valid, true, 'Berlin landline with +49');
  assertEqual(result.normalized, '+49301234567', 'Normalized correctly');
  assertEqual(result.type, 'landline', 'Detected as landline');
}, 'Berlin landline with +49');

testGroup('Special Characters and Formats');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('(0151) 234-567.89');
  assertEqual(result.valid, true, 'Valid mobile with parentheses, dash, dot');
  assertEqual(result.normalized, '+4915123456789', 'Normalized correctly');
  assertEqual(result.type, 'mobile', 'Detected as mobile');
}, 'Mobile with multiple special chars');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('030/1234567');
  assertEqual(result.valid, true, 'Landline with slash');
  assertEqual(result.normalized, '+49301234567', 'Normalized correctly');
  assertEqual(result.type, 'landline', 'Detected as landline');
}, 'Landline with slash');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+49 (0)30 1234567');
  assertEqual(result.valid, true, 'German international format with (0)');
  assertEqual(result.normalized, '+49301234567', 'Normalized with (0) removed');
}, 'German international with (0)');

testGroup('International Non-German Numbers');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+33612345678');
  assertEqual(result.valid, false, 'French number rejected');
  assertEqual(result.error.includes('Not a German phone number'), true, 'Correct error message');
}, 'French number (+33)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+441234567890');
  assertEqual(result.valid, false, 'UK number rejected');
}, 'UK number (+44)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('001234567890');
  assertEqual(result.valid, false, 'US number rejected with trunk prefix error');
  assertEqual(result.error.includes('Invalid trunk prefix'), true, 'Correct error for US number');
}, 'US number (001)');

testGroup('Edge Cases');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0151');
  assertEqual(result.valid, false, 'Too short mobile');
  assertEqual(result.error.includes('Invalid length'), true, 'Correct error for too short');
}, 'Too short (4 digits)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('030');
  assertEqual(result.valid, false, 'Too short landline');
}, 'Too short landline (3 digits)');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+490123456789012');
  assertEqual(result.valid, false, 'Trunk prefix after country code');
  assertEqual(result.error.includes('Invalid trunk prefix'), true, 'Correct error message');
}, 'Trunk prefix after +49');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+49151234567890123');
  assertEqual(result.valid, false, 'Very long mobile');
}, 'Very long mobile number');

runTest(() => {
  const normalized = PhoneValidation.normalizeToE164('015123456789');
  assertEqual(normalized, '+4915123456789', 'normalizeToE164 returns E.164');
}, 'normalizeToE164 helper');

runTest(() => {
  const isValid = PhoneValidation.isValidE164('+4915123456789');
  assertEqual(isValid, true, 'Valid E.164 detected');
}, 'isValidE164 returns true');

runTest(() => {
  const isValid = PhoneValidation.isValidE164('015123456789');
  assertEqual(isValid, false, 'Non-E.164 rejected');
}, 'isValidE164 rejects national format');

testGroup('Real Customer Scenarios');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0157 / 123 456');
  assertEqual(result.valid, true, 'Customer with slash and spaces');
  assertEqual(result.normalized, '+49157123456', 'Normalized correctly');
}, 'DIY customer: mobile with slash and spaces');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('+49 (0) 171 234 567-8');
  assertEqual(result.valid, true, 'Customer using (0) notation');
  assertEqual(result.normalized, '+491712345678', 'Normalized correctly with (0) removed');
}, 'DIY customer: (0) notation');

runTest(() => {
  const result = PhoneValidation.validateGermanPhone('0049 160 / 123 4567');
  assertEqual(result.valid, true, 'Customer using 0049 prefix');
  assertEqual(result.normalized, '+491601234567', 'Normalized correctly');
}, 'DIY customer: 0049 prefix');

console.log('\n' + '='.repeat(50));
console.log(`Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
