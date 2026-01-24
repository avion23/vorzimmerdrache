const { Client } = require('@twilio/rest');
const express = require('express');
const { google } = require('googleapis');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

let config;
try {
  const configPath = process.env.TWILIO_CONFIG_PATH || path.join(__dirname, 'config.json');
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (err) {
  console.error('Config file not found. Using config.example.json as reference.');
  process.exit(1);
}

const twilio = new Client(config.twilio.accountSid, config.twilio.authToken);
const sheets = google.sheets('v4');

async function getSheetAuth() {
  const auth = new google.auth.GoogleAuth({
    keyFile: config.google.credentialsPath,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });
  return await auth.getClient();
}

function getTwiML(templateId, params = {}) {
  const templatePath = path.join(__dirname, 'twiml-templates.xml');
  let xml = fs.readFileSync(templatePath, 'utf8');

  const templateRegex = new RegExp(`<Template id="${templateId}">([\\s\\S]*?)</Template>`);
  const match = xml.match(templateRegex);

  if (!match) {
    console.error(`Template ${templateId} not found`);
    return '<Response><Say>Template error</Say><Hangup/></Response>';
  }

  let twiML = match[1]
    .replace(/{{(\w+)}}/g, (_, key) => params[key] || '')
    .replace(/\{\{(\w+)\}\}/g, (_, key) => params[key] || '');

  twiML = twiML
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<Template[^>]*>/g, '')
    .replace(/<\/Template>/g, '')
    .trim();

  return '<?xml version="1.0" encoding="UTF-8"?>' + twiML;
}

async function updateSheet(callSid, status, outcome) {
  try {
    const auth = await getSheetAuth();
    const values = [
      new Date().toISOString(),
      callSid,
      config.twilio.callerId,
      status,
      outcome,
      callSid
    ];

    await sheets.spreadsheets.values.append({
      auth,
      spreadsheetId: config.google.spreadsheetId,
      range: `${config.google.sheetName}!A:E`,
      valueInputOption: 'USER_ENTERED',
      resource: { values: [values] }
    });
  } catch (err) {
    console.error('Sheet update error:', err.message);
  }
}

async function sendSMSFallback(installerNumber, customerInfo) {
  try {
    await twilio.messages.create({
      from: config.twilio.smsNumber,
      to: installerNumber,
      body: `Neue Anfrage: ${customerInfo.name}, ${customerInfo.address}. Tel: ${customerInfo.phone}. Ruf zurück unter dieser Nummer.`
    });
  } catch (err) {
    console.error('SMS fallback error:', err.message);
  }
}

app.post('/voice/welcome', async (req, res) => {
  const { customerName, address, leadType, customerNumber, callSid } = req.body;

  req.session = req.session || {};
  req.session.callData = {
    customerName,
    address,
    leadType,
    customerNumber,
    callSid,
    startTime: Date.now()
  };

  const twiML = getTwiML('installer-welcome', {
    customerName: customerName || 'Kunde',
    address: address || 'Adresse unbekannt',
    leadType: leadType || 'Allgemein',
    callbackUrl: config.webhook.baseUrl,
    customerNumber
  });

  res.type('application/xml').send(twiML);
});

app.post('/voice/gather', async (req, res) => {
  const { Digits } = req.body;
  const callData = req.session?.callData || {};

  let twiML;

  if (Digits === '1') {
    twiML = getTwiML('dtmf-response-1', {
      customerNumber: callData.customerNumber,
      callerId: config.twilio.callerId,
      callbackUrl: config.webhook.baseUrl
    });
    await updateSheet(callData.callSid, 'answered', 'installer_connected');
  } else if (Digits === '2') {
    twiML = getTwiML('dtmf-response-2', {
      callbackUrl: config.webhook.baseUrl
    });
    await updateSheet(callData.callSid, 'answered', 'installer_deferred');
    await sendSMSFallback(req.body.From, callData);
  } else {
    twiML = getTwiML('dtmf-invalid', {
      callbackUrl: config.webhook.baseUrl
    });
  }

  res.type('application/xml').send(twiML);
});

app.post('/voice/timeout', async (req, res) => {
  const callData = req.session?.callData || {};

  const twiML = getTwiML('installer-timeout', {
    callbackUrl: config.webhook.baseUrl
  });

  await updateSheet(callData.callSid, 'no-answer', 'timeout');
  await sendSMSFallback(req.body.From, callData);

  res.type('application/xml').send(twiML);
});

app.post('/voice/call-complete', async (req, res) => {
  const { DialCallStatus, DialCallDuration, CallStatus } = req.body;
  const callData = req.session?.callData || {};

  let twiML;
  let outcome;

  if (DialCallStatus === 'completed') {
    twiML = getTwiML('call-completed', {
      callDuration: DialCallDuration || '0'
    });
    outcome = 'call_successful';
  } else if (DialCallStatus === 'no-answer' || DialCallStatus === 'busy') {
    twiML = getTwiML('voicemail-fallback', {
      callbackUrl: config.webhook.baseUrl
    });
    outcome = DialCallStatus;
  } else {
    twiML = getTwiML('call-failed');
    outcome = 'call_failed';
  }

  await updateSheet(callData.callSid, CallStatus, outcome);

  res.type('application/xml').send(twiML);
});

app.post('/voice/voicemail-complete', async (req, res) => {
  const { RecordingUrl, RecordingDuration } = req.body;
  const callData = req.session?.callData || {};

  const twiML = getTwiML('voicemail-complete');

  await updateSheet(callData.callSid, 'voicemail', `voicemail_${RecordingDuration}s`);

  if (config.twilio.smsCustomerOnVoicemail) {
    try {
      await twilio.messages.create({
        from: config.twilio.callerId,
        to: callData.customerNumber,
        body: `Ihr Installateur hat eine Nachricht für Sie hinterlassen. Rückruf unter ${config.twilio.callerId}.`
      });
    } catch (err) {
      console.error('Customer SMS error:', err.message);
    }
  }

  res.type('application/xml').send(twiML);
});

app.post('/voice/transcribe', async (req, res) => {
  const { TranscriptionText, RecordingUrl, CallSid } = req.body;

  await updateSheet(CallSid, 'transcribed', TranscriptionText?.substring(0, 200));

  res.send('<Response/>');
});

app.post('/callback/status', async (req, res) => {
  const { CallSid, CallStatus, CallDuration, ErrorCode, ErrorMessage } = req.body;

  const statusMap = {
    'queued': 'queued',
    'ringing': 'ringing',
    'in-progress': 'in-progress',
    'completed': 'completed',
    'busy': 'busy',
    'no-answer': 'no-answer',
    'failed': 'failed',
    'canceled': 'canceled'
  };

  await updateSheet(CallSid, CallStatus, `duration_${CallDuration || 0}s`);

  if (CallStatus === 'failed' || CallStatus === 'no-answer') {
    await sendSMSFallback(req.body.To, { name: 'Kunde', address: '', phone: 'siehe Dashboard' });
  }

  res.status(200).send('OK');
});

app.post('/initiate-call', async (req, res) => {
  const { installerNumber, customerName, address, leadType, customerNumber } = req.body;

  try {
    const call = await twilio.calls.create({
      to: installerNumber,
      from: config.twilio.callerId,
      url: `${config.webhook.baseUrl}/voice/welcome`,
      method: 'POST',
      statusCallback: `${config.webhook.baseUrl}/callback/status`,
      statusCallbackEvent: ['completed', 'failed', 'no-answer', 'busy'],
      statusCallbackMethod: 'POST'
    });

    res.json({
      success: true,
      callSid: call.sid,
      status: call.status
    });
  } catch (err) {
    console.error('Call initiation error:', err.message);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const PORT = config.webhook.port || 3000;
app.listen(PORT, () => {
  console.log(`Twilio webhook server running on port ${PORT}`);
});
