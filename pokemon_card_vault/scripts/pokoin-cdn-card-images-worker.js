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
const EDGE_CACHE_HEADER = "X-Pokoin-CDN-Cache";

export function keepOnR2(requestedKey) {
  const key = String(requestedKey || "").replace(/^\/+/, "");
  return (
    key.startsWith("originals/") ||
    key.startsWith("manifests/") ||
    key.startsWith("competitive/") ||
    /_homepage\.webp$/i.test(key)
  );
}

/** Storage leftover `{ct_id}_*` for public `{card_id = ct_id * 2}_*`. Try as-is first. */
export function leftoverCdnObjectKey(requestedKey) {
  const key = String(requestedKey || "").replace(/^\/+/, "");
  const match = key.match(/^(previews\/)?(\d+)(_.*)$/);
  if (!match) {
    return null;
  }
  const prefix = match[2];
  if (!/^\d+$/.test(prefix) || prefix.length > 16) {
    return null;
  }
  let value;
  try {
    value = BigInt(prefix);
  } catch {
    return null;
  }
  if (value <= 0n || value % 2n !== 0n) {
    return null;
  }
  const leftover = value / 2n;
  if (leftover <= 0n) {
    return null;
  }
  return `${match[1] || ""}${leftover}${match[3]}`;
}

export function jpegCatalogKey(requestedKey) {
  const key = String(requestedKey || "").replace(/^\/+/, "");
  if (!key) {
    return null;
  }
  if (keepOnR2(key) || key.startsWith("previews/")) {
    return key;
  }
  if (/\.jpe?g$/i.test(key)) {
    return key;
  }
  return key.replace(/\.(png|webp)$/i, ".jpg");
}

function withResponseHeaders(response, origin, requestedKey) {
  const headers = new Headers(response.headers);
  // Do not expose the Pi tunnel's Cloudflare cache state as the public
  // Worker's cache state. Cache API hits are reported explicitly below.
  headers.delete("CF-Cache-Status");
  headers.set("X-Pokoin-CDN-Worker", "r2-card-images");
  if (origin) {
    headers.set("X-Pokoin-CDN-Origin", origin);
  }
  if (requestedKey) {
    headers.set("X-Pokoin-CDN-Object-Key", requestedKey);
  }
  if (response.status >= 400) {
    headers.set("Cache-Control", "private, no-store");
  }
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

function edgeCacheRequest(request, epoch = "1") {
  const url = new URL(request.url);
  url.searchParams.set("cdn-e", String(epoch || "1"));
  return new Request(url.toString(), { method: "GET" });
}

function forRequest(response, method, cacheStatus) {
  const headers = new Headers(response.headers);
  headers.set(EDGE_CACHE_HEADER, cacheStatus);
  return new Response(method === "HEAD" ? null : response.body, {
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

function candidateKeys(requestedKey) {
  const out = [];
  const seen = new Set();
  function add(next) {
    if (!next || seen.has(next)) {
      return;
    }
    seen.add(next);
    out.push(next);
  }
  add(requestedKey);
  add(jpegCatalogKey(requestedKey));
  add(leftoverCdnObjectKey(requestedKey));
  add(leftoverCdnObjectKey(jpegCatalogKey(requestedKey)));
  if (/_homepage\.webp$/i.test(requestedKey)) {
    const jpg = requestedKey.replace(/_homepage\.webp$/i, ".jpg");
    add(jpg);
    add(leftoverCdnObjectKey(jpg));
  }
  return out;
}

function rejectMismatchedJpeg(key, response) {
  if (!/\.jpe?g$/i.test(key)) {
    return false;
  }
  const contentType = String(response.headers.get("Content-Type") || "");
  return /image\/webp/i.test(contentType);
}

async function fetchOrigin(origin, key, request, bypassCache) {
  if (!origin) {
    return null;
  }
  // Query is ignored by the Pi origin. It bypasses stale orange-cloud 404s on cdn.pokoin.com.
  const url = `${String(origin).replace(/\/+$/, "")}/${key}${bypassCache ? "?from=pi" : ""}`;
  const init = {
    method: request.method === "HEAD" ? "GET" : request.method,
    redirect: "manual",
  };
  if (bypassCache) {
    init.cf = { cacheTtl: 0, cacheEverything: false };
  }
  const response = await fetch(url, init);
  if (!response.ok) {
    return null;
  }
  if (rejectMismatchedJpeg(key, response)) {
    return null;
  }
  const headers = new Headers(response.headers);
  headers.set("Cache-Control", CACHE_CONTROL);
  const body = request.method === "HEAD" ? null : response.body;
  return new Response(body, { status: response.status, headers });
}

async function fromPi(env, key, request) {
  return fetchOrigin(env.PI_CDN_ORIGIN, key, request, true);
}

async function fromR2(env, key, request) {
  const object = await env.CARD_IMAGES.get(key);
  if (!object) {
    return null;
  }
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("Cache-Control", CACHE_CONTROL);
  const response = new Response(request.method === "HEAD" ? null : object.body, { headers });
  if (rejectMismatchedJpeg(key, response)) {
    return null;
  }
  return response;
}

async function resolveObject(key, request, env) {
  try {
    const piResp = await fromPi(env, key, request);
    if (piResp) {
      return withResponseHeaders(piResp, "pi-local", key);
    }
  } catch (error) {
    console.warn("pi origin miss", key, String(error));
  }

  const r2Resp = await fromR2(env, key, request);
  if (r2Resp) {
    return withResponseHeaders(r2Resp, "r2-backup", key);
  }
  return null;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return withResponseHeaders(new Response(null, { status: 204 }), "none");
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return withResponseHeaders(new Response("Method Not Allowed", { status: 405 }), "none");
    }

    const key = getObjectKey(request.url);
    if (!key) {
      return withResponseHeaders(new Response("Not Found", { status: 404 }), "none");
    }

    const edgeCache = caches.default;
    const cacheRequest = edgeCacheRequest(request, env.CACHE_EPOCH);
    const cached = await edgeCache.match(cacheRequest);
    if (cached) {
      return forRequest(cached, request.method, "HIT");
    }

    for (const candidate of candidateKeys(key)) {
      const hit = await resolveObject(candidate, request, env);
      if (hit) {
        const response = withResponseHeaders(hit, hit.headers.get("X-Pokoin-CDN-Origin"), key);
        if (request.method === "GET") {
          ctx.waitUntil(edgeCache.put(cacheRequest, response.clone()).catch((error) => {
            console.warn("edge cache put failed", key, String(error));
          }));
        }
        return forRequest(response, request.method, "MISS");
      }
    }

    return withResponseHeaders(new Response("Not Found", { status: 404 }), "none", key);
  },
};
