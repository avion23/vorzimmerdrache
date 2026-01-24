const PhoneValidation = {
  validateGermanPhone(phone) {
    if (!phone || typeof phone !== 'string') {
      return {
        valid: false,
        normalized: null,
        error: 'Phone must be a non-empty string'
      };
    }

    const cleaned = phone.replace(/[\s\-\(\)\.]/g, '');

    if (!cleaned) {
      return {
        valid: false,
        normalized: null,
        error: 'Phone number is empty after cleaning'
      };
    }

    const e164Pattern = /^\+49[1-9]\d{8,12}$/;
    const nationalPattern = /^0[1-9]\d{8,12}$/;

    let normalized = cleaned;

    if (cleaned.startsWith('00')) {
      normalized = '+' + cleaned.substring(2);
    } else if (cleaned.startsWith('0')) {
      normalized = '+49' + cleaned.substring(1);
    }

    const isValidE164 = e164Pattern.test(normalized);

    if (isValidE164) {
      return {
        valid: true,
        normalized: normalized,
        format: 'E.164',
        countryCode: '+49',
        nationalNumber: normalized.substring(3)
      };
    }

    const isValidNational = nationalPattern.test(cleaned);

    if (isValidNational) {
      normalized = '+49' + cleaned.substring(1);
      return {
        valid: true,
        normalized: normalized,
        format: 'E.164',
        countryCode: '+49',
        nationalNumber: normalized.substring(3)
      };
    }

    const areaCodePattern = /^(030|040|089|0211|069|0711|06221|0221|0231|0251|0341|0351|0391|0410[1-9]|0511|0531|06151|0621|06421|0711|0721|0821|089|0911|0931|0941|0951|0961)[1-9]\d{5,9}$/;
    if (areaCodePattern.test(cleaned)) {
      normalized = '+49' + cleaned.substring(1);
      return {
        valid: true,
        normalized: normalized,
        format: 'E.164',
        countryCode: '+49',
        nationalNumber: normalized.substring(3),
        areaCode: cleaned.substring(0, cleaned.length > 3 ? 4 : 3)
      };
    }

    if (!cleaned.startsWith('+49') && !cleaned.startsWith('00') && !cleaned.startsWith('0')) {
      return {
        valid: false,
        normalized: cleaned,
        error: 'Phone number must start with +49, 0049, or 0 for German numbers'
      };
    }

    if (cleaned.startsWith('+49') || cleaned.startsWith('00')) {
      const number = cleaned.startsWith('+49') ? cleaned.substring(3) : cleaned.substring(4);
      if (number.length < 10 || number.length > 13) {
        return {
          valid: false,
          normalized: cleaned,
          error: 'German phone numbers must have 10-13 digits after country code'
        };
      }
    }

    return {
      valid: false,
      normalized: cleaned,
      error: 'Invalid German phone number format'
    };
  },

  isValidE164(phone) {
    if (!phone || typeof phone !== 'string') {
      return false;
    }

    const cleaned = phone.replace(/[\s\-\(\)\.]/g, '');
    const e164Pattern = /^\+49[1-9]\d{8,12}$/;

    return e164Pattern.test(cleaned);
  },

  normalizeToE164(phone) {
    const result = this.validateGermanPhone(phone);

    if (result.valid) {
      return result.normalized;
    }

    return null;
  }
};

module.exports = PhoneValidation;
