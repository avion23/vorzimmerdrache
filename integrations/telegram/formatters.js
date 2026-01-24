function formatMissedCall(callData, timestamp) {
  const { customerName, address, phoneNumber, leadType } = callData;

  return `📞 *Verpasster Anruf*

*Zeit:* ${escapeMarkdown(timestamp)}

*Kunde:* ${escapeMarkdown(customerName || 'Unbekannt')}
*Adresse:* ${escapeMarkdown(address || 'Nicht angegeben')}
*Telefon:* ${escapeMarkdown(phoneNumber || 'Nicht angegeben')}
*Typ:* ${escapeMarkdown(leadType || 'Allgemein')}

Bitte umgehend zurückrufen\\.`;
}

function formatLeadAlert(leadData, timestamp) {
  const { customerName, address, phoneNumber, leadType, priority, notes } = leadData;

  const priorityEmoji = priority === 'high' ? '🔴' : priority === 'medium' ? '🟡' : '🟢';

  let message = `${priorityEmoji} *Neuer Lead\\*

*Zeit:* ${escapeMarkdown(timestamp)}

*Kunde:* ${escapeMarkdown(customerName || 'Unbekannt')}
*Adresse:* ${escapeMarkdown(address || 'Nicht angegeben')}
*Telefon:* ${escapeMarkdown(phoneNumber || 'Nicht angegeben')}
*Typ:* ${escapeMarkdown(leadType || 'Allgemein')}
*Priorität:* ${escapeMarkdown(priority || 'Normal')}`;

  if (notes) {
    message += `

*Notizen:* ${escapeMarkdown(notes)}`;
  }

  message += '\n\nBitte zeitnah kontaktieren\\.';

  return message;
}

function formatDailySummary(summaryData, timestamp) {
  const { date, totalLeads, missedCalls, connectedCalls, topInstallers } = summaryData;

  let message = `📊 *Tägliche Zusammenfassung*

*Datum:* ${escapeMarkdown(date)}

*Statistiken:*
• Gesamt Leads: ${totalLeads || 0}
• Verpasste Anrufe: ${missedCalls || 0}
• Verbundene Anrufe: ${connectedCalls || 0}
• Erfolgsquote: ${totalLeads ? ((connectedCalls / totalLeads) * 100).toFixed(1) : 0}%`;

  if (topInstallers && topInstallers.length > 0) {
    message += `

*Top Installateure:*
${topInstallers.map((installer, index) => {
      return `${index + 1}\\. ${escapeMarkdown(installer.name)}: ${installer.calls} Anrufe`;
    }).join('\n')}`;
  }

  message += `\n\n*Stand:* ${escapeMarkdown(timestamp)}`;

  return message;
}

function formatError(error) {
  return `❌ *Fehler aufgetreten*

*Fehler:* ${escapeMarkdown(error.message || 'Unbekannter Fehler')}

Bitte kontaktieren Sie den Administrator\\.`;
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
  formatMissedCall,
  formatLeadAlert,
  formatDailySummary,
  formatError
};
