const assert = require('node:assert/strict');
const test = require('node:test');

const social = require('./_social_autoposter');

test('buildPostContent creates Pokoin copy with card URL and X length cap', () => {
  const content = social.buildPostContent({
    hook: 'Hot on Pokoin:',
    card: {
      cardId: '316600',
      name: 'Leafeon',
      setName: 'Prismatic Evolutions',
      cardNumber: '005/131',
      rarity: 'Rare',
      pricePkn: 4500,
      imageUrl: 'https://cdn.pokoin.com/cards/leafeon.png',
    },
  });

  assert.match(content.text, /Hot on Pokoin: Leafeon/);
  assert.match(content.text, /4,500 PKN/);
  assert.match(content.text, /https:\/\/pokoin.com\/marketplace\/en\/cards\/633200\/rare-leafeon-005-131-prismatic-evolutions/);
  assert.match(content.text, /#Pokoin/);
  assert.equal(content.imageUrl, 'https://pokoin.com/card-images/cards/leafeon.png');
  assert.ok(content.xText.length <= social.X_POST_LIMIT);
});

test('cleanTargets accepts telegram and x aliases only', () => {
  assert.deepEqual(social.cleanTargets('telegram,twitter'), ['telegram', 'x']);
  assert.throws(() => social.cleanTargets('mastodon'), /Unsupported social target/);
});

test('socialAgentEndpoint defaults to peer2 social route', () => {
  assert.equal(social.socialAgentEndpoint({}), social.DEFAULT_SOCIAL_AGENT_ENDPOINT);
  assert.equal(social.socialAgentEndpoint({ SOCIAL_AGENT_ENDPOINT: 'https://peer2.example/' }), 'https://peer2.example/social-post');
});

test('dry-run posting returns redacted platform payloads without fetch', async () => {
  const content = social.buildPostContent({
    message: 'Pokoin social test',
    cardUrl: 'https://pokoin.com/marketplace',
  });
  const result = await social.postToTargets(['telegram', 'x'], content, {
    dryRun: true,
    env: {
      TELEGRAM_CHANNEL_ID: '@pokoin',
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.results.telegram.method, 'sendMessage');
  assert.equal(result.results.telegram.payload.chat_id, '[configured]');
  assert.equal(result.results.x.endpoint, '/2/tweets');
  assert.equal(result.results.x.payload.text.includes('Pokoin social test'), true);
});

test('postToX accepts X_BEARER_TOKEN alias for configured token', async () => {
  const content = social.buildPostContent({
    message: 'Pokoin X token alias test',
    cardUrl: 'https://pokoin.com/marketplace',
  });
  let authHeader = '';
  const result = await social.postToX(content, {
    env: {
      X_BEARER_TOKEN: 'x-user-token',
    },
    fetchImpl: async (_url, options) => {
      authHeader = options.headers.Authorization;
      return {
        ok: true,
        json: async () => ({ data: { id: 'post-1', text: 'posted' } }),
      };
    },
  });

  assert.equal(result.ok, true);
  assert.equal(authHeader, 'Bearer x-user-token');
});

test('postToTelegram uploads card image bytes for sendPhoto', async () => {
  const content = social.buildPostContent({
    message: 'Pokoin Telegram image test',
    cardUrl: 'https://pokoin.com/marketplace',
    imageUrl: 'https://pokoin.com/card-images/leafeon.jpg',
  });
  const calls = [];
  const result = await social.postToTelegram(content, {
    env: {
      TELEGRAM_BOT_TOKEN: 'telegram-token',
      TELEGRAM_CHANNEL_ID: '@pokoin',
    },
    fetchImpl: async (url, options = {}) => {
      calls.push({ url, options });
      if (String(url).includes('/card-images/')) {
        return {
          ok: true,
          headers: new Map([['content-type', 'image/jpeg']]),
          arrayBuffer: async () => Buffer.from('fake-image'),
        };
      }
      assert.match(String(url), /sendPhoto$/);
      assert.equal(options.method, 'POST');
      assert.ok(options.body instanceof FormData);
      return {
        ok: true,
        json: async () => ({ ok: true, result: { message_id: 7 } }),
      };
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.method, 'sendPhoto');
  assert.equal(result.uploadedImage, true);
  assert.equal(result.messageId, 7);
  assert.equal(calls.length, 2);
});

test('postToX uploads media and attaches media id', async () => {
  const content = social.buildPostContent({
    message: 'Pokoin X media test',
    cardUrl: 'https://pokoin.com/marketplace',
    imageUrl: 'https://pokoin.com/card-images/leafeon.jpg',
  });
  const seenBodies = [];
  const result = await social.postToX(content, {
    env: {
      X_ACCESS_TOKEN: 'x-user-token',
    },
    fetchImpl: async (url, options = {}) => {
      if (String(url).includes('/card-images/')) {
        return {
          ok: true,
          headers: new Map([['content-type', 'image/jpeg']]),
          arrayBuffer: async () => Buffer.from('fake-image'),
        };
      }
      seenBodies.push(options.body);
      if (options.body instanceof FormData) {
        return {
          ok: true,
          json: async () => ({ data: { id: 'media-1' } }),
        };
      }
      const payload = JSON.parse(options.body);
      assert.deepEqual(payload.media, { media_ids: ['media-1'] });
      return {
        ok: true,
        json: async () => ({ data: { id: 'post-1', text: payload.text } }),
      };
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.mediaId, 'media-1');
  assert.equal(result.postId, 'post-1');
  assert.equal(seenBodies.length, 4);
});

test('postToX supports OAuth 1.0a token pair for media and post signing', async () => {
  const content = social.buildPostContent({
    message: 'Pokoin OAuth1 media test',
    cardUrl: 'https://pokoin.com/marketplace',
    imageUrl: 'https://pokoin.com/card-images/leafeon.jpg',
  });
  const authHeaders = [];
  const result = await social.postToX(content, {
    env: {
      X_API_KEY: 'consumer-key',
      X_API_SECRET: 'consumer-secret',
      X_ACCESS_TOKEN: 'access-token',
      X_ACCESS_TOKEN_SECRET: 'access-secret',
    },
    fetchImpl: async (url, options = {}) => {
      if (String(url).includes('/card-images/')) {
        return {
          ok: true,
          headers: new Map([['content-type', 'image/jpeg']]),
          arrayBuffer: async () => Buffer.from('fake-image'),
        };
      }
      authHeaders.push(options.headers.Authorization);
      if (String(url).includes('upload.twitter.com')) {
        assert.ok(options.body instanceof FormData);
        return {
          ok: true,
          json: async () => ({ media_id_string: 'media-oauth1' }),
        };
      }
      const payload = JSON.parse(options.body);
      assert.deepEqual(payload.media, { media_ids: ['media-oauth1'] });
      return {
        ok: true,
        json: async () => ({ data: { id: 'post-oauth1', text: payload.text } }),
      };
    },
  });

  assert.equal(result.ok, true);
  assert.equal(result.mediaId, 'media-oauth1');
  assert.equal(result.postId, 'post-oauth1');
  assert.equal(authHeaders.length, 2);
  assert.ok(authHeaders.every((header) => header.startsWith('OAuth ')));
});

test('contentWithOptionalAgent uses social agent copy and preserves canonical URL', async () => {
  const fallbackContent = social.buildPostContent({
    card: {
      cardId: '316600',
      name: 'Leafeon',
      setName: 'Prismatic Evolutions',
      cardNumber: '005/131',
      rarity: 'Rare',
    },
  });
  let requestedUrl = '';
  let requestBody = null;
  const content = await social.contentWithOptionalAgent({
    fallbackContent,
    targets: ['telegram', 'x'],
  }, {
    useAgent: true,
    env: {
      SOCIAL_AGENT_ENDPOINT: 'https://peer2.example/social-post',
      SOCIAL_AGENT_TOKEN: 'agent-token',
    },
    fetchImpl: async (url, options) => {
      requestedUrl = url;
      requestBody = JSON.parse(options.body);
      assert.equal(options.headers.Authorization, 'Bearer agent-token');
      return {
        ok: true,
        json: async () => ({
          telegramText: 'Agent Telegram copy',
          xText: 'Agent X copy',
          provider: 'ollama',
          model: 'qwen',
          source: 'peer2-social-agent',
        }),
      };
    },
  });

  assert.equal(requestedUrl, 'https://peer2.example/social-post');
  assert.match(requestBody.instructions, /not the Pokontact support chatbot/);
  assert.equal(content.agent.ok, true);
  assert.match(content.telegramText, /Agent Telegram copy/);
  assert.match(content.telegramText, /https:\/\/pokoin.com\/marketplace\/en\/cards\/633200/);
  assert.match(content.xText, /https:\/\/pokoin.com\/marketplace\/en\/cards\/633200/);
  assert.ok(content.xText.length <= social.X_POST_LIMIT);
});

test('contentWithOptionalAgent falls back when social agent fails', async () => {
  const fallbackContent = social.buildPostContent({
    message: 'Deterministic copy',
    cardUrl: 'https://pokoin.com/marketplace',
  });
  const content = await social.contentWithOptionalAgent({
    fallbackContent,
    targets: ['x'],
  }, {
    useAgent: true,
    env: {
      SOCIAL_AGENT_ENDPOINT: 'https://peer2.example/social-post',
      SOCIAL_AGENT_TOKEN: 'agent-token',
    },
    fetchImpl: async () => ({
      ok: false,
      status: 503,
      json: async () => ({ error: 'peer2 down' }),
    }),
  });

  assert.equal(content.agent.ok, false);
  assert.equal(content.agent.fallback, true);
  assert.match(content.agent.error, /peer2 down/);
  assert.match(content.telegramText, /Deterministic copy/);
});

test('authorizeSocialRequest accepts shared secret header', async () => {
  const authorized = await social.authorizeSocialRequest({
    headers: {
      'x-pokoin-social-secret': 'test-secret',
    },
  }, {
    SOCIAL_AUTOPOST_SECRET: 'test-secret',
  });

  assert.equal(authorized.type, 'shared_secret');
});

test('selectHotCard maps marketplace hot card rows', async () => {
  const card = await social.selectHotCard({
    query: async (sql, values) => {
      assert.match(String(sql), /marketplace_hot_blueprints/);
      assert.deepEqual(values, [12]);
      return {
        rows: [{
          blueprint_id: 316600,
          name: 'Leafeon',
          set_name: 'Prismatic Evolutions',
          card_number: '005/131',
          rarity: 'Rare',
          image_url: 'https://cdn.pokoin.com/cards/leafeon.png',
          lowest_ask_pkn: 4500,
          active_listing_count: 1,
          listed_quantity: 2,
          hot_score_24h: 42,
        }],
      };
    },
  });

  assert.equal(card.cardId, '316600');
  assert.equal(card.pricePkn, 4500);
  assert.equal(card.cardUrl, 'https://pokoin.com/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions');
});
