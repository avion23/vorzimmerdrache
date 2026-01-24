const MessageService = require('../integrations/waha/message-service');

describe('Opt-Out Compliance Handler', () => {
  let messageService;

  beforeEach(() => {
    messageService = new MessageService({
      pgPool: {
        query: jest.fn()
      }
    });
  });

  describe('checkOptOutStatus', () => {
    it('should return optedOut: true for opted-out leads', async () => {
      const mockQuery = {
        rows: [{ opted_out: true }]
      };
      messageService.pgPool.query.mockResolvedValue(mockQuery);

      const result = await messageService.checkOptOutStatus('+491701234567');

      expect(result.optedOut).toBe(true);
      expect(messageService.pgPool.query).toHaveBeenCalledWith(
        'SELECT opted_out FROM leads WHERE phone = $1',
        expect.any(Array)
      );
    });

    it('should return optedOut: false for active leads', async () => {
      const mockQuery = {
        rows: [{ opted_out: false }]
      };
      messageService.pgPool.query.mockResolvedValue(mockQuery);

      const result = await messageService.checkOptOutStatus('+491701234567');

      expect(result.optedOut).toBe(false);
    });

    it('should handle non-existent leads', async () => {
      const mockQuery = { rows: [] };
      messageService.pgPool.query.mockResolvedValue(mockQuery);

      const result = await messageService.checkOptOutStatus('+491701234567');

      expect(result.optedOut).toBe(false);
      expect(result.leadExists).toBe(false);
    });
  });

  describe('sendWhatsApp', () => {
    it('should throw error if lead is opted out', async () => {
      messageService.checkOptOutStatus = jest.fn().mockResolvedValue({ optedOut: true });

      await expect(
        messageService.sendWhatsApp('+491701234567', 'Test message')
      ).rejects.toThrow('opted out');
    });
  });

  describe('sendSMSFallback', () => {
    it('should throw error if lead is opted out', async () => {
      messageService.checkOptOutStatus = jest.fn().mockResolvedValue({ optedOut: true });
      messageService.twilio = {
        accountSid: 'test',
        authToken: 'test',
        phoneNumber: '+4912345678'
      };

      await expect(
        messageService.sendSMSFallback('+491701234567', 'Test message')
      ).rejects.toThrow('opted out');
    });
  });

  describe('sendMessage', () => {
    it('should throw error if lead is opted out', async () => {
      messageService.checkOptOutStatus = jest.fn().mockResolvedValue({ optedOut: true });

      await expect(
        messageService.sendMessage('+491701234567', 'test_template')
      ).rejects.toThrow('opted out');
    });
  });
});
