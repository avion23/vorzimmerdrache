const mockMessages = [];
const mockStatus = { status: 'queued' };
const mockWebhooks = [];

class TwilioMock {
  constructor(config = {}) {
    this.accountSid = config.accountSid || 'ACmockaccountsid';
    this.authToken = config.authToken || 'mockauthtoken';
    this.phoneNumber = config.phoneNumber || '+15551234567';
    this.messageHistory = [];
  }

  async healthCheck() {
    return { status: 'healthy', data: { status: 'ok' } };
  }

  async getPhoneNumber() {
    return { phoneNumber: this.phoneNumber, status: 'active' };
  }

  async sendSMS(to, from, body, mediaUrls = []) {
    const messageSid = `SM${Date.now()}${Math.random().toString(36).substr(2, 9)}`;
    
    const sentMessage = {
      sid: messageSid,
      to,
      from: from || this.phoneNumber,
      body,
      status: 'queued',
      direction: 'outbound-api',
      mediaUrls,
      accountSid: this.accountSid,
      timestamp: new Date().toISOString()
    };
    
    mockMessages.push(sentMessage);
    this.messageHistory.push(Date.now());
    
    return { success: true, sid: messageSid, status: 'queued' };
  }

  async sendWhatsApp(to, from, body, mediaUrls = []) {
    const messageSid = `WA${Date.now()}${Math.random().toString(36).substr(2, 9)}`;
    
    const sentMessage = {
      sid: messageSid,
      to,
      from: from || this.phoneNumber,
      body,
      status: 'queued',
      direction: 'outbound-api',
      mediaUrls,
      accountSid: this.accountSid,
      timestamp: new Date().toISOString()
    };
    
    mockMessages.push(sentMessage);
    
    return { success: true, sid: messageSid, status: 'queued', method: 'whatsapp' };
  }

  async createMessage(to, from, body, options = {}) {
    const messageSid = `MG${Date.now()}${Math.random().toString(36).substr(2, 9)}`;
    const method = to.startsWith('whatsapp') ? 'whatsapp' : 'sms';
    
    const sentMessage = {
      sid: messageSid,
      to,
      from: from || this.phoneNumber,
      body,
      status: 'queued',
      direction: 'outbound-api',
      mediaUrls: options.mediaUrls || [],
      statusCallback: options.statusCallback || null,
      accountSid: this.accountSid,
      timestamp: new Date().toISOString()
    };
    
    mockMessages.push(sentMessage);
    this.messageHistory.push(Date.now());
    
    return { success: true, sid: messageSid, status: 'queued', method };
  }

  async getMessageStatus(messageSid) {
    const message = mockMessages.find(m => m.sid === messageSid);
    if (!message) {
      throw new Error(`Message ${messageSid} not found`);
    }
    
    return {
      sid: messageSid,
      status: mockStatus.status,
      to: message.to,
      from: message.from,
      timestamp: message.timestamp
    };
  }

  reset() {
    mockMessages.length = 0;
    mockWebhooks.length = 0;
    this.messageHistory.length = 0;
    mockStatus.status = 'queued';
  }
}

const mockTwilioSMS = (to, from, body, mediaUrls = []) => {
  const messageSid = `SM${Date.now()}${Math.random().toString(36).substr(2, 9)}`;
  
  const sentMessage = {
    sid: messageSid,
    to,
    from: from || '+15551234567',
    body,
    status: 'queued',
    direction: 'outbound-api',
    mediaUrls,
    timestamp: new Date().toISOString()
  };
  
  mockMessages.push(sentMessage);
  
  return Promise.resolve({ success: true, sid: messageSid, status: 'queued' });
};

const mockTwilioWebhook = (eventType, payload = {}) => {
  const webhook = {
    eventType,
    payload,
    timestamp: new Date().toISOString(),
    id: `webhook_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  };
  
  mockWebhooks.push(webhook);
  
  return Promise.resolve({ success: true, webhookId: webhook.id });
};

const mockTwilioStatus = (status = 'delivered', messageSid = null) => {
  mockStatus.status = status;
  
  if (messageSid) {
    const message = mockMessages.find(m => m.sid === messageSid);
    if (message) {
      message.status = status;
    }
  }
  
  return Promise.resolve({ 
    status, 
    messageSid, 
    timestamp: new Date().toISOString() 
  });
};

const getMockMessages = () => [...mockMessages];
const getMockWebhooks = () => [...mockWebhooks];
const resetMocks = () => {
  mockMessages.length = 0;
  mockWebhooks.length = 0;
  mockStatus.status = 'queued';
};

module.exports = {
  TwilioMock,
  mockTwilioSMS,
  mockTwilioWebhook,
  mockTwilioStatus,
  getMockMessages,
  getMockWebhooks,
  resetMocks
};
