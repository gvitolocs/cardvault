const assert = require('node:assert/strict');
const test = require('node:test');

const handler = require('./earn-pkn');

function createResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    end() {
      return this;
    },
  };
}

test('Earn PKN form validates required fields', async () => {
  const res = createResponse();
  await handler({
    method: 'POST',
    body: {
      email: 'not-an-email',
      cardList: 'Pikachu promo',
    },
  }, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /valid email/);
});

test('Earn PKN form sends completed payload to contact inbox', async () => {
  const sent = [];
  handler._test.setSendEmailOverride(async (message) => {
    sent.push(message);
    return { ok: true, id: 'email-123' };
  });

  try {
    const res = createResponse();
    await handler({
      method: 'POST',
      body: {
        email: 'collector@example.com',
        numberOfCards: '24',
        valueOfCards: '480 EUR',
        requestMode: 'cards',
        cardList: 'Charizard base set\nPikachu promo',
        language: 'English and Japanese',
        conditions: 'NM to LP',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.ok, true);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, 'contact@pokoin.com');
    assert.match(sent[0].subject, /Card shard PKN request: 24 cards/);
    assert.match(sent[0].text, /collector@example\.com/);
    assert.match(sent[0].text, /Charizard base set/);
    assert.match(sent[0].html, /English and Japanese/);
  } finally {
    handler._test.resetSendEmailOverride();
  }
});

test('Earn PKN form sends deck shard decklist payload', async () => {
  const sent = [];
  handler._test.setSendEmailOverride(async (message) => {
    sent.push(message);
    return { ok: true, id: 'email-456' };
  });

  try {
    const deckList = [
      'Pokemon: 18',
      '3 Mega Kangaskhan ex MEG 104',
      '',
      'Trainer: 27',
      '4 Crispin SCR 133',
      '',
      'Energy: 15',
      '8 Grass Energy MEE 1',
    ].join('\n');
    const res = createResponse();
    await handler({
      method: 'POST',
      body: {
        email: 'deck-builder@example.com',
        requestMode: 'deck',
        numberOfCards: '60',
        valueOfCards: 'deck review',
        deckList,
        deckCards: [
          {
            quantity: 3,
            name: 'Mega Kangaskhan ex',
            setCode: 'MEG',
            collectorNumber: '104',
            category: 'Pokemon',
            version: 'MEG 104 standard',
            selectedVersion: {
              cardId: '316600',
              name: 'Mega Kangaskhan ex',
              set: 'Mega Evolution',
              number: '104',
              rarity: 'Double Rare',
              canonicalPath: '/marketplace/en/cards/633200/mega-kangaskhan-ex',
              imageUrl: 'https://pokoin.com/card-images/previews/316600.webp',
            },
            language: 'English',
            condition: 'Near Mint',
            rawLine: '3 Mega Kangaskhan ex MEG 104',
          },
          {
            quantity: 4,
            name: 'Crispin',
            setCode: 'SCR',
            collectorNumber: '133',
            category: 'Trainer',
            version: 'SCR 133 reverse holo',
            language: 'English',
            condition: 'Lightly Played',
            rawLine: '4 Crispin SCR 133',
          },
        ],
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(sent.length, 1);
    assert.match(sent[0].subject, /Deck shard PKN request: 60 cards/);
    assert.match(sent[0].text, /Request mode: Deck shard/);
    assert.match(sent[0].text, /Mega Kangaskhan ex/);
    assert.match(sent[0].text, /Version: MEG 104 standard/);
    assert.match(sent[0].text, /Marketplace card: 316600/);
    assert.match(sent[0].html, /\/marketplace\/en\/cards\/633200\/mega-kangaskhan-ex/);
    assert.match(sent[0].text, /Condition: Lightly Played/);
    assert.match(sent[0].html, /Grass Energy/);
    assert.match(sent[0].html, /SCR 133 reverse holo/);
  } finally {
    handler._test.resetSendEmailOverride();
  }
});

test('Earn PKN form requires deck card selections when imported rows are sent', async () => {
  const res = createResponse();
  await handler({
    method: 'POST',
    body: {
      email: 'deck-builder@example.com',
      requestMode: 'deck',
      deckCards: [
        {
          quantity: 3,
          name: 'Mega Kangaskhan ex',
          setCode: 'MEG',
          collectorNumber: '104',
          category: 'Pokemon',
          version: 'MEG 104 standard',
          language: 'English',
        },
      ],
    },
  }, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /version, language, and condition/);
});

test('Earn PKN form requires deck sections for deck shard mode', async () => {
  const res = createResponse();
  await handler({
    method: 'POST',
    body: {
      email: 'deck-builder@example.com',
      requestMode: 'deck',
      numberOfCards: '60',
      valueOfCards: 'deck review',
      deckList: '3 Mega Kangaskhan ex MEG 104',
    },
  }, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /Pokemon, Trainer, and Energy/);
});

test('Earn PKN form reports email configuration clearly', async () => {
  handler._test.setSendEmailOverride(async () => ({
    ok: false,
    skipped: true,
    reason: 'RESEND_API_KEY is not configured.',
  }));

  try {
    const res = createResponse();
    await handler({
      method: 'POST',
      body: {
        email: 'collector@example.com',
        numberOfCards: '3',
        valueOfCards: '90 EUR',
        cardList: 'Pikachu promo',
      },
    }, res);

    assert.equal(res.statusCode, 503);
    assert.match(res.body.error, /not configured/);
    assert.match(res.body.reason, /RESEND_API_KEY/);
  } finally {
    handler._test.resetSendEmailOverride();
  }
});
