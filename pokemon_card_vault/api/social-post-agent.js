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
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const social = loadSocialAutoposterHelper();
  try {
    await social.authorizeSocialRequest(req);
    const body = req.body || {};
    const targets = social.cleanTargets(body.targets || body.target);
    const fallbackContent = social.buildPostContent({
      message: body.message || body.text,
      hook: body.hook,
      hashtags: body.hashtags,
      card: body.card || {},
      cardUrl: body.cardUrl,
      imageUrl: body.imageUrl,
      targets,
    });
    const content = await social.contentWithOptionalAgent({
      fallbackContent,
      targets,
      context: {
        source: 'social-post-agent',
        prompt: social.cleanText(body.prompt, 1000),
      },
    }, {
      useAgent: true,
    });
    return res.status(200).json({
      ok: true,
      agent: content.agent,
      telegramText: content.telegramText,
      xText: content.xText,
      cardUrl: content.cardUrl,
      imageUrl: content.imageUrl,
    });
  } catch (error) {
    console.error('social-post-agent failed', {
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Social post agent failed.',
    });
  }
}

module.exports = handler;
module.exports._test = {
  isMissingHelper,
  loadSocialAutoposterHelper,
};
