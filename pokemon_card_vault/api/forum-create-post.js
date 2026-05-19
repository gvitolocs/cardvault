const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { encodeFilterValue, supabaseFetch } = require('../server/_supabase');

function cleanUuid(value) {
  const text = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : '';
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
    const topicId = cleanUuid(req.body?.topicId);
    const body = cleanText(req.body?.body, 5000);

    if (!topicId) {
      return res.status(400).json({ error: 'Invalid topic id.' });
    }
    if (body.length < 3) {
      return res.status(400).json({ error: 'Reply must be at least 3 characters.' });
    }

    const topicRows = await supabaseFetch(
      `/rest/v1/forum_topics?select=id,category_id,status&id=eq.${encodeFilterValue(topicId)}&status=eq.open&limit=1`,
      { serviceRole: true },
    );
    const topic = Array.isArray(topicRows) ? topicRows[0] : null;
    if (!topic) {
      return res.status(404).json({ error: 'This topic is no longer open.' });
    }

    const profile = await profileForUid(decoded.uid);
    const rows = await supabaseFetch('/rest/v1/forum_posts?select=*', {
      method: 'POST',
      serviceRole: true,
      headers: { Prefer: 'return=representation' },
      body: {
        topic_id: topic.id,
        category_id: topic.category_id,
        body,
        author_uid: decoded.uid,
        author_name: authorName(profile, decoded.name),
        author_photo_url: profile.photoUrl || decoded.picture || null,
      },
    });

    return res.status(200).json({
      post: Array.isArray(rows) ? rows[0] : rows,
    });
  } catch (error) {
    console.error('forum-create-post failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Reply creation failed.',
    });
  }
};
