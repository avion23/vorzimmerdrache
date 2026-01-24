const { formatMessage } = require('./bot');

async function handleStatus(chatId, queue) {
  const installers = queue.getAllInstallers();
  const activeCount = Object.keys(installers).length;

  const message = `📊 *Status Übersicht*

*Installateure:* ${activeCount}
*Aktive Chats:* ${activeCount}

${Object.entries(installers).map(([id, name]) => `• ${escapeMarkdown(name)} \\[${escapeMarkdown(id)}]`).join('\n')}
`;

  try {
    const { sendMessage } = require('./bot');
    return await sendMessage(chatId, message);
  } catch (err) {
    console.error('Status command error:', err.message);
  }
}

async function handleToday(chatId, queue) {
  const today = new Date().toISOString().split('T')[0];

  const message = `📅 *Heutige Leads*

*Datum:* ${escapeMarkdown(today)}

Dieses Feature erfordert eine Datenbankverbindung für Lead\\-Statistiken\\. Aktuell werden nur Benachrichtigungen gesendet\\.`;

  try {
    const { sendMessage } = require('./bot');
    return await sendMessage(chatId, message);
  } catch (err) {
    console.error('Today command error:', err.message);
  }
}

async function handleHelp(chatId) {
  const message = `🤖 *Verfügbare Befehle*

/register <Name> – Installateur registrieren
/status – Aktive Installateure anzeigen
/today – Lead\\-Übersicht für heute
/help – Diese Hilfe anzeigen

*Beispiele:*
/register Max Mustermann
/status`;

  try {
    const { sendMessage } = require('./bot');
    return await sendMessage(chatId, message);
  } catch (err) {
    console.error('Help command error:', err.message);
  }
}

async function handleRegister(text, chatId, queue) {
  const parts = text.split(' ');
  const name = parts.slice(1).join(' ').trim();

  if (!name) {
    const message = '❌ *Fehler: Name fehlt*

Verwendung: `/register <Ihr Name>`

Beispiel: `/register Max Mustermann`';
    try {
      const { sendMessage } = require('./bot');
      return await sendMessage(chatId, message);
    } catch (err) {
      console.error('Register command error:', err.message);
    }
    return;
  }

  if (queue.getInstallerName(chatId)) {
    const message = `⚠️ *Bereits registriert*

Sie sind bereits als "${escapeMarkdown(queue.getInstallerName(chatId))}" registriert\\. Um den Namen zu ändern, kontaktieren Sie den Administrator\\.`;
    try {
      const { sendMessage } = require('./bot');
      return await sendMessage(chatId, message);
    } catch (err) {
      console.error('Register command error:', err.message);
    }
    return;
  }

  queue.registerInstaller(chatId, name);

  const message = `✅ *Registrierung erfolgreich*

Willkommen, ${escapeMarkdown(name)}\\!
Sie erhalten jetzt Benachrichtigungen über neue Anrufe und Leads\\.`;

  try {
    const { sendMessage } = require('./bot');
    return await sendMessage(chatId, message);
  } catch (err) {
    console.error('Register command error:', err.message);
  }
}

async function handleUnknown(chatId) {
  const message = `❓ *Unbekannter Befehl*

Verfügbare Befehle:
/status – Installateur\\-Status
/today – Lead\\-Übersicht
/help – Hilfe anzeigen`;

  try {
    const { sendMessage } = require('./bot');
    return await sendMessage(chatId, message);
  } catch (err) {
    console.error('Unknown command error:', err.message);
  }
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

module.exports = {
  handleStatus,
  handleToday,
  handleHelp,
  handleRegister,
  handleUnknown
};
