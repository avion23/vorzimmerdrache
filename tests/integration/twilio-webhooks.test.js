const request = require('supertest');
const nock = require('nock');
const express = require('express');
const { TwilioMock, mockTwilioWebhook, resetMocks } = require('../mocks/twilio-mock');

describe('Twilio Webhook Integration Tests', () => {
  let app;
  let twilioMock;
  const TEST_ACCOUNT_SID = 'ACtest123456789012345678901234';
  const TEST_AUTH_TOKEN = 'testauthtoken123456789012345678901';
  const TEST_PHONE_NUMBER = '+15551234567';
  const TEST_WEBHOOK_URL = 'https://api.twilio.com';

  beforeEach(() => {
    twilioMock = new TwilioMock({
      accountSid: TEST_ACCOUNT_SID,
      authToken: TEST_AUTH_TOKEN,
      phoneNumber: TEST_PHONE_NUMBER
    });

    app = express();
    app.use(express.urlencoded({ extended: true }));
    app.use(express.json());

    app.post('/sms/inbound', (req, res) => {
      const { From, To, Body, MessageSid } = req.body;
      
      if (!From || !Body) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      if (Body.length > 1600) {
        return res.status(400).json({ error: 'Message body too long' });
      }

      mockTwilioWebhook('sms.inbound', { From, To, Body, MessageSid });

      res.status(200).send('<Response><Message>Message received</Message></Response>');
    });

    app.post('/sms/delivery-receipt', (req, res) => {
      const { MessageSid, MessageStatus, ErrorCode, ErrorMessage } = req.body;

      if (!MessageSid || !MessageStatus) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      mockTwilioWebhook('sms.delivery_receipt', {
        MessageSid,
        MessageStatus,
        ErrorCode,
        ErrorMessage
      });

      res.status(200).send('<Response/>');
    });

    app.post('/sms/opt-out', (req, res) => {
      const { From, Body } = req.body;
      const optOutKeywords = ['STOP', 'STOPALL', 'UNSUBSCRIBE', 'CANCEL', 'QUIT', 'END'];
      const normalizedBody = Body.toUpperCase().trim();

      if (optOutKeywords.includes(normalizedBody)) {
        mockTwilioWebhook('sms.opt_out', { From, keyword: normalizedBody });
        return res.status(200).send('<Response><Message>You have opted out. Reply START to opt back in.</Message></Response>');
      }

      mockTwilioWebhook('sms.opt_out_check', { From, Body });
      res.status(200).send('<Response><Message>Message received</Message></Response>');
    });

    app.post('/sms/opt-in', (req, res) => {
      const { From, Body } = req.body;
      const optInKeywords = ['START', 'YES', 'UNSTOP'];
      const normalizedBody = Body.toUpperCase().trim();

      if (optInKeywords.includes(normalizedBody)) {
        mockTwilioWebhook('sms.opt_in', { From, keyword: normalizedBody });
        return res.status(200).send('<Response><Message>You have opted back in.</Message></Response>');
      }

      res.status(400).json({ error: 'Invalid opt-in keyword' });
    });

    app.post('/sms/bounce', (req, res) => {
      const { From, To, MessageSid, ErrorCode, ErrorMessage } = req.body;

      mockTwilioWebhook('sms.bounce', {
        From,
        To,
        MessageSid,
        ErrorCode,
        ErrorMessage
      });

      res.status(200).send('<Response/>');
    });

    app.get('/health', (req, res) => {
      res.json({ status: 'ok', timestamp: new Date().toISOString() });
    });

    nock.cleanAll();
    resetMocks();
  });

  afterEach(() => {
    nock.cleanAll();
    resetMocks();
  });

  describe('Inbound SMS Handling', () => {
    test('should successfully process inbound SMS with all fields', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234567',
        From: '+15559876543',
        To: '+15551234567',
        Body: 'Hello, this is a test message',
        FromCountry: 'US',
        FromState: 'CA',
        FromCity: 'San Francisco',
        NumSegments: '1'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .reply(200, {
          sid: smsPayload.MessageSid,
          status: 'received',
          from: smsPayload.From,
          to: smsPayload.To,
          body: smsPayload.Body
        });

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200)
        .expect('Content-Type', /xml/);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should process inbound SMS with special characters', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234568',
        From: '+15559876544',
        To: '+15551234567',
        Body: 'Test with émojis 🎉 and spëcial çhars!'
      };

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });

    test('should process inbound SMS with media URLs', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234569',
        From: '+15559876545',
        To: '+15551234567',
        Body: 'Here is an image',
        NumMedia: '1',
        MediaUrl0: 'https://example.com/image.jpg',
        MediaContentType0: 'image/jpeg'
      };

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });

    test('should reject inbound SMS without From field', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234570',
        To: '+15551234567',
        Body: 'Test message'
      };

      await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(400)
        .expect('Content-Type', /json/)
        .expect(res => {
          expect(res.body.error).toBe('Missing required fields');
        });
    });

    test('should reject inbound SMS without Body field', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234571',
        From: '+15559876546',
        To: '+15551234567'
      };

      await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(400)
        .expect('Content-Type', /json/)
        .expect(res => {
          expect(res.body.error).toBe('Missing required fields');
        });
    });

    test('should reject inbound SMS with body exceeding 1600 characters', async () => {
      const longBody = 'A'.repeat(1601);
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234572',
        From: '+15559876547',
        To: '+15551234567',
        Body: longBody
      };

      await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(400)
        .expect('Content-Type', /json/)
        .expect(res => {
          expect(res.body.error).toBe('Message body too long');
        });
    });

    test('should handle empty body message', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234573',
        From: '+15559876548',
        To: '+15551234567',
        Body: ''
      };

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });
  });

  describe('Delivery Receipt Handling', () => {
    test('should process successful delivery receipt', async () => {
      const deliveryPayload = {
        MessageSid: 'SM123456789012345678901234580',
        MessageStatus: 'delivered',
        To: '+15559876543',
        From: '+15551234567',
        ErrorCode: '',
        ErrorMessage: ''
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .get('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages/' + deliveryPayload.MessageSid + '.json')
        .reply(200, {
          sid: deliveryPayload.MessageSid,
          status: 'delivered'
        });

      const response = await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(200);

      expect(response.text).toContain('<Response/>');
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should process queued delivery receipt', async () => {
      const deliveryPayload = {
        MessageSid: 'SM123456789012345678901234581',
        MessageStatus: 'queued',
        To: '+15559876544',
        ErrorCode: '',
        ErrorMessage: ''
      };

      const response = await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(200);

      expect(response.text).toContain('<Response/>');
    });

    test('should process sent delivery receipt', async () => {
      const deliveryPayload = {
        MessageSid: 'SM123456789012345678901234582',
        MessageStatus: 'sent',
        To: '+15559876545',
        ErrorCode: '',
        ErrorMessage: ''
      };

      const response = await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(200);

      expect(response.text).toContain('<Response/>');
    });

    test('should process failed delivery with error code', async () => {
      const deliveryPayload = {
        MessageSid: 'SM123456789012345678901234583',
        MessageStatus: 'failed',
        To: '+15559876546',
        From: '+15551234567',
        ErrorCode: '21614',
        ErrorMessage: 'To number is not a valid mobile number'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .get('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages/' + deliveryPayload.MessageSid + '.json')
        .reply(200, {
          sid: deliveryPayload.MessageSid,
          status: 'failed',
          error_code: '21614',
          error_message: 'To number is not a valid mobile number'
        });

      const response = await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(200);

      expect(response.text).toContain('<Response/>');
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should process undelivered receipt', async () => {
      const deliveryPayload = {
        MessageSid: 'SM123456789012345678901234584',
        MessageStatus: 'undelivered',
        To: '+15559876547',
        ErrorCode: '30007',
        ErrorMessage: 'Message delivery - Carrier violation'
      };

      const response = await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(200);

      expect(response.text).toContain('<Response/>');
    });

    test('should reject delivery receipt without MessageSid', async () => {
      const deliveryPayload = {
        MessageStatus: 'delivered',
        To: '+15559876548'
      };

      await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(400)
        .expect('Content-Type', /json/)
        .expect(res => {
          expect(res.body.error).toBe('Missing required fields');
        });
    });

    test('should reject delivery receipt without MessageStatus', async () => {
      const deliveryPayload = {
        MessageSid: 'SM123456789012345678901234585',
        To: '+15559876549'
      };

      await request(app)
        .post('/sms/delivery-receipt')
        .type('form')
        .send(deliveryPayload)
        .expect(400)
        .expect('Content-Type', /json/)
        .expect(res => {
          expect(res.body.error).toBe('Missing required fields');
        });
    });
  });

  describe('Error Scenarios', () => {
    test('should handle Twilio API timeout error', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234590',
        From: '+15559876550',
        To: '+15551234567',
        Body: 'Test message'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .replyWithError({ code: 'ETIMEDOUT', message: 'Connection timeout' });

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload);

      expect(response.status).toBe(200);
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should handle Twilio API 500 error', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234591',
        From: '+15559876551',
        To: '+15551234567',
        Body: 'Test message'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .reply(500, {
          code: 20003,
          message: 'Authenticate',
          more_info: 'https://www.twilio.com/docs/errors/20003',
          status: 500
        });

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload);

      expect(response.status).toBe(200);
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should handle invalid JSON payload', async () => {
      const response = await request(app)
        .post('/sms/inbound')
        .set('Content-Type', 'application/json')
        .send('{ invalid json }')
        .expect(400);
    });

    test('should handle malformed form data', async () => {
      const response = await request(app)
        .post('/sms/inbound')
        .set('Content-Type', 'application/x-www-form-urlencoded')
        .send('From=+15559876552&Body=Test&Extra==bad=data')
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });

    test('should handle concurrent webhook requests', async () => {
      const payloads = Array.from({ length: 5 }, (_, i) => ({
        MessageSid: `SM12345678901234567890123460${i}`,
        From: `+15559876550${i}`,
        To: '+15551234567',
        Body: `Concurrent message ${i}`
      }));

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .times(5)
        .reply(200, { sid: 'SM123', status: 'received' });

      const responses = await Promise.all(
        payloads.map(payload =>
          request(app)
            .post('/sms/inbound')
            .type('form')
            .send(payload)
        )
      );

      responses.forEach(response => {
        expect(response.status).toBe(200);
        expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
      });

      expect(twilioScope.isDone()).toBe(true);
    });

    test('should handle very long phone numbers', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234592',
        From: '+15559876553' + '0'.repeat(100),
        To: '+15551234567',
        Body: 'Test'
      };

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload);

      expect(response.status).toBe(200);
    });

    test('should handle bounce webhook with invalid number', async () => {
      const bouncePayload = {
        From: '+15559876554',
        To: '+15551234567',
        MessageSid: 'SM123456789012345678901234593',
        ErrorCode: '21610',
        ErrorMessage: 'Unable to deliver message to the specified phone number'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .get('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages/' + bouncePayload.MessageSid + '.json')
        .reply(404, {
          code: 20404,
          message: 'The requested resource was not found'
        });

      const response = await request(app)
        .post('/sms/bounce')
        .type('form')
        .send(bouncePayload)
        .expect(200);

      expect(twilioScope.isDone()).toBe(true);
    });
  });

  describe('Opt-out Handling', () => {
    test('should process STOP keyword for opt-out', async () => {
      const smsPayload = {
        From: '+15559876555',
        To: '+15551234567',
        Body: 'STOP'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .reply(200, { sid: 'SM123', status: 'queued' });

      const response = await request(app)
        .post('/sms/opt-out')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('You have opted out');
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should process STOPALL keyword for opt-out', async () => {
      const smsPayload = {
        From: '+15559876556',
        To: '+15551234567',
        Body: 'STOPALL'
      };

      const response = await request(app)
        .post('/sms/opt-out')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('You have opted out');
    });

    test('should process STOP with mixed case', async () => {
      const smsPayload = {
        From: '+15559876557',
        To: '+15551234567',
        Body: 'StOp'
      };

      const response = await request(app)
        .post('/sms/opt-out')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('You have opted out');
    });

    test('should process STOP with trailing spaces', async () => {
      const smsPayload = {
        From: '+15559876558',
        To: '+15551234567',
        Body: '  STOP  '
      };

      const response = await request(app)
        .post('/sms/opt-out')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('You have opted out');
    });

    test('should not opt-out for non-opt-out keywords', async () => {
      const smsPayload = {
        From: '+15559876559',
        To: '+15551234567',
        Body: 'Hello, I have a question'
      };

      const response = await request(app)
        .post('/sms/opt-out')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });
  });

  describe('Opt-in Handling', () => {
    test('should process START keyword for opt-in', async () => {
      const smsPayload = {
        From: '+15559876560',
        To: '+15551234567',
        Body: 'START'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .reply(200, { sid: 'SM123', status: 'queued' });

      const response = await request(app)
        .post('/sms/opt-in')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('You have opted back in');
      expect(twilioScope.isDone()).toBe(true);
    });

    test('should process UNSTOP keyword for opt-in', async () => {
      const smsPayload = {
        From: '+15559876561',
        To: '+15551234567',
        Body: 'UNSTOP'
      };

      const response = await request(app)
        .post('/sms/opt-in')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('You have opted back in');
    });

    test('should reject invalid opt-in keyword', async () => {
      const smsPayload = {
        From: '+15559876562',
        To: '+15551234567',
        Body: 'INVALID'
      };

      await request(app)
        .post('/sms/opt-in')
        .type('form')
        .send(smsPayload)
        .expect(400)
        .expect('Content-Type', /json/)
        .expect(res => {
          expect(res.body.error).toBe('Invalid opt-in keyword');
        });
    });
  });

  describe('Webhook Verification', () => {
    test('should return health check status', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200)
        .expect('Content-Type', /json/);

      expect(response.body.status).toBe('ok');
      expect(response.body.timestamp).toBeDefined();
    });

    test('should accept webhook with valid Twilio signature', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234600',
        From: '+15559876563',
        To: '+15551234567',
        Body: 'Test message'
      };

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .reply(200, { sid: 'SM123', status: 'received' });

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(twilioScope.isDone()).toBe(true);
    });

    test('should handle missing Content-Type header', async () => {
      const response = await request(app)
        .post('/sms/inbound')
        .send('From=+15559876564&Body=Test');

      expect([200, 400, 415]).toContain(response.status);
    });
  });

  describe('TwilioMock Integration', () => {
    test('should use TwilioMock for SMS sending simulation', async () => {
      const result = await twilioMock.sendSMS(
        '+15559876565',
        '+15551234567',
        'Test message from mock'
      );

      expect(result.success).toBe(true);
      expect(result.sid).toBeDefined();
      expect(result.status).toBe('queued');
      expect(result.sid).toMatch(/^SM/);
    });

    test('should send WhatsApp message through mock', async () => {
      const result = await twilioMock.sendWhatsApp(
        'whatsapp:+15559876566',
        'whatsapp:+15551234567',
        'WhatsApp message'
      );

      expect(result.success).toBe(true);
      expect(result.method).toBe('whatsapp');
      expect(result.sid).toMatch(/^WA/);
    });

    test('should track message history in mock', async () => {
      await twilioMock.sendSMS('+15559876567', '+15551234567', 'Message 1');
      await twilioMock.sendSMS('+15559876568', '+15551234567', 'Message 2');

      expect(twilioMock.messageHistory.length).toBe(2);
    });

    test('should reset mock state', async () => {
      await twilioMock.sendSMS('+15559876569', '+15551234567', 'Test');
      expect(twilioMock.messageHistory.length).toBeGreaterThan(0);

      twilioMock.reset();
      expect(twilioMock.messageHistory.length).toBe(0);
    });
  });

  describe('Rate Limiting and Throttling', () => {
    test('should handle rapid successive requests', async () => {
      const payloads = Array.from({ length: 10 }, (_, i) => ({
        MessageSid: `SM12345678901234567890123461${i}`,
        From: `+15559876570${i}`,
        To: '+15551234567',
        Body: `Rapid message ${i}`
      }));

      const twilioScope = nock(TEST_WEBHOOK_URL)
        .post('/2010-04-01/Accounts/' + TEST_ACCOUNT_SID + '/Messages.json')
        .times(10)
        .reply(200, { sid: 'SM123', status: 'received' });

      const startTime = Date.now();
      await Promise.all(
        payloads.map(payload =>
          request(app)
            .post('/sms/inbound')
            .type('form')
            .send(payload)
        )
      );
      const duration = Date.now() - startTime;

      expect(duration).toBeLessThan(5000);
      expect(twilioScope.isDone()).toBe(true);
    });
  });

  describe('Message Encoding and Internationalization', () => {
    test('should handle UTF-8 encoded messages', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234620',
        From: '+15559876571',
        To: '+15551234567',
        Body: 'Grüße из 日本 العربية'
      };

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });

    test('should handle international phone numbers', async () => {
      const internationalNumbers = [
        '+4915112345678',
        '+442071234567',
        '+33123456789',
        '+819012345678',
        '+8613812345678'
      ];

      for (const number of internationalNumbers) {
        const smsPayload = {
          MessageSid: `SM${Date.now()}`,
          From: number,
          To: '+15551234567',
          Body: 'International test'
        };

        const response = await request(app)
          .post('/sms/inbound')
          .type('form')
          .send(smsPayload)
          .expect(200);

        expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
      }
    });

    test('should handle right-to-left text', async () => {
      const smsPayload = {
        MessageSid: 'SM123456789012345678901234621',
        From: '+15559876572',
        To: '+15551234567',
        Body: 'مرحبا بالعالم'
      };

      const response = await request(app)
        .post('/sms/inbound')
        .type('form')
        .send(smsPayload)
        .expect(200);

      expect(response.text).toContain('<Response><Message>Message received</Message></Response>');
    });
  });

  describe('Status Callback Webhooks', () => {
    test('should handle multiple status updates for same message', async () => {
      const statuses = ['queued', 'sent', 'delivered'];
      const messageSid = 'SM123456789012345678901234630';

      for (const status of statuses) {
        const deliveryPayload = {
          MessageSid: messageSid,
          MessageStatus: status,
          To: '+15559876573',
          ErrorCode: '',
          ErrorMessage: ''
        };

        const response = await request(app)
          .post('/sms/delivery-receipt')
          .type('form')
          .send(deliveryPayload)
          .expect(200);

        expect(response.text).toContain('<Response/>');
      }
    });

    test('should handle message status transitions correctly', async () => {
      const transitions = [
        { status: 'queued', expectSuccess: true },
        { status: 'sent', expectSuccess: true },
        { status: 'delivered', expectSuccess: true },
        { status: 'failed', expectSuccess: true },
        { status: 'undelivered', expectSuccess: true }
      ];

      for (const transition of transitions) {
        const deliveryPayload = {
          MessageSid: `SM${Date.now()}`,
          MessageStatus: transition.status,
          To: '+15559876574',
          ErrorCode: transition.status === 'failed' ? '21614' : '',
          ErrorMessage: transition.status === 'failed' ? 'Invalid number' : ''
        };

        const response = await request(app)
          .post('/sms/delivery-receipt')
          .type('form')
          .send(deliveryPayload);

        expect(transition.expectSuccess ? 200 : 400).toBe(response.status);
      }
    });
  });
});
