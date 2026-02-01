const crypto = require('crypto');

const ENCRYPTION_KEY = process.env.N8N_ENCRYPTION_KEY;

// Try to decrypt n8n format
const encryptedData = 'U2FsdGVkX1/tt4Whc7pf3DyYL/soxbw8WNEuj8QNSKzAZYmXpk3JDUlXPAdpJ40cznGFQorJemid3oNolLN0BLOQv+JncSmQPHiMQ6N4IqH/4PmDxJb/IgH39SmY43Q2NxVnWHrdevnfxKNKvfFuSe6aBjdqxwfliT4Q6eMwQ8jMGBBmtYaZ0zG94oR8T2VCc6Y/QFQqwSTnoUkWToQNNA==';

try {
  // Try OpenSSL format (Salted__)
  const data = Buffer.from(encryptedData, 'base64');
  const salt = data.slice(8, 16);
  const encrypted = data.slice(16);
  
  // Derive key and iv using EVP_BytesToKey
  const keyIv = crypto.pbkdf2Sync(ENCRYPTION_KEY, salt, 10000, 48, 'sha256');
  const key = keyIv.slice(0, 32);
  const iv = keyIv.slice(32, 48);
  
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  let decrypted = decipher.update(encrypted);
  decrypted = Buffer.concat([decrypted, decipher.final()]);
  
  console.log("Decrypted:", decrypted.toString('utf8'));
} catch (e) {
  console.error("Decryption failed:", e.message);
}
