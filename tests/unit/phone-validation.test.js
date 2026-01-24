const PhoneValidation = require('../../integrations/utils/phone-validation');

describe('PhoneValidation', () => {
  describe('validateGermanPhone', () => {
    describe('Invalid Input', () => {
      test('should reject null input', () => {
        const result = PhoneValidation.validateGermanPhone(null);
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone must be a non-empty string');
        expect(result.normalized).toBeNull();
      });

      test('should reject undefined input', () => {
        const result = PhoneValidation.validateGermanPhone(undefined);
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone must be a non-empty string');
        expect(result.normalized).toBeNull();
      });

      test('should reject empty string', () => {
        const result = PhoneValidation.validateGermanPhone('');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone must be a non-empty string');
        expect(result.normalized).toBeNull();
      });

      test('should reject non-string input', () => {
        const result = PhoneValidation.validateGermanPhone(1234567890);
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone must be a non-empty string');
        expect(result.normalized).toBeNull();
      });

      test('should reject object input', () => {
        const result = PhoneValidation.validateGermanPhone({ phone: '123' });
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone must be a non-empty string');
        expect(result.normalized).toBeNull();
      });

      test('should reject array input', () => {
        const result = PhoneValidation.validateGermanPhone(['1234567890']);
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone must be a non-empty string');
        expect(result.normalized).toBeNull();
      });

      test('should reject string with only spaces', () => {
        const result = PhoneValidation.validateGermanPhone('   ');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number is empty after cleaning');
        expect(result.normalized).toBeNull();
      });

      test('should reject string with only dashes', () => {
        const result = PhoneValidation.validateGermanPhone('---');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number is empty after cleaning');
        expect(result.normalized).toBeNull();
      });

      test('should reject string with only special characters', () => {
        const result = PhoneValidation.validateGermanPhone('()-. ');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number is empty after cleaning');
        expect(result.normalized).toBeNull();
      });
    });

    describe('Valid E.164 Format (+49)', () => {
      test('should accept valid E.164 format with mobile number', () => {
        const result = PhoneValidation.validateGermanPhone('+4915112345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
        expect(result.format).toBe('E.164');
        expect(result.countryCode).toBe('+49');
        expect(result.nationalNumber).toBe('15112345678');
      });

      test('should accept valid E.164 format with landline (Berlin)', () => {
        const result = PhoneValidation.validateGermanPhone('+493012345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+493012345678');
        expect(result.countryCode).toBe('+49');
        expect(result.nationalNumber).toBe('3012345678');
      });

      test('should accept valid E.164 format with landline (Munich)', () => {
        const result = PhoneValidation.validateGermanPhone('+498912345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+498912345678');
        expect(result.countryCode).toBe('+49');
        expect(result.nationalNumber).toBe('8912345678');
      });

      test('should accept valid E.164 with 10 digits after country code', () => {
        const result = PhoneValidation.validateGermanPhone('+491511234567');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+491511234567');
      });

      test('should accept valid E.164 with 13 digits after country code', () => {
        const result = PhoneValidation.validateGermanPhone('+49151123456789');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+49151123456789');
      });
    });

    describe('Valid National Format (0)', () => {
      test('should accept valid national format with mobile', () => {
        const result = PhoneValidation.validateGermanPhone('015112345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
        expect(result.format).toBe('E.164');
        expect(result.countryCode).toBe('+49');
        expect(result.nationalNumber).toBe('15112345678');
      });

      test('should accept valid national format with landline (Berlin)', () => {
        const result = PhoneValidation.validateGermanPhone('03012345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+493012345678');
        expect(result.countryCode).toBe('+49');
      });

      test('should accept valid national format with landline (Hamburg)', () => {
        const result = PhoneValidation.validateGermanPhone('04012345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+494012345678');
      });

      test('should accept valid national format with landline (Frankfurt)', () => {
        const result = PhoneValidation.validateGermanPhone('06912345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+496912345678');
      });

      test('should accept valid national format with landline (Stuttgart)', () => {
        const result = PhoneValidation.validateGermanPhone('071112345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4971112345678');
      });
    });

    describe('Valid 00 Prefix Format', () => {
      test('should accept valid format with 0049 prefix', () => {
        const result = PhoneValidation.validateGermanPhone('004915112345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
        expect(result.format).toBe('E.164');
        expect(result.countryCode).toBe('+49');
      });

      test('should accept valid format with 0049 and landline', () => {
        const result = PhoneValidation.validateGermanPhone('00493012345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+493012345678');
      });
    });

    describe('Valid German Area Codes', () => {
      test('should accept Berlin (030) area code', () => {
        const result = PhoneValidation.validateGermanPhone('030123456');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4930123456');
        expect(result.areaCode).toBe('0301');
      });

      test('should accept Hamburg (040) area code', () => {
        const result = PhoneValidation.validateGermanPhone('040123456');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4940123456');
        expect(result.areaCode).toBe('0401');
      });

      test('should accept Munich (089) area code', () => {
        const result = PhoneValidation.validateGermanPhone('089123456');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4989123456');
        expect(result.areaCode).toBe('0891');
      });

      test('should accept Frankfurt (069) area code', () => {
        const result = PhoneValidation.validateGermanPhone('069123456');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4969123456');
        expect(result.areaCode).toBe('0691');
      });
    });

    describe('Numbers with Spaces and Dashes', () => {
      test('should accept E.164 with spaces', () => {
        const result = PhoneValidation.validateGermanPhone('+49 151 12345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept E.164 with dashes', () => {
        const result = PhoneValidation.validateGermanPhone('+49-151-12345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept E.164 with parentheses', () => {
        const result = PhoneValidation.validateGermanPhone('+49(151)12345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept E.164 with dots', () => {
        const result = PhoneValidation.validateGermanPhone('+49.151.12345678');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept E.164 with mixed formatting', () => {
        const result = PhoneValidation.validateGermanPhone('+49 (151) 123-456.78');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept national format with spaces', () => {
        const result = PhoneValidation.validateGermanPhone('0151 123 456 78');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept national format with dashes', () => {
        const result = PhoneValidation.validateGermanPhone('0151-123-456-78');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should accept national format with area code and spaces', () => {
        const result = PhoneValidation.validateGermanPhone('030 123 456');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4930123456');
      });

      test('should accept 00 format with spaces', () => {
        const result = PhoneValidation.validateGermanPhone('00 49 151 123 456 78');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });
    });

    describe('Invalid Formats', () => {
      test('should reject missing country code without 0 prefix', () => {
        const result = PhoneValidation.validateGermanPhone('15112345678');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number must start with +49, 0049, or 0 for German numbers');
        expect(result.normalized).toBe('15112345678');
      });

      test('should reject wrong country code', () => {
        const result = PhoneValidation.validateGermanPhone('+43123456789');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number must start with +49, 0049, or 0 for German numbers');
        expect(result.normalized).toBe('+43123456789');
      });

      test('should reject US number format', () => {
        const result = PhoneValidation.validateGermanPhone('+12025551234');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number must start with +49, 0049, or 0 for German numbers');
      });

      test('should reject UK number format', () => {
        const result = PhoneValidation.validateGermanPhone('+441234567890');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number must start with +49, 0049, or 0 for German numbers');
      });

      test('should reject E.164 with zero after country code', () => {
        const result = PhoneValidation.validateGermanPhone('+4901512345678');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Invalid German phone number format');
      });

      test('should reject E.164 with too few digits (8)', () => {
        const result = PhoneValidation.validateGermanPhone('+4915123456');
        expect(result.valid).toBe(false);
      });

      test('should reject E.164 with too many digits (14)', () => {
        const result = PhoneValidation.validateGermanPhone('+49151234567890');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('German phone numbers must have 10-13 digits after country code');
      });

      test('should reject 00 prefix with zero after country code', () => {
        const result = PhoneValidation.validateGermanPhone('004901512345678');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Invalid German phone number format');
      });

      test('should reject 00 prefix with too few digits', () => {
        const result = PhoneValidation.validateGermanPhone('004915123456');
        expect(result.valid).toBe(false);
      });

      test('should reject 00 prefix with too many digits', () => {
        const result = PhoneValidation.validateGermanPhone('00491512345678901');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('German phone numbers must have 10-13 digits after country code');
      });

      test('should reject invalid characters', () => {
        const result = PhoneValidation.validateGermanPhone('+49abc1234567');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Invalid German phone number format');
      });

      test('should reject letters in number', () => {
        const result = PhoneValidation.validateGermanPhone('0151abcdefgh');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Invalid German phone number format');
      });

      test('should reject special characters beyond formatting', () => {
        const result = PhoneValidation.validateGermanPhone('+49151123*45678');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Invalid German phone number format');
      });
    });

    describe('Edge Cases', () => {
      test('should handle leading/trailing whitespace', () => {
        const result = PhoneValidation.validateGermanPhone('  +4915112345678  ');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+4915112345678');
      });

      test('should handle only formatting characters', () => {
        const result = PhoneValidation.validateGermanPhone(' - . () ');
        expect(result.valid).toBe(false);
        expect(result.error).toBe('Phone number is empty after cleaning');
      });

      test('should accept minimum valid length (10 digits)', () => {
        const result = PhoneValidation.validateGermanPhone('+491511234567');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+491511234567');
      });

      test('should accept maximum valid length (13 digits)', () => {
        const result = PhoneValidation.validateGermanPhone('+49151123456789');
        expect(result.valid).toBe(true);
        expect(result.normalized).toBe('+49151123456789');
      });
    });
  });

  describe('isValidE164', () => {
    test('should return true for valid E.164 mobile number', () => {
      const result = PhoneValidation.isValidE164('+4915112345678');
      expect(result).toBe(true);
    });

    test('should return true for valid E.164 landline', () => {
      const result = PhoneValidation.isValidE164('+493012345678');
      expect(result).toBe(true);
    });

    test('should return false for national format', () => {
      const result = PhoneValidation.isValidE164('015112345678');
      expect(result).toBe(false);
    });

    test('should return false for 00 prefix format', () => {
      const result = PhoneValidation.isValidE164('004915112345678');
      expect(result).toBe(false);
    });

    test('should return false for null input', () => {
      const result = PhoneValidation.isValidE164(null);
      expect(result).toBe(false);
    });

    test('should return false for undefined input', () => {
      const result = PhoneValidation.isValidE164(undefined);
      expect(result).toBe(false);
    });

    test('should return false for empty string', () => {
      const result = PhoneValidation.isValidE164('');
      expect(result).toBe(false);
    });

    test('should return false for non-string input', () => {
      const result = PhoneValidation.isValidE164(1234567890);
      expect(result).toBe(false);
    });

    test('should return false for wrong country code', () => {
      const result = PhoneValidation.isValidE164('+43123456789');
      expect(result).toBe(false);
    });

    test('should return false for number with spaces', () => {
      const result = PhoneValidation.isValidE164('+49 151 12345678');
      expect(result).toBe(true);
    });

    test('should return false for number with dashes', () => {
      const result = PhoneValidation.isValidE164('+49-151-12345678');
      expect(result).toBe(true);
    });

    test('should return false for too short number', () => {
      const result = PhoneValidation.isValidE164('+4915123456');
      expect(result).toBe(false);
    });

    test('should return false for too long number', () => {
      const result = PhoneValidation.isValidE164('+491512345678901');
      expect(result).toBe(false);
    });

    test('should return false for number starting with zero after country code', () => {
      const result = PhoneValidation.isValidE164('+4901512345678');
      expect(result).toBe(false);
    });
  });

  describe('normalizeToE164', () => {
    test('should normalize valid E.164 format', () => {
      const result = PhoneValidation.normalizeToE164('+4915112345678');
      expect(result).toBe('+4915112345678');
    });

    test('should normalize national format to E.164', () => {
      const result = PhoneValidation.normalizeToE164('015112345678');
      expect(result).toBe('+4915112345678');
    });

    test('should normalize 00 prefix format to E.164', () => {
      const result = PhoneValidation.normalizeToE164('004915112345678');
      expect(result).toBe('+4915112345678');
    });

    test('should normalize number with spaces to E.164', () => {
      const result = PhoneValidation.normalizeToE164('+49 151 12345678');
      expect(result).toBe('+4915112345678');
    });

    test('should normalize number with dashes to E.164', () => {
      const result = PhoneValidation.normalizeToE164('0151-123-456-78');
      expect(result).toBe('+4915112345678');
    });

    test('should return null for invalid format', () => {
      const result = PhoneValidation.normalizeToE164('15112345678');
      expect(result).toBeNull();
    });

    test('should return null for null input', () => {
      const result = PhoneValidation.normalizeToE164(null);
      expect(result).toBeNull();
    });

    test('should return null for empty string', () => {
      const result = PhoneValidation.normalizeToE164('');
      expect(result).toBeNull();
    });

    test('should return null for wrong country code', () => {
      const result = PhoneValidation.normalizeToE164('+43123456789');
      expect(result).toBeNull();
    });

    test('should return null for too short number', () => {
      const result = PhoneValidation.normalizeToE164('+49151234567');
      expect(result).toBeNull();
    });

    test('should return null for too long number', () => {
      const result = PhoneValidation.normalizeToE164('+49151234567890');
      expect(result).toBeNull();
    });

    test('should return null for invalid characters', () => {
      const result = PhoneValidation.normalizeToE164('+49abc1234567');
      expect(result).toBeNull();
    });
  });
});
