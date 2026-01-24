const axios = require('axios');

class MessageService {
  constructor(config = {}) {
    this.wahaBaseUrl = config.wahaBaseUrl || 'http://localhost:3000';
    this.twilio = config.twilio || {};
    this.sessionId = config.sessionId || 'default';
    this.rateLimit = config.rateLimit || { max: 5, window: 3600000 };
    this.messageHistory = [];
    this.pgPool = config.pgPool || null;
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

  async checkOptOutStatus(phone) {
    if (!this.pgPool) {
      return { optedOut: false };
    }

    const normalizedPhone = phone.replace(/[^+\d]/g, '');
    
    try {
      const result = await this.pgPool.query(
        'SELECT opted_out FROM leads WHERE phone = $1',
        [normalizedPhone]
      );
      
      if (result.rows.length === 0) {
        return { optedOut: false, leadExists: false };
      }
      
      const optedOut = result.rows[0].opted_out === true;
      
      if (optedOut) {
        console.warn(`Attempt to message opted-out lead: ${normalizedPhone}`);
      }
      
      return { optedOut, leadExists: true };
    } catch (error) {
      console.error('Failed to check opt-out status:', error.message);
      return { optedOut: false, error: error.message };
    }
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
    
    const optOutStatus = await this.checkOptOutStatus(phone);
    if (optOutStatus.optedOut) {
      throw new Error(`Cannot send WhatsApp: lead ${phone} has opted out`);
    }
    
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

    const optOutStatus = await this.checkOptOutStatus(phone);
    if (optOutStatus.optedOut) {
      throw new Error(`Cannot send SMS: lead ${phone} has opted out`);
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
    const optOutStatus = await this.checkOptOutStatus(phone);
    if (optOutStatus.optedOut) {
      throw new Error(`Cannot send message: lead ${phone} has opted out`);
    }

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
