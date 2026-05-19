const { encodeFilterValue, supabaseFetch } = require('../server/_supabase');

const defaultCategories = [
  {
    id: 'general',
    title: 'General',
    description: 'Community updates and open discussion.',
    icon_name: 'forum',
    sort_order: 10,
    topic_count: 0,
    post_count: 0,
  },
  {
    id: 'cards',
    title: 'Cards',
    description: 'Collecting, grading, trades and marketplace ideas.',
    icon_name: 'cards',
    sort_order: 20,
    topic_count: 0,
    post_count: 0,
  },
  {
    id: 'pkn',
    title: 'PKN and wPKN',
    description: 'Native PKN, wPKN liquidity and DeFi.',
    icon_name: 'token',
    sort_order: 30,
    topic_count: 0,
    post_count: 0,
  },
  {
    id: 'validators',
    title: 'Validators',
    description: 'Nodes, RPC, staking and network operations.',
    icon_name: 'validators',
    sort_order: 40,
    topic_count: 0,
    post_count: 0,
  },
];

function cleanCategoryId(value) {
  const text = String(value || '').trim();
  return /^[a-z0-9_-]{2,40}$/.test(text) ? text : '';
}

function cleanUuid(value) {
  const text = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : '';
}

async function getCategories() {
  return supabaseFetch(
    '/rest/v1/forum_categories?select=id,title,description,icon_name,sort_order,topic_count,post_count&order=sort_order.asc,id.asc',
  );
}

async function getTopics(categoryId) {
  const params = [
    'select=id,category_id,title,body,author_uid,author_name,author_photo_url,reply_count,status,created_at,updated_at',
    'status=eq.open',
    'order=updated_at.desc',
    'limit=50',
  ];
  if (categoryId) {
    params.splice(2, 0, `category_id=eq.${encodeFilterValue(categoryId)}`);
  }
  return supabaseFetch(`/rest/v1/forum_topics?${params.join('&')}`);
}

async function getTopic(topicId) {
  const rows = await supabaseFetch(
    `/rest/v1/forum_topics?select=id,category_id,title,body,author_uid,author_name,author_photo_url,reply_count,status,created_at,updated_at&id=eq.${encodeFilterValue(topicId)}&status=eq.open&limit=1`,
  );
  return Array.isArray(rows) ? rows[0] || null : null;
}

async function getPosts(topicId) {
  return supabaseFetch(
    `/rest/v1/forum_posts?select=id,topic_id,category_id,body,author_uid,author_name,author_photo_url,status,created_at,updated_at&topic_id=eq.${encodeFilterValue(topicId)}&status=eq.open&order=created_at.asc&limit=100`,
  );
}

async function getMedia(topicId) {
  return supabaseFetch(
    `/rest/v1/forum_media?select=id,topic_id,post_id,public_url,mime_type,byte_size,width,height,created_at&topic_id=eq.${encodeFilterValue(topicId)}&order=created_at.asc&limit=100`,
  );
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const categoryId = cleanCategoryId(url.searchParams.get('categoryId'));
    const topicId = cleanUuid(url.searchParams.get('topicId'));
    const mode = String(url.searchParams.get('mode') || 'home');

    if (topicId || mode === 'topic') {
      const cleanTopicId = topicId || cleanUuid(url.searchParams.get('id'));
      if (!cleanTopicId) {
        return res.status(400).json({ error: 'Invalid topic id.' });
      }
      const [topic, posts, media] = await Promise.all([
        getTopic(cleanTopicId),
        getPosts(cleanTopicId),
        getMedia(cleanTopicId),
      ]);
      return res.status(200).json({ topic, posts, media });
    }

    let categories = [];
    let topics = [];
    try {
      [categories, topics] = await Promise.all([
        getCategories(),
        getTopics(categoryId),
      ]);
    } catch (error) {
      console.warn('forum home falling back to default categories', error);
      categories = defaultCategories;
      topics = [];
    }
    if (!Array.isArray(categories) || categories.length === 0) {
      categories = defaultCategories;
    }
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=60');
    return res.status(200).json({ categories, topics });
  } catch (error) {
    console.error('forum read failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Forum data failed.',
    });
  }
};
