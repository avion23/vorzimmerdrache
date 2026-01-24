const PhoneValidation = (() => {
  const MOBILE_PREFIXES = ['15', '16', '17'];
  const MAJOR_CITY_CODES = ['30', '40', '89', '211', '69', '711', '6221', '221', '231', '251', '341', '351', '391', '410', '511', '531', '6151', '621', '6421', '721', '821', '911', '931', '941', '951', '961'];

  const PATTERNS = {
    E164: /^\+49[1-9]\d{8,12}$/,
    NATIONAL: /^0[1-9]\d{8,12}$/,
    MOBILE: /^(?:\+49|0049|0)(15[0-9]|16[0-9]|17[0-9])\d{7,8}$/,
    LANDLINE: /^(?:\+49|0049|0)(?!(15|16|17)\d)[1-9]\d{8,11}$/
  };

  function stripSpecialChars(phone) {
    return phone.replace(/[^\d+]/g, '');
  }

  function handleGermanNotation(phone) {
    return phone.replace(/\(0\)/g, '');
  }

  function detectType(normalized) {
    if (!normalized.startsWith('+49')) return null;

    const subscriber = normalized.substring(3);

    if (PATTERNS.MOBILE.test(normalized)) return 'mobile';
    if (PATTERNS.LANDLINE.test(normalized)) return 'landline';

    const firstThree = subscriber.substring(0, 3);
    if (MOBILE_PREFIXES.includes(firstThree)) return 'mobile';

    const firstTwo = subscriber.substring(0, 2);
    if (MOBILE_PREFIXES.includes(firstTwo)) return 'mobile';

    return 'landline';
  }

  function normalizeGermanPhone(phone) {
    if (!phone || typeof phone !== 'string') {
      return null;
    }

    let cleaned = handleGermanNotation(phone);
    cleaned = stripSpecialChars(cleaned);

    if (!cleaned) return null;

    if (cleaned.startsWith('+49')) return cleaned;
    if (cleaned.startsWith('0049')) return '+49' + cleaned.substring(4);
    if (cleaned.startsWith('0')) return '+49' + cleaned.substring(1);

    return cleaned;
  }

  function validateGermanPhone(phone) {
    if (!phone || typeof phone !== 'string') {
      return {
        valid: false,
        normalized: null,
        type: null,
        error: 'Phone must be a non-empty string'
      };
    }

    if (!phone.trim()) {
      return {
        valid: false,
        normalized: null,
        type: null,
        error: 'Phone number is empty after cleaning'
      };
    }

    const normalized = normalizeGermanPhone(phone);

    if (!normalized) {
      return {
        valid: false,
        normalized: null,
        type: null,
        error: 'Phone number is empty after cleaning'
      };
    }

    if (!normalized.startsWith('+49')) {
      return {
        valid: false,
        normalized: normalized,
        type: null,
        error: 'Not a German phone number (must start with +49, 0049, or 0)'
      };
    }

    const subscriber = normalized.substring(3);

    if (subscriber.startsWith('0')) {
      return {
        valid: false,
        normalized: normalized,
        type: null,
        error: 'Invalid trunk prefix (0) after country code'
      };
    }

    if (subscriber.length < 9 || subscriber.length > 13) {
      return {
        valid: false,
        normalized: normalized,
        type: null,
        error: `Invalid length: ${subscriber.length} digits after country code (expected 9-13)`
      };
    }

    if (!/^\d+$/.test(subscriber)) {
      return {
        valid: false,
        normalized: normalized,
        type: null,
        error: 'Phone number contains invalid characters'
      };
    }

    const type = detectType(normalized);

    return {
      valid: true,
      normalized,
      type
    };
  }

  function isValidE164(phone) {
    return PATTERNS.E164.test(phone);
  }

  function normalizeToE164(phone) {
    const result = validateGermanPhone(phone);
    return result.valid ? result.normalized : null;
  }

  return {
    validateGermanPhone,
    isValidE164,
    normalizeToE164,
    stripSpecialChars,
    detectType
  };
})();

module.exports = PhoneValidation;
