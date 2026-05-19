const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { encodeFilterValue, supabaseFetch } = require('../server/_supabase');

const allowedCategories = new Set(['general', 'cards', 'pkn', 'validators']);

function cleanCategoryId(value) {
  const text = String(value || '').trim();
  return allowedCategories.has(text) ? text : '';
}

function cleanText(value, maxLength) {
  return String(value || '').trim().replace(/\s+\n/g, '\n').slice(0, maxLength);
}

async function profileForUid(uid) {
  const admin = getFirebaseAdmin();
  const snapshot = await admin.firestore().collection('users').doc(uid).get();
  return snapshot.exists ? snapshot.data() || {} : {};
}

function authorName(profile, fallback) {
  const username = String(profile.username || '').trim();
  if (username) return username;
  const displayName = String(profile.displayName || '').trim();
  if (displayName) return displayName;
  return fallback || 'Pokoin user';
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const categoryId = cleanCategoryId(req.body?.categoryId);
    const title = cleanText(req.body?.title, 120);
    const body = cleanText(req.body?.body, 5000);
    const cardIds = Array.isArray(req.body?.cardIds)
      ? req.body.cardIds
          .map((value) => Number(value))
          .filter((value) => Number.isSafeInteger(value) && value > 0)
          .slice(0, 12)
      : [];

    if (!categoryId) {
      return res.status(400).json({ error: 'Choose a valid forum category.' });
    }
    if (title.length < 6) {
      return res.status(400).json({ error: 'Topic title must be at least 6 characters.' });
    }
    if (body.length < 12) {
      return res.status(400).json({ error: 'Topic body must be at least 12 characters.' });
    }

    const profile = await profileForUid(decoded.uid);
    const rows = await supabaseFetch('/rest/v1/forum_topics?select=*', {
      method: 'POST',
      serviceRole: true,
      headers: { Prefer: 'return=representation' },
      body: {
        category_id: categoryId,
        title,
        body,
        author_uid: decoded.uid,
        author_name: authorName(profile, decoded.name),
        author_photo_url: profile.photoUrl || decoded.picture || null,
      },
    });
    const topic = Array.isArray(rows) ? rows[0] : rows;

    if (topic?.id && cardIds.length > 0) {
      await supabaseFetch('/rest/v1/forum_topic_cards', {
        method: 'POST',
        serviceRole: true,
        headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' },
        body: cardIds.map((cardId) => ({
          topic_id: topic.id,
          card_id: cardId,
        })),
      }).catch((error) => {
        console.warn(
          `forum topic card links failed for ${encodeFilterValue(topic.id)}: ${error.message}`,
        );
      });
    }

    return res.status(200).json({ topic });
  } catch (error) {
    console.error('forum-create-topic failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Topic creation failed.',
    });
  }
};
