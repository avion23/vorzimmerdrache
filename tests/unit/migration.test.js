const PhoneValidation = require('../../integrations/utils/phone-validation');

function parseAddress(addressRaw) {
  if (!addressRaw) {
    return {
      address_raw: addressRaw,
      address_street: null,
      address_city: null,
      address_postal_code: null,
      address_state: null
    };
  }

  let street = null;
  let city = null;
  let postalCode = null;

  const patterns = [
    { regex: /^(.+?),\s*(\d{5})\s*(.+)$/, groups: ['street', 'postalCode', 'city'] },
    { regex: /^(\d{5})\s+(.+?),\s*(.+)$/, groups: ['postalCode', 'city', 'street'] },
    { regex: /^(.+?),\s*(.+)$/, groups: ['street', 'city'] }
  ];

  for (const { regex, groups } of patterns) {
    const match = addressRaw.match(regex);
    if (match) {
      if (groups[0] === 'street') {
        street = match[1]?.trim() || null;
        postalCode = groups.includes('postalCode') ? (match[2]?.trim() || null) : null;
        city = groups.includes('city') ? (match[groups.length === 3 ? 3 : 2]?.trim() || null) : null;
      } else if (groups[0] === 'postalCode') {
        postalCode = match[1]?.trim() || null;
        city = match[2]?.trim() || null;
        street = groups.includes('street') ? (match[3]?.trim() || null) : null;
      }
      break;
    }
  }

  if (!street && !city) {
    const parts = addressRaw.split(',').map(p => p.trim());
    if (parts.length >= 2) {
      street = parts[0] || null;
      city = parts.slice(1).join(', ') || null;
    } else {
      street = addressRaw;
    }
  }

  return {
    address_raw: addressRaw,
    address_street: street,
    address_city: city,
    address_postal_code: postalCode,
    address_state: null
  };
}

describe('Migration: Phone Normalization', () => {
  test('normalizes various German phone formats to E.164', () => {
    const testCases = [
      { input: '+49 89 1234567', expected: '+49891234567' },
      { input: '+49891234567', expected: '+49891234567' },
      { input: '089 1234567', expected: '+49891234567' },
      { input: '089-1234567', expected: '+49891234567' },
      { input: '0049 89 1234567', expected: '+49891234567' },
      { input: '+49 30 2345678', expected: '+49302345678' },
      { input: '030 2345678', expected: '+49302345678' },
      { input: '+49 151 12345678', expected: '+4915112345678' },
      { input: '0151 12345678', expected: '+4915112345678' }
    ];

    for (const { input, expected } of testCases) {
      const result = PhoneValidation.validateGermanPhone(input);
      expect(result.valid).toBe(true);
      expect(result.normalized).toBe(expected);
    }
  });

  test('rejects invalid phone numbers', () => {
    const invalidCases = [
      '12345',
      '+44 20 1234 5678',
      'not a phone',
      '',
      '+49 0 123456789'
    ];

    for (const input of invalidCases) {
      const result = PhoneValidation.validateGermanPhone(input);
      expect(result.valid).toBe(false);
    }
  });
});

describe('Migration: Address Parsing', () => {
  test('parses German addresses with postal code first', () => {
    const result = parseAddress('80331 München, Hauptstraße 42');
    expect(result.address_postal_code).toBe('80331');
    expect(result.address_city).toBe('München');
    expect(result.address_street).toBe('Hauptstraße 42');
  });

  test('parses German addresses with postal code second', () => {
    const result = parseAddress('Hauptstraße 42, 80331 München');
    expect(result.address_postal_code).toBe('80331');
    expect(result.address_city).toBe('München');
    expect(result.address_street).toBe('Hauptstraße 42');
  });

  test('handles simple comma-separated addresses', () => {
    const result = parseAddress('Hauptstraße 42, München');
    expect(result.address_street).toBe('Hauptstraße 42');
    expect(result.address_city).toBe('München');
    expect(result.address_postal_code).toBeNull();
  });

  test('handles single-field addresses', () => {
    const result = parseAddress('Hauptstraße 42');
    expect(result.address_street).toBe('Hauptstraße 42');
    expect(result.address_city).toBeNull();
    expect(result.address_postal_code).toBeNull();
  });

  test('handles empty/null addresses', () => {
    const emptyResult = parseAddress('');
    expect(emptyResult.address_raw).toBe('');
    expect(emptyResult.address_street).toBeNull();
    expect(emptyResult.address_city).toBeNull();

    const nullResult = parseAddress(null);
    expect(nullResult.address_raw).toBeNull();
    expect(nullResult.address_street).toBeNull();
    expect(nullResult.address_city).toBeNull();
  });
});

describe('Migration: Priority Parsing', () => {
  function parsePriority(value) {
    if (!value) return 0;
    const normalized = String(value).toLowerCase();
    if (normalized === 'urgent' || normalized === '2') return 2;
    if (normalized === 'high' || normalized === '1') return 1;
    return 0;
  }

  test('parses various priority formats', () => {
    expect(parsePriority('urgent')).toBe(2);
    expect(parsePriority('2')).toBe(2);
    expect(parsePriority('high')).toBe(1);
    expect(parsePriority('1')).toBe(1);
    expect(parsePriority('normal')).toBe(0);
    expect(parsePriority('0')).toBe(0);
    expect(parsePriority(null)).toBe(0);
    expect(parsePriority(undefined)).toBe(0);
  });
});
