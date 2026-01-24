const mockMessages = [];
const mockStatus = { status: 'READY' };
const mockWebhooks = [];

class WahaMock {
  constructor(config = {}) {
    this.sessionId = config.sessionId || 'default';
    this.messageHistory = [];
  }

  async healthCheck() {
    return { status: 'healthy', data: { status: 'ok' } };
  }

  async getQRCode() {
    return {
      success: true,
      qrData: Buffer.from('mock-qr-code'),
      contentType: 'image/png'
    };
  }

  async getSessionStatus() {
    return { status: mockStatus.status };
  }

  async sendWhatsApp(phone, message, mediaUrl = null) {
    const messageId = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    const sentMessage = {
      id: messageId,
      chatId: phone,
      text: message,
      session: this.sessionId,
      media: mediaUrl ? { url: mediaUrl } : null,
      timestamp: new Date().toISOString()
    };
    
    mockMessages.push(sentMessage);
    this.messageHistory.push(Date.now());
    
    return { success: true, messageId, method: 'whatsapp' };
  }

  async sendSMSFallback(phone, message) {
    const messageId = `sms_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    return { success: true, messageId, method: 'sms' };
  }

  async sendMessage(phone, templateKey, variables = {}, mediaUrl = null) {
    const templates = {
      de: {
        welcome: { template: 'Willkommen {name}!', variables: ['name'] },
        appointment: { template: 'Termin am {date} um {time}', variables: ['date', 'time'] }
      }
    };

    const template = templates.de[templateKey] || { template: templateKey, variables: [] };
    let message = template.template;
    
    template.variables.forEach(v => {
      message = message.replace(`{${v}}`, variables[v] || '');
    });

    return this.sendWhatsApp(phone, message, mediaUrl);
  }

  reset() {
    mockMessages.length = 0;
    mockWebhooks.length = 0;
    this.messageHistory.length = 0;
  }
}

const mockWahaSend = (phone, message, mediaUrl = null) => {
  const messageId = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  
  const sentMessage = {
    id: messageId,
    chatId: phone,
    text: message,
    media: mediaUrl ? { url: mediaUrl } : null,
    timestamp: new Date().toISOString()
  };
  
  mockMessages.push(sentMessage);
  
  return Promise.resolve({ success: true, messageId, method: 'whatsapp' });
};

const mockWahaStatus = (status = 'READY') => {
  mockStatus.status = status;
  return Promise.resolve({ status });
};

const mockWahaWebhook = (event, data) => {
  const webhook = {
    event,
    data,
    timestamp: new Date().toISOString(),
    id: `webhook_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  };
  
  mockWebhooks.push(webhook);
  
  return Promise.resolve({ success: true, webhookId: webhook.id });
};

const getMockMessages = () => [...mockMessages];
const getMockWebhooks = () => [...mockWebhooks];
const resetMocks = () => {
  mockMessages.length = 0;
  mockWebhooks.length = 0;
  mockStatus.status = 'READY';
};

module.exports = {
  WahaMock,
  mockWahaSend,
  mockWahaStatus,
  mockWahaWebhook,
  getMockMessages,
  getMockWebhooks,
  resetMocks
};
