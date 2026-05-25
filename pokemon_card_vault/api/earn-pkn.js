const { sendEmail } = require('../server/_email');

const DEFAULT_EARN_PKN_TO = 'contact@pokoin.com';
const DEFAULT_EARN_PKN_FROM = 'Pokoin <no-reply@pokoin.com>';
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

let sendEmailOverride = null;

function setCorsHeaders(res) {
  for (const [name, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(name, value);
  }
}

function cleanText(value, maxLength = 1000) {
  return String(value || '')
    .replace(/\r/g, '')
    .trim()
    .slice(0, maxLength);
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function validateEmail(email) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

function normalizeRequestMode(value) {
  const mode = cleanText(value, 40).toLowerCase().replace(/[\s_-]+/g, '-');
  if (mode === 'deck' || mode === 'deck-shard' || mode === 'decklist') {
    return 'deck';
  }
  return 'cards';
}

function hasDeckSections(deckList) {
  const lowerDeckList = String(deckList || '').toLowerCase();
  const hasPokemon = lowerDeckList.includes('pokemon:') || lowerDeckList.includes('pokémon:');
  return hasPokemon &&
    lowerDeckList.includes('trainer:') &&
    lowerDeckList.includes('energy:') &&
    /^\s*\d+\s+\S+/m.test(deckList);
}

function normalizeDeckCards(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((card, index) => {
    const quantityText = cleanText(card?.quantity, 20);
    const quantity = quantityText ? Number(quantityText) : null;
    const selected = card?.selectedVersion && typeof card.selectedVersion === 'object'
      ? card.selectedVersion
      : null;
    const normalized = {
      quantity,
      name: cleanText(card?.name, 240),
      setCode: cleanText(card?.setCode, 40),
      collectorNumber: cleanText(card?.collectorNumber, 40),
      category: cleanText(card?.category, 40),
      version: cleanText(card?.version, 240),
      language: cleanText(card?.language, 80),
      condition: cleanText(card?.condition, 80),
      rawLine: cleanText(card?.rawLine, 400),
      selectedVersion: selected ? {
        cardId: cleanText(selected.cardId, 80),
        name: cleanText(selected.name, 240),
        set: cleanText(selected.set, 160),
        number: cleanText(selected.number, 80),
        rarity: cleanText(selected.rarity, 120),
        canonicalPath: cleanText(selected.canonicalPath, 500),
        imageUrl: cleanText(selected.imageUrl, 500),
      } : null,
    };
    if (!Number.isSafeInteger(normalized.quantity) || normalized.quantity <= 0) {
      throw Object.assign(new Error(`Deck card ${index + 1} must include a valid quantity.`), { statusCode: 400 });
    }
    if (!normalized.name || !normalized.setCode || !normalized.collectorNumber) {
      throw Object.assign(new Error(`Deck card ${index + 1} must include name, set code, and collector number.`), { statusCode: 400 });
    }
    if (!normalized.version || !normalized.language || !normalized.condition) {
      throw Object.assign(new Error(`Deck card ${index + 1} must include version, language, and condition.`), { statusCode: 400 });
    }
    return normalized;
  });
}

function normalizeEarnPknSubmission(body = {}) {
  const email = cleanText(body.email, 320).toLowerCase();
  const requestMode = normalizeRequestMode(body.requestMode ?? body.mode ?? body.shardMode);
  const numberOfCardsText = cleanText(body.numberOfCards ?? body.cardCount, 40);
  const numberOfCards = numberOfCardsText ? Number(numberOfCardsText) : null;
  const valueOfCards = cleanText(body.valueOfCards ?? body.estimatedValue, 120);
  const cardList = cleanText(body.cardList ?? body.listOfCards ?? body.cards, 4000);
  const deckList = cleanText(body.deckList ?? body.decklist ?? body.deckShard, 12000);
  const language = cleanText(body.language, 240);
  const conditions = cleanText(body.conditions ?? body.condition, 800);
  const deckCards = normalizeDeckCards(body.deckCards ?? body.deckCardSelections);

  if (!validateEmail(email)) {
    throw Object.assign(new Error('Enter a valid email address.'), { statusCode: 400 });
  }
  if (numberOfCards !== null && (!Number.isSafeInteger(numberOfCards) || numberOfCards <= 0)) {
    throw Object.assign(new Error('Enter the number of cards as a whole number.'), { statusCode: 400 });
  }
  if (requestMode === 'deck') {
    if (deckCards.length === 0 && !deckList) {
      throw Object.assign(new Error('Import a decklist for deck shard review.'), { statusCode: 400 });
    }
    if (deckCards.length === 0 && !hasDeckSections(deckList)) {
      throw Object.assign(new Error('Deck shard requests must include Pokemon, Trainer, and Energy sections.'), { statusCode: 400 });
    }
  } else if (!cardList) {
    throw Object.assign(new Error('Enter the card list for review.'), { statusCode: 400 });
  }

  return {
    email,
    requestMode,
    numberOfCards,
    valueOfCards,
    cardList,
    deckList,
    deckCards,
    language,
    conditions,
  };
}

function earnPknEmailFrom() {
  return process.env.EARN_PKN_EMAIL_FROM ||
    process.env.NO_REPLY_EMAIL_FROM ||
    DEFAULT_EARN_PKN_FROM;
}

function earnPknEmailTo() {
  return process.env.EARN_PKN_EMAIL_TO || DEFAULT_EARN_PKN_TO;
}

function buildEarnPknEmail(submission) {
  const requestLabel = submission.requestMode === 'deck' ? 'Deck shard' : 'Card shard';
  const deckCardTotal = submission.deckCards.reduce((total, card) => total + card.quantity, 0);
  const cardCountLabel = submission.numberOfCards
    ? `${submission.numberOfCards} card${submission.numberOfCards === 1 ? '' : 's'}`
    : deckCardTotal
      ? `${deckCardTotal} card${deckCardTotal === 1 ? '' : 's'}`
    : 'unspecified cards';
  const subject = `${requestLabel} PKN request: ${cardCountLabel}`;
  const deckCardLines = submission.deckCards.length
    ? submission.deckCards.map((card) => [
      `${card.quantity}x ${card.name} (${card.setCode} ${card.collectorNumber})`,
      `  Category: ${card.category || '-'}`,
      `  Version: ${card.version}`,
      card.selectedVersion?.cardId
        ? `  Marketplace card: ${card.selectedVersion.cardId}${card.selectedVersion.canonicalPath ? ` (${card.selectedVersion.canonicalPath})` : ''}`
        : '',
      `  Language: ${card.language}`,
      `  Condition: ${card.condition}`,
    ].filter(Boolean).join('\n')).join('\n\n')
    : '-';
  const deckCardRows = submission.deckCards.length
    ? submission.deckCards.map((card) => `
        <tr>
          <td style="padding:8px;border-top:1px solid #e2e8f0">${escapeHtml(card.quantity)}</td>
          <td style="padding:8px;border-top:1px solid #e2e8f0">${escapeHtml(card.name)}</td>
          <td style="padding:8px;border-top:1px solid #e2e8f0">${escapeHtml(card.category || '-')}</td>
          <td style="padding:8px;border-top:1px solid #e2e8f0">${escapeHtml(`${card.setCode} ${card.collectorNumber}`)}</td>
          <td style="padding:8px;border-top:1px solid #e2e8f0">
            ${escapeHtml(card.version)}
            ${card.selectedVersion?.cardId ? `<br><span style="color:#64748b">#${escapeHtml(card.selectedVersion.cardId)} ${escapeHtml(card.selectedVersion.canonicalPath || '')}</span>` : ''}
          </td>
          <td style="padding:8px;border-top:1px solid #e2e8f0">${escapeHtml(card.language)}</td>
          <td style="padding:8px;border-top:1px solid #e2e8f0">${escapeHtml(card.condition)}</td>
        </tr>
      `).join('')
    : '<tr><td colspan="7" style="padding:8px;border-top:1px solid #e2e8f0">-</td></tr>';
  const lines = [
    'A collector submitted the PKN shard review form.',
    '',
    `Email: ${submission.email}`,
    `Request mode: ${requestLabel}`,
    `Number of cards: ${submission.numberOfCards || '-'}`,
    `Estimated value: ${submission.valueOfCards || '-'}`,
    `Language: ${submission.language || '-'}`,
    `Conditions: ${submission.conditions || '-'}`,
    '',
    'Card list:',
    submission.cardList || '-',
    '',
    'Decklist:',
    submission.deckList || '-',
    '',
    'Imported deck cards:',
    deckCardLines,
    '',
    `Submitted at: ${new Date().toISOString()}`,
  ];
  const html = `
    <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
      <h1 style="margin:0 0 16px">PKN shard review submission</h1>
      <p>A collector wants to shard cards into PKN.</p>
      <ul>
        <li><strong>Email:</strong> ${escapeHtml(submission.email)}</li>
        <li><strong>Request mode:</strong> ${escapeHtml(requestLabel)}</li>
        <li><strong>Number of cards:</strong> ${escapeHtml(submission.numberOfCards || '-')}</li>
        <li><strong>Estimated value:</strong> ${escapeHtml(submission.valueOfCards || '-')}</li>
        <li><strong>Language:</strong> ${escapeHtml(submission.language || '-')}</li>
        <li><strong>Conditions:</strong> ${escapeHtml(submission.conditions || '-')}</li>
      </ul>
      <h2 style="font-size:16px;margin:20px 0 8px">Card list</h2>
      <pre style="white-space:pre-wrap;background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:14px">${escapeHtml(submission.cardList || '-')}</pre>
      <h2 style="font-size:16px;margin:20px 0 8px">Decklist</h2>
      <pre style="white-space:pre-wrap;background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:14px">${escapeHtml(submission.deckList || '-')}</pre>
      <h2 style="font-size:16px;margin:20px 0 8px">Imported deck cards</h2>
      <table style="border-collapse:collapse;width:100%;font-size:14px">
        <thead>
          <tr>
            <th align="left" style="padding:8px">Qty</th>
            <th align="left" style="padding:8px">Card</th>
            <th align="left" style="padding:8px">Category</th>
            <th align="left" style="padding:8px">Parsed set/number</th>
            <th align="left" style="padding:8px">Selected version</th>
            <th align="left" style="padding:8px">Language</th>
            <th align="left" style="padding:8px">Condition</th>
          </tr>
        </thead>
        <tbody>${deckCardRows}</tbody>
      </table>
      <p style="color:#64748b;font-size:14px">Submitted at ${escapeHtml(new Date().toISOString())}</p>
    </div>
  `;
  return { subject, text: lines.join('\n'), html };
}

async function deliverEarnPknEmail(message) {
  const sender = sendEmailOverride || sendEmail;
  return sender(message);
}

async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const submission = normalizeEarnPknSubmission(req.body || {});
    const message = buildEarnPknEmail(submission);
    const delivery = await deliverEarnPknEmail({
      from: earnPknEmailFrom(),
      to: earnPknEmailTo(),
      subject: message.subject,
      text: message.text,
      html: message.html,
    });

    if (delivery?.skipped) {
      return res.status(503).json({
        error: 'Earn PKN email delivery is not configured.',
        reason: delivery.reason || 'Email provider is not configured.',
      });
    }

    return res.status(200).json({ ok: true, email: delivery });
  } catch (error) {
    if (!error.statusCode || error.statusCode >= 500) {
      console.error('earn-pkn failed', error);
    }
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Earn PKN request failed.',
    });
  }
}

handler._test = {
  buildEarnPknEmail,
  normalizeEarnPknSubmission,
  setSendEmailOverride(fn) {
    sendEmailOverride = fn;
  },
  resetSendEmailOverride() {
    sendEmailOverride = null;
  },
};

module.exports = handler;
