const axios = require('axios');

class MessageService {
  constructor(config = {}) {
    this.wahaBaseUrl = config.wahaBaseUrl || 'http://localhost:3000';
    this.twilio = config.twilio || {};
    this.sessionId = config.sessionId || 'default';
    this.rateLimit = config.rateLimit || { max: 5, window: 3600000 };
    this.messageHistory = [];
  }

  async checkRateLimit() {
    const now = Date.now();
    const windowStart = now - this.rateLimit.window;
    const recentMessages = this.messageHistory.filter(m => m > windowStart);
    
    if (recentMessages.length >= this.rateLimit.max) {
      const oldest = Math.min(...recentMessages);
      const waitTime = Math.ceil((oldest + this.rateLimit.window - now) / 60000);
      throw new Error(`Rate limit exceeded. Wait ${waitTime} minutes.`);
    }
    
    this.messageHistory.push(now);
  }

  async healthCheck() {
    try {
      const response = await axios.get(`${this.wahaBaseUrl}/health`);
      return { status: 'healthy', data: response.data };
    } catch (error) {
      return { status: 'unhealthy', error: error.message };
    }
  }

  async getQRCode() {
    try {
      const response = await axios.get(
        `${this.wahaBaseUrl}/api/sessions/${this.sessionId}/qr`,
        { responseType: 'arraybuffer' }
      );
      return {
        success: true,
        qrData: response.data,
        contentType: response.headers['content-type']
      };
    } catch (error) {
      return { success: false, error: error.message };
    }
  }

  async getSessionStatus() {
    try {
      const response = await axios.get(`${this.wahaBaseUrl}/api/sessions`);
      const session = response.data.find(s => s.id === this.sessionId);
      return session ? { status: session.status } : null;
    } catch (error) {
      return { status: 'error', error: error.message };
    }
  }

  async sendWhatsApp(phone, message, mediaUrl = null) {
    await this.checkRateLimit();
    
    const payload = {
      chatId: phone,
      text: message,
      session: this.sessionId
    };

    if (mediaUrl) {
      payload.media = { url: mediaUrl };
    }

    try {
      const response = await axios.post(
        `${this.wahaBaseUrl}/api/sendText`,
        payload
      );
      return { success: true, messageId: response.data.id, method: 'whatsapp' };
    } catch (error) {
      console.error('WhatsApp send failed:', error.message);
      throw error;
    }
  }

  async sendSMSFallback(phone, message) {
    if (!this.twilio.accountSid || !this.twilio.authToken) {
      throw new Error('Twilio credentials not configured');
    }

    try {
      const response = await axios.post(
        `https://api.twilio.com/2010-04-01/Accounts/${this.twilio.accountSid}/Messages.json`,
        new URLSearchParams({
          To: phone,
          From: this.twilio.phoneNumber,
          Body: message
        }),
        {
          auth: {
            username: this.twilio.accountSid,
            password: this.twilio.authToken
          }
        }
      );
      return { success: true, messageId: response.data.sid, method: 'sms' };
    } catch (error) {
      throw new Error(`SMS fallback failed: ${error.message}`);
    }
  }

  async sendMessage(phone, templateKey, variables = {}, mediaUrl = null) {
    const templates = require('./templates.json');
    const template = templates.de[templateKey];

    if (!template) {
      throw new Error(`Template not found: ${templateKey}`);
    }

    let message = template.template;
    template.variables.forEach(v => {
      message = message.replace(`{${v}}`, variables[v] || '');
    });

    const health = await this.healthCheck();
    
    try {
      if (health.status === 'healthy') {
        const result = await this.sendWhatsApp(phone, message, mediaUrl);
        return result;
      }
      throw new Error('WhatsApp service unhealthy');
    } catch (error) {
      console.warn('WhatsApp failed, attempting SMS fallback:', error.message);
      return await this.sendSMSFallback(phone, message);
    }
  }
}

module.exports = MessageService;
