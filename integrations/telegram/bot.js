const axios = require('axios');
const fs = require('fs');
const path = require('path');
const { formatMissedCall, formatLeadAlert, formatDailySummary, formatError } = require('./formatters');
const { handleStatus, handleToday, handleHelp, handleRegister, handleUnknown } = require('./commands');

let config;
try {
  const configPath = process.env.TELEGRAM_CONFIG_PATH || path.join(__dirname, 'bot-config.json');
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (err) {
  console.error('Config file not found. Using bot-config.example.json as reference.');
  process.exit(1);
}

const API_BASE = `https://api.telegram.org/bot${config.botToken}`;

class MessageQueue {
  constructor(maxPerMinute = 20) {
    this.queue = [];
    this.processing = false;
    this.maxPerMinute = maxPerMinute;
    this.sentThisMinute = 0;
    this.lastReset = Date.now();
    this.installers = new Map();
    this.loadInstallers();
  }

  loadInstallers() {
    try {
      const installersPath = config.installersPath || path.join(__dirname, 'installers.json');
      if (fs.existsSync(installersPath)) {
        const data = JSON.parse(fs.readFileSync(installersPath, 'utf8'));
        Object.entries(data).forEach(([chatId, name]) => {
          this.installers.set(chatId, name);
        });
      }
    } catch (err) {
      console.error('Installers load error:', err.message);
    }
  }

  saveInstallers() {
    try {
      const installersPath = config.installersPath || path.join(__dirname, 'installers.json');
      const data = Object.fromEntries(this.installers);
      fs.writeFileSync(installersPath, JSON.stringify(data, null, 2));
    } catch (err) {
      console.error('Installers save error:', err.message);
    }
  }

  registerInstaller(chatId, name) {
    this.installers.set(chatId, name);
    this.saveInstallers();
  }

  getInstallerName(chatId) {
    return this.installers.get(chatId);
  }

  getAllInstallers() {
    return Object.fromEntries(this.installers);
  }

  async add(message) {
    return new Promise((resolve, reject) => {
      this.queue.push({ message, resolve, reject });
      this.process();
    });
  }

  async process() {
    if (this.processing || this.queue.length === 0) return;

    this.processing = true;

    while (this.queue.length > 0) {
      const now = Date.now();
      if (now - this.lastReset >= 60000) {
        this.sentThisMinute = 0;
        this.lastReset = now;
      }

      if (this.sentThisMinute >= this.maxPerMinute) {
        const waitTime = 60000 - (now - this.lastReset);
        await new Promise(resolve => setTimeout(resolve, waitTime));
        this.sentThisMinute = 0;
        this.lastReset = Date.now();
      }

      const { message, resolve, reject } = this.queue.shift();
      try {
        const result = await this.send(message);
        this.sentThisMinute++;
        resolve(result);
      } catch (err) {
        reject(err);
      }
    }

    this.processing = false;
  }

  async send({ method, payload }) {
    try {
      const response = await axios.post(`${API_BASE}/${method}`, payload, {
        timeout: 10000
      });
      if (!response.data.ok) {
        throw new Error(response.data.description || 'Telegram API error');
      }
      return response.data.result;
    } catch (err) {
      throw new Error(`Telegram send failed: ${err.message}`);
    }
  }
}

const queue = new MessageQueue(config.rateLimit || 20);

async function sendMessage(chatId, text, options = {}) {
  const payload = {
    chat_id: chatId,
    text,
    parse_mode: 'MarkdownV2',
    ...options
  };
  return queue.add({ method: 'sendMessage', payload });
}

async function sendPhoto(chatId, photoUrl, caption, options = {}) {
  const payload = {
    chat_id: chatId,
    photo: photoUrl,
    caption,
    parse_mode: 'MarkdownV2',
    ...options
  };
  return queue.add({ method: 'sendPhoto', payload });
}

function formatMessage(template, data = {}) {
  let message = template;
  Object.keys(data).forEach(key => {
    const value = escapeMarkdown(data[key]);
    message = message.replace(new RegExp(`{{${key}}}`, 'g'), value);
  });
  return message;
}

function escapeMarkdown(text) {
  if (!text) return '';
  return String(text)
    .replace(/_/g, '\\_')
    .replace(/\*/g, '\\*')
    .replace(/\[/g, '\\[')
    .replace(/\]/g, '\\]')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)')
    .replace(/~/g, '\\~')
    .replace(/`/g, '\\`')
    .replace(/>/g, '\\>')
    .replace(/#/g, '\\#')
    .replace(/\+/g, '\\+')
    .replace(/-/g, '\\-')
    .replace(/=/g, '\\=')
    .replace(/\|/g, '\\|')
    .replace(/\./g, '\\.')
    .replace(/!/g, '\\!');
}

function getGermanTime() {
  return new Date().toLocaleString('de-DE', {
    timeZone: 'Europe/Berlin',
    dateStyle: 'medium',
    timeStyle: 'short'
  });
}

async function notifyMissedCall(callData) {
  const installers = queue.getAllInstallers();
  const message = formatMissedCall(callData, getGermanTime());

  const results = [];
  for (const [chatId, installerName] of Object.entries(installers)) {
    try {
      const result = await sendMessage(chatId, message);
      results.push({ chatId, installerName, success: true, result });
    } catch (err) {
      console.error(`Failed to notify installer ${installerName}:`, err.message);
      results.push({ chatId, installerName, success: false, error: err.message });
    }
  }
  return results;
}

async function notifyLeadAlert(leadData) {
  const installers = queue.getAllInstallers();
  const message = formatLeadAlert(leadData, getGermanTime());

  const results = [];
  for (const [chatId, installerName] of Object.entries(installers)) {
    try {
      const result = await sendMessage(chatId, message);
      results.push({ chatId, installerName, success: true, result });
    } catch (err) {
      console.error(`Failed to notify installer ${installerName}:`, err.message);
      results.push({ chatId, installerName, success: false, error: err.message });
    }
  }
  return results;
}

async function sendDailySummary(summaryData) {
  const installers = queue.getAllInstallers();
  const message = formatDailySummary(summaryData, getGermanTime());

  const results = [];
  for (const [chatId, installerName] of Object.entries(installers)) {
    try {
      const result = await sendMessage(chatId, message);
      results.push({ chatId, installerName, success: true, result });
    } catch (err) {
      console.error(`Failed to send summary to installer ${installerName}:`, err.message);
      results.push({ chatId, installerName, success: false, error: err.message });
    }
  }
  return results;
}

function handleUpdate(update) {
  if (!update.message || !update.message.text) return;

  const chatId = update.message.chat.id;
  const text = update.message.text;

  const installerName = queue.getInstallerName(chatId);

  if (text.startsWith('/register')) {
    return handleRegister(text, chatId, queue);
  }

  if (!installerName) {
    return sendMessage(chatId, 'Bitte registrieren Sie sich zuerst mit `/register <Ihr Name>`');
  }

  if (text === '/status') {
    return handleStatus(chatId, queue);
  }

  if (text === '/today') {
    return handleToday(chatId, queue);
  }

  if (text === '/help') {
    return handleHelp(chatId);
  }

  return handleUnknown(chatId);
}

async function startWebhook() {
  const express = require('express');
  const app = express();
  app.use(express.json());

  app.post(config.webhook.path, (req, res) => {
    try {
      handleUpdate(req.body);
      res.sendStatus(200);
    } catch (err) {
      console.error('Webhook error:', err.message);
      res.sendStatus(500);
    }
  });

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  await axios.post(`${API_BASE}/setWebhook`, {
    url: config.webhook.url
  });

  app.listen(config.webhook.port, () => {
    console.log(`Telegram bot webhook running on port ${config.webhook.port}`);
  });
}

async function startPolling() {
  let offset = 0;

  const poll = async () => {
    try {
      const response = await axios.get(`${API_BASE}/getUpdates`, {
        params: { offset, timeout: 30 },
        timeout: 35000
      });

      if (response.data.ok && response.data.result) {
        for (const update of response.data.result) {
          offset = update.update_id + 1;
          handleUpdate(update);
        }
      }
    } catch (err) {
      console.error('Polling error:', err.message);
    }

    poll();
  };

  poll();
}

if (require.main === module) {
  if (config.webhook && config.webhook.url) {
    startWebhook();
  } else {
    startPolling();
  }
}

module.exports = {
  sendMessage,
  sendPhoto,
  formatMessage,
  notifyMissedCall,
  notifyLeadAlert,
  sendDailySummary,
  startWebhook,
  startPolling,
  getGermanTime
};
