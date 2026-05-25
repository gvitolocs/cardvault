function cleanText(value, maxLength = 500) {
  return String(value || '').trim().slice(0, maxLength);
}

function stripHtmlTags(value) {
  return cleanText(value)
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]*>/g, '')
    .replace(/[\u0000-\u001f\u007f]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizedCommentText(value) {
  return stripHtmlTags(value)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9@./:_+-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function isPromotionalSellerComment(value) {
  const text = normalizedCommentText(value);
  if (!text) return false;

  return [
    /\bcheck\s+(?:out\s+)?my\s+(?:store|shop|profile|page|cards|listings|other\s+items)\b/,
    /\bvisit\s+my\s+(?:store|shop|profile|page)\b/,
    /\bsee\s+my\s+(?:store|shop|profile|page|other\s+cards|listings)\b/,
    /\bmore\s+(?:cards|items|listings|products)\s+available\b/,
    /\b(?:other|more)\s+(?:cards|items|listings|products)\s+(?:in|on)\s+my\s+(?:store|shop|profile|page)\b/,
    /\b(?:message|contact|dm|pm)\s+me\b/,
    /\b(?:whatsapp|telegram|instagram|facebook|discord|ebay|vinted)\b/,
    /(?:https?:\/\/|www\.|(?:^|\s)[a-z0-9-]+\.(?:com|it|net|org|shop)\b)/,
  ].some((pattern) => pattern.test(text));
}

function publicSellerComment(value, maxLength = 500) {
  const comment = stripHtmlTags(value).slice(0, maxLength).trim();
  return isPromotionalSellerComment(comment) ? '' : comment;
}

module.exports = {
  isPromotionalSellerComment,
  publicSellerComment,
  _test: {
    normalizedCommentText,
    stripHtmlTags,
  },
};
