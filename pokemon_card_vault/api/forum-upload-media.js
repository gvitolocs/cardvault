const crypto = require('crypto');
const sharp = require('sharp');
const { verifyBearerToken } = require('../server/_firebase');
const { uploadForumMediaToR2 } = require('../server/_r2');
const { supabaseFetch } = require('../server/_supabase');

const maxUploadBytes = 8 * 1024 * 1024;

function cleanUuid(value) {
  const text = String(value || '').trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)
    ? text
    : null;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { imageBase64, topicId, postId } = req.body || {};
    if (typeof imageBase64 !== 'string' || imageBase64.trim().isEmpty) {
      return res.status(400).json({ error: 'Missing image data.' });
    }

    const cleanTopicId = cleanUuid(topicId);
    const cleanPostId = cleanUuid(postId);
    if (!cleanTopicId && !cleanPostId) {
      return res.status(400).json({ error: 'Upload media after creating a topic or reply.' });
    }

    const rawBase64 = imageBase64.replace(/^data:image\/\w+;base64,/, '');
    const sourceBuffer = Buffer.from(rawBase64, 'base64');
    if (!sourceBuffer.length || sourceBuffer.length > maxUploadBytes) {
      return res.status(400).json({ error: 'Image must be smaller than 8 MB.' });
    }

    const image = sharp(sourceBuffer).rotate().resize(1600, 1600, {
      fit: 'inside',
      withoutEnlargement: true,
    });
    const metadata = await image.metadata();
    const mediaBuffer = await image.webp({ quality: 86 }).toBuffer();
    const mediaId = crypto.randomUUID();
    const storagePath = `forum-media/${decoded.uid}/${mediaId}.webp`;
    const uploaded = await uploadForumMediaToR2({
      key: storagePath,
      body: mediaBuffer,
      contentType: 'image/webp',
    });

    if (!uploaded?.url) {
      return res.status(500).json({
        error:
          'Cloudflare R2 forum media storage is not configured. Add R2_FORUM_MEDIA_BUCKET and R2_FORUM_MEDIA_PUBLIC_URL.',
      });
    }

    const rows = await supabaseFetch('/rest/v1/forum_media?select=*', {
      method: 'POST',
      serviceRole: true,
      headers: { Prefer: 'return=representation' },
      body: {
        owner_uid: decoded.uid,
        topic_id: cleanTopicId,
        post_id: cleanPostId,
        object_key: uploaded.key,
        public_url: uploaded.url,
        mime_type: 'image/webp',
        byte_size: mediaBuffer.length,
        width: metadata.width || null,
        height: metadata.height || null,
      },
    });

    return res.status(200).json({
      media: Array.isArray(rows) ? rows[0] : rows,
    });
  } catch (error) {
    console.error('forum-upload-media failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Forum media upload failed.',
    });
  }
};
