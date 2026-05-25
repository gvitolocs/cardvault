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
  if (req.method === 'OPTIONS') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(204).end();
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const social = loadSocialAutoposterHelper();
  try {
    const authorized = await social.authorizeSocialRequest(req);
    const body = req.body || {};
    const targets = social.cleanTargets(body.targets || body.target);
    const useAgent = social.boolValue(body.useAgent ?? body.agent, true);
    const content = await social.resolveManualPostInput(body, {
      targets,
      useAgent,
    });
    const postResult = await social.postToTargets(targets, content, {
      dryRun: social.boolValue(body.dryRun, false),
      sendPhoto: social.boolValue(body.sendPhoto, true),
      silent: social.boolValue(body.silent, false),
    });
    return res.status(postResult.ok ? 200 : 502).json({
      ok: postResult.ok,
      dryRun: social.boolValue(body.dryRun, false),
      authorizedBy: authorized.type,
      targets,
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
    console.error('social-autopost failed', {
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Social autopost failed.',
    });
  }
}

module.exports = handler;
module.exports._test = {
  isMissingHelper,
  loadSocialAutoposterHelper,
};
