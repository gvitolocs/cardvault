const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Robots-Tag": "noai, noimageai",
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Range",
  "Access-Control-Max-Age": "86400",
};

const CACHE_CONTROL = "public, max-age=31536000, immutable";

function withResponseHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set("X-Pokoin-CDN-Worker", "r2-card-images");
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function getObjectKey(requestUrl) {
  const url = new URL(requestUrl);
  let key = decodeURIComponent(url.pathname.replace(/^\/+/, ""));

  if (key.startsWith("card-images/")) {
    key = key.slice("card-images/".length);
  }

  return key;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return withResponseHeaders(new Response(null, { status: 204 }));
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return withResponseHeaders(new Response("Method Not Allowed", { status: 405 }));
    }

    const key = getObjectKey(request.url);
    if (!key) {
      return withResponseHeaders(new Response("Not Found", { status: 404 }));
    }

    const object = await env.CARD_IMAGES.get(key);
    if (!object) {
      return withResponseHeaders(new Response("Not Found", { status: 404 }));
    }

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    headers.set("Cache-Control", CACHE_CONTROL);

    return withResponseHeaders(new Response(request.method === "HEAD" ? null : object.body, {
      headers,
    }));
  },
};
