function isMissingHelper(error, request) {
  return error.code === 'MODULE_NOT_FOUND' &&
    String(error.message || '').includes(request);
}

function loadSocialAutoposterHelper() {
  try {
    return require('../server/_social_autoposter');
  } catch (error) {
    if (!isMissingHelper(error, '../server/_social_autoposter')) {
      throw error;
    }
    return require('./_social_autoposter');
  }
}

async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const social = loadSocialAutoposterHelper();
  try {
    const authorized = await social.authorizeSocialRequest(req);
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const body = req.body || {};
    const source = req.method === 'GET' ? Object.fromEntries(url.searchParams.entries()) : body;
    const targets = social.cleanTargets(source.targets || source.target);
    const card = await social.selectHotCard({
      window: source.window,
      limit: source.limit,
    });
    if (!card) {
      return res.status(404).json({ error: 'No hot marketplace card is available for autoposting.' });
    }
    const useAgent = social.boolValue(source.useAgent ?? source.agent, true);
    const content = await social.contentWithOptionalAgent({
      hook: source.hook || 'Hot on Pokoin right now:',
      message: source.message || source.text,
      hashtags: source.hashtags,
      card,
      targets,
      context: {
        source: 'hot-card',
        window: social.cleanWindow(source.window),
      },
    }, {
      useAgent,
    });
    const postResult = await social.postToTargets(targets, content, {
      dryRun: social.boolValue(source.dryRun, false),
      sendPhoto: social.boolValue(source.sendPhoto, true),
      silent: social.boolValue(source.silent, false),
    });
    return res.status(postResult.ok ? 200 : 502).json({
      ok: postResult.ok,
      dryRun: social.boolValue(source.dryRun, false),
      authorizedBy: authorized.type,
      window: social.cleanWindow(source.window),
      targets,
      card,
      post: {
        text: content.text,
        xText: content.xText,
        cardUrl: content.cardUrl,
        imageUrl: content.imageUrl,
      },
      agent: content.agent,
      results: postResult.results,
    });
  } catch (error) {
    console.error('social-autopost-hot-card failed', {
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Social hot-card autopost failed.',
    });
  }
}

module.exports = handler;
module.exports._test = {
  isMissingHelper,
  loadSocialAutoposterHelper,
};
