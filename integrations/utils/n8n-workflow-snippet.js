// ============================================
// N8N CODE NODE - Simplified Phone Validation
// ============================================
// Place this in a Code node in your n8n workflow
// This module should be placed in: integrations/utils/phone-validation.js

const PhoneValidation = require('../../../integrations/utils/phone-validation');

// Get phone number from webhook
let phone = webhookData.From || '';

// Validate and normalize
const result = PhoneValidation.validateGermanPhone(phone);

// Output result
return {
  originalPhone: phone,
  phone: result.normalized,
  phoneValid: result.valid,
  phoneType: result.type,
  phoneError: result.error || null,
  // For backward compatibility with existing workflow
  cleanedPhone: result.normalized || ''
};
