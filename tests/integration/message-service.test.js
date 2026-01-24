const nock = require('nock');
const MessageService = require('../../integrations/waha/message-service');

describe('MessageService Integration Tests', () => {
  let service;
  const wahaBaseUrl = 'http://localhost:3000';
  const sessionId = 'test-session';
  
  const twilioConfig = {
    accountSid: 'ACtestaccountsid',
    authToken: 'testauthtoken',
    phoneNumber: '+15551234567'
  };

  beforeEach(() => {
    nock.cleanAll();
    service = new MessageService({
      wahaBaseUrl,
      sessionId,
      twilio: twilioConfig,
      rateLimit: { max: 5, window: 3600000 }
    });
  });

  afterEach(() => {
    nock.cleanAll();
  });

  describe('Health Check', () => {
    test('should return healthy status when Waha responds successfully', async () => {
      const scope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok', uptime: 12345 });

      const result = await service.healthCheck();

      expect(result.status).toBe('healthy');
      expect(result.data).toEqual({ status: 'ok', uptime: 12345 });
      scope.done();
    });

    test('should return unhealthy status when Waha fails', async () => {
      const scope = nock(wahaBaseUrl)
        .get('/health')
        .reply(500, { error: 'Internal Server Error' });

      const result = await service.healthCheck();

      expect(result.status).toBe('unhealthy');
      expect(result.error).toContain('Internal Server Error');
      scope.done();
    });

    test('should handle connection errors', async () => {
      const scope = nock(wahaBaseUrl)
        .get('/health')
        .replyWithError('ECONNREFUSED');

      const result = await service.healthCheck();

      expect(result.status).toBe('unhealthy');
      expect(result.error).toContain('ECONNREFUSED');
      scope.done();
    });

    test('should handle timeout errors', async () => {
      const scope = nock(wahaBaseUrl)
        .get('/health')
        .delayConnection(10000)
        .reply(200, { status: 'ok' });

      await expect(service.healthCheck()).rejects.toThrow();
      scope.done();
    });
  });

  describe('QR Code', () => {
    test('should return QR code data successfully', async () => {
      const qrData = Buffer.from('mock-qr-code-data');
      const scope = nock(wahaBaseUrl)
        .get(`/api/sessions/${sessionId}/qr`)
        .reply(200, qrData, { 'content-type': 'image/png' });

      const result = await service.getQRCode();

      expect(result.success).toBe(true);
      expect(result.qrData).toEqual(qrData);
      expect(result.contentType).toBe('image/png');
      scope.done();
    });

    test('should handle QR code endpoint errors', async () => {
      const scope = nock(wahaBaseUrl)
        .get(`/api/sessions/${sessionId}/qr`)
        .reply(404, { error: 'Session not found' });

      const result = await service.getQRCode();

      expect(result.success).toBe(false);
      expect(result.error).toContain('Session not found');
      scope.done();
    });
  });

  describe('Session Status', () => {
    test('should return session status successfully', async () => {
      const sessions = [
        { id: 'other-session', status: 'STOPPED' },
        { id: sessionId, status: 'READY' }
      ];

      const scope = nock(wahaBaseUrl)
        .get('/api/sessions')
        .reply(200, sessions);

      const result = await service.getSessionStatus();

      expect(result.status).toBe('READY');
      scope.done();
    });

    test('should return null when session not found', async () => {
      const sessions = [
        { id: 'other-session', status: 'READY' }
      ];

      const scope = nock(wahaBaseUrl)
        .get('/api/sessions')
        .reply(200, sessions);

      const result = await service.getSessionStatus();

      expect(result).toBeNull();
      scope.done();
    });

    test('should handle session status errors', async () => {
      const scope = nock(wahaBaseUrl)
        .get('/api/sessions')
        .reply(500, { error: 'Server error' });

      const result = await service.getSessionStatus();

      expect(result.status).toBe('error');
      expect(result.error).toContain('Server error');
      scope.done();
    });
  });

  describe('Rate Limiting', () => {
    test('should allow messages within rate limit', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(200, { id: 'msg123' });

      for (let i = 0; i < 5; i++) {
        await expect(service.sendWhatsApp('+1234567890', 'Test message')).resolves.toEqual({
          success: true,
          messageId: 'msg123',
          method: 'whatsapp'
        });
      }
      scope.done();
    });

    test('should reject messages exceeding rate limit', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(200, { id: 'msg123' });

      service.rateLimit = { max: 2, window: 3600000 };

      await service.sendWhatsApp('+1234567890', 'Test 1');
      await service.sendWhatsApp('+1234567890', 'Test 2');

      await expect(service.sendWhatsApp('+1234567890', 'Test 3'))
        .rejects.toThrow('Rate limit exceeded');
      scope.done();
    });

    test('should reset rate limit after window expires', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(200, { id: 'msg123' });

      service.rateLimit = { max: 2, window: 100 };

      await service.sendWhatsApp('+1234567890', 'Test 1');
      await service.sendWhatsApp('+1234567890', 'Test 2');

      await new Promise(resolve => setTimeout(resolve, 150));

      await expect(service.sendWhatsApp('+1234567890', 'Test 3')).resolves.toEqual({
        success: true,
        messageId: 'msg123',
        method: 'whatsapp'
      });
      scope.done();
    });
  });

  describe('Send WhatsApp', () => {
    test('should send text message successfully', async () => {
      const payload = {
        chatId: '+1234567890',
        text: 'Test message',
        session: sessionId
      };

      const scope = nock(wahaBaseUrl)
        .post('/api/sendText', payload)
        .reply(200, { id: 'msg123' });

      const result = await service.sendWhatsApp('+1234567890', 'Test message');

      expect(result.success).toBe(true);
      expect(result.messageId).toBe('msg123');
      expect(result.method).toBe('whatsapp');
      scope.done();
    });

    test('should send message with media', async () => {
      const payload = {
        chatId: '+1234567890',
        text: 'Test message with media',
        session: sessionId,
        media: { url: 'https://example.com/image.jpg' }
      };

      const scope = nock(wahaBaseUrl)
        .post('/api/sendText', payload)
        .reply(200, { id: 'msg456' });

      const result = await service.sendWhatsApp(
        '+1234567890',
        'Test message with media',
        'https://example.com/image.jpg'
      );

      expect(result.success).toBe(true);
      expect(result.messageId).toBe('msg456');
      expect(result.method).toBe('whatsapp');
      scope.done();
    });

    test('should throw error on WhatsApp send failure', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(500, { error: 'Send failed' });

      await expect(service.sendWhatsApp('+1234567890', 'Test message'))
        .rejects.toThrow();
      scope.done();
    });

    test('should handle network errors when sending WhatsApp', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .replyWithError('ETIMEDOUT');

      await expect(service.sendWhatsApp('+1234567890', 'Test message'))
        .rejects.toThrow();
      scope.done();
    });
  });

  describe('Send SMS Fallback', () => {
    test('should send SMS successfully with Twilio credentials', async () => {
      const scope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .basicAuth({ user: twilioConfig.accountSid, pass: twilioConfig.authToken })
        .reply(200, { sid: 'SM123' });

      const result = await service.sendSMSFallback('+1234567890', 'Fallback message');

      expect(result.success).toBe(true);
      expect(result.messageId).toBe('SM123');
      expect(result.method).toBe('sms');
      scope.done();
    });

    test('should throw error when Twilio credentials missing', async () => {
      const serviceNoCreds = new MessageService({
        wahaBaseUrl,
        sessionId,
        twilio: {}
      });

      await expect(serviceNoCreds.sendSMSFallback('+1234567890', 'Test'))
        .rejects.toThrow('Twilio credentials not configured');
    });

    test('should handle SMS send failures', async () => {
      const scope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .reply(400, { error: 'Invalid number' });

      await expect(service.sendSMSFallback('+1234567890', 'Test'))
        .rejects.toThrow('SMS fallback failed');
      scope.done();
    });

    test('should handle SMS network errors', async () => {
      const scope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .replyWithError('ENOTFOUND');

      await expect(service.sendSMSFallback('+1234567890', 'Test'))
        .rejects.toThrow('SMS fallback failed');
      scope.done();
    });

    test('should use configured phone number for From', async () => {
      const scope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`, body => {
          return body.toString().includes(`From=${encodeURIComponent(twilioConfig.phoneNumber)}`);
        })
        .reply(200, { sid: 'SM456' });

      await service.sendSMSFallback('+1234567890', 'Test');
      scope.done();
    });
  });

  describe('Send Message with Fallback', () => {
    beforeEach(() => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });
    });

    test('should send WhatsApp message successfully when healthy', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(200, { id: 'msg789' });

      const result = await service.sendMessage(
        '+1234567890',
        'lead_acknowledgment',
        {}
      );

      expect(result.success).toBe(true);
      expect(result.method).toBe('whatsapp');
      healthScope.done();
      sendScope.done();
    });

    test('should fallback to SMS when WhatsApp unhealthy', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(503, { error: 'Service unavailable' });

      const smsScope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .reply(200, { sid: 'SM789' });

      const result = await service.sendMessage(
        '+1234567890',
        'lead_acknowledgment',
        {}
      );

      expect(result.success).toBe(true);
      expect(result.method).toBe('sms');
      healthScope.done();
      smsScope.done();
    });

    test('should fallback to SMS when WhatsApp send fails', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(500, { error: 'Send failed' });

      const smsScope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .reply(200, { sid: 'SM999' });

      const result = await service.sendMessage(
        '+1234567890',
        'lead_acknowledgment',
        {}
      );

      expect(result.success).toBe(true);
      expect(result.method).toBe('sms');
      healthScope.done();
      sendScope.done();
      smsScope.done();
    });

    test('should replace template variables correctly', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => {
          return body.text === 'Ihr Termin am 2024-01-24 um 14:00 wurde bestätigt. Wir freuen uns auf Sie! Adresse: 123 Main St';
        })
        .reply(200, { id: 'msg001' });

      const result = await service.sendMessage(
        '+1234567890',
        'appointment_confirmation',
        { date: '2024-01-24', time: '14:00', address: '123 Main St' }
      );

      expect(result.success).toBe(true);
      healthScope.done();
      sendScope.done();
    });

    test('should handle missing template gracefully', async () => {
      await expect(service.sendMessage('+1234567890', 'nonexistent_template', {}))
        .rejects.toThrow('Template not found');
    });

    test('should handle missing variables in template', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => {
          return body.text.includes('Ihr Angebot liegt bereit. Sie können es hier einsehen: . Haben Sie Fragen?');
        })
        .reply(200, { id: 'msg002' });

      const result = await service.sendMessage(
        '+1234567890',
        'quote_sent',
        {}
      );

      expect(result.success).toBe(true);
      healthScope.done();
      sendScope.done();
    });

    test('should include media URL in WhatsApp message', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => {
          return body.media && body.media.url === 'https://example.com/media.pdf';
        })
        .reply(200, { id: 'msg003' });

      const result = await service.sendMessage(
        '+1234567890',
        'lead_acknowledgment',
        {},
        'https://example.com/media.pdf'
      );

      expect(result.success).toBe(true);
      expect(result.method).toBe('whatsapp');
      healthScope.done();
      sendScope.done();
    });
  });

  describe('Timeout Tests', () => {
    test('should timeout on slow health check', async () => {
      const scope = nock(wahaBaseUrl)
        .get('/health')
        .delayConnection(11000)
        .reply(200, { status: 'ok' });

      await expect(service.healthCheck()).rejects.toThrow();
      scope.done();
    });

    test('should timeout on slow WhatsApp send', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .delayConnection(11000)
        .reply(200, { id: 'msg_timeout' });

      await expect(service.sendWhatsApp('+1234567890', 'Test'))
        .rejects.toThrow();
      scope.done();
    });

    test('should fallback to SMS on WhatsApp timeout', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .delayConnection(11000)
        .reply(200, { id: 'msg_timeout' });

      const smsScope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .reply(200, { sid: 'SM_timeout' });

      const result = await service.sendMessage(
        '+1234567890',
        'lead_acknowledgment',
        {}
      );

      expect(result.success).toBe(true);
      expect(result.method).toBe('sms');
      healthScope.done();
      sendScope.done();
      smsScope.done();
    });
  });

  describe('API Failure Scenarios', () => {
    test('should handle 401 unauthorized from Waha', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(401, { error: 'Unauthorized' });

      await expect(service.sendWhatsApp('+1234567890', 'Test'))
        .rejects.toThrow();
      scope.done();
    });

    test('should handle 403 forbidden from Waha', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(403, { error: 'Forbidden' });

      await expect(service.sendWhatsApp('+1234567890', 'Test'))
        .rejects.toThrow();
      scope.done();
    });

    test('should handle 429 too many requests from Waha', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(429, { error: 'Too many requests' });

      await expect(service.sendWhatsApp('+1234567890', 'Test'))
        .rejects.toThrow();
      scope.done();
    });

    test('should handle 401 unauthorized from Twilio', async () => {
      const scope = nock('https://api.twilio.com')
        .post(`/2010-04-01/Accounts/${twilioConfig.accountSid}/Messages.json`)
        .reply(401, { error: 'Unauthorized' });

      await expect(service.sendSMSFallback('+1234567890', 'Test'))
        .rejects.toThrow('SMS fallback failed');
      scope.done();
    });

    test('should handle malformed JSON response', async () => {
      const scope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .reply(200, 'invalid json', { 'content-type': 'application/json' });

      await expect(service.sendWhatsApp('+1234567890', 'Test'))
        .rejects.toThrow();
      scope.done();
    });
  });

  describe('Edge Cases', () => {
    test('should handle empty message text', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => body.text === '')
        .reply(200, { id: 'msg_empty' });

      const result = await service.sendMessage('+1234567890', 'lead_acknowledgment', {});

      expect(result.success).toBe(true);
      healthScope.done();
      sendScope.done();
    });

    test('should handle special characters in message', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => {
          return body.text.includes('äöüß') && body.text.includes('©®™');
        })
        .reply(200, { id: 'msg_special' });

      await service.sendWhatsApp('+1234567890', 'Test äöüß ©®™');
      healthScope.done();
      sendScope.done();
    });

    test('should handle very long messages', async () => {
      const longMessage = 'x'.repeat(2000);

      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => body.text.length === 2000)
        .reply(200, { id: 'msg_long' });

      await service.sendWhatsApp('+1234567890', longMessage);
      healthScope.done();
      sendScope.done();
    });

    test('should handle concurrent requests', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .times(5)
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .times(5)
        .reply(200, { id: 'msg_concurrent' });

      const promises = Array(5).fill(null).map((_, i) =>
        service.sendMessage('+1234567890', 'lead_acknowledgment', {})
      );

      const results = await Promise.all(promises);

      results.forEach(result => {
        expect(result.success).toBe(true);
        expect(result.method).toBe('whatsapp');
      });

      healthScope.done();
      sendScope.done();
    });
  });

  describe('Multiple Template Variables', () => {
    test('should handle template with multiple variables', async () => {
      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText', body => {
          const expected = 'Gute Neuigkeiten! Die Materialien für Ihr Projekt wurden bestellt. Voraussichtliche Lieferung: 2024-02-15.';
          return body.text === expected;
        })
        .reply(200, { id: 'msg_multi' });

      const result = await service.sendMessage(
        '+1234567890',
        'material_ordered',
        { delivery_date: '2024-02-15' }
      );

      expect(result.success).toBe(true);
      healthScope.done();
      sendScope.done();
    });

    test('should handle all available templates', async () => {
      const templates = [
        'lead_acknowledgment',
        'appointment_confirmation',
        'quote_sent',
        'material_ordered',
        'installation_scheduled',
        'fallback_sms'
      ];

      const healthScope = nock(wahaBaseUrl)
        .get('/health')
        .times(templates.length)
        .reply(200, { status: 'ok' });

      const sendScope = nock(wahaBaseUrl)
        .post('/api/sendText')
        .times(templates.length)
        .reply(200, { id: 'msg_template' });

      for (const template of templates) {
        const result = await service.sendMessage('+1234567890', template, {});
        expect(result.success).toBe(true);
      }

      healthScope.done();
      sendScope.done();
    });
  });
});
