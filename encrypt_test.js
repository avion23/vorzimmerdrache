const crypto = require('crypto');

const ENCRYPTION_KEY = process.env.N8N_ENCRYPTION_KEY;

function encrypt(data) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', Buffer.from(ENCRYPTION_KEY, 'hex'), iv);
  let encrypted = cipher.update(data, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return iv.toString('base64') + ':' + encrypted;
}

function decrypt(data) {
  const parts = data.split(':');
  const iv = Buffer.from(parts.shift(), 'base64');
  const encrypted = parts.join(':');
  const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(ENCRYPTION_KEY, 'hex'), iv);
  let decrypted = decipher.update(encrypted, 'base64', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}

// Test with sample data
const testData = JSON.stringify({accountSid: "test123", authToken: "test456"});
console.log("Original:", testData);

const encrypted = encrypt(testData);
console.log("Encrypted:", encrypted);

const decrypted = decrypt(encrypted);
console.log("Decrypted:", decrypted);
