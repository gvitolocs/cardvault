const SERVICE_NAME = "trainingai-cardvault-images";
const BUCKET_NAME = "cardvault-images";
const BEST_BLUEPRINT_IMAGES_KEY = "manifests/best-blueprint-images.json";
const MAX_MANIFEST_LIMIT = 1000;
const DEFAULT_MANIFEST_LIMIT = 100;
const CACHE_CONTROL = "public, max-age=31536000, immutable";
const FORBIDDEN_PREFIXES = [
  "artist-profiles/",
  "avatars/",
  "forum/",
  "profile-pictures/",
  "user/",
  "users/",
];
const ALLOWED_IMAGE_EXTENSIONS = new Set([
  "avif",
  "gif",
  "jpeg",
  "jpg",
  "png",
  "webp",
]);

const SECURITY_HEADERS = {
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Robots-Tag": "noindex, nofollow",
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, If-Modified-Since, If-None-Match, Range",
  "Access-Control-Expose-Headers": "Accept-Ranges, Content-Length, Content-Range, Content-Type, ETag, X-CardVault-TrainingAI-Worker",
  "Access-Control-Max-Age": "86400",
};

function withResponseHeaders(response, extraHeaders = {}) {
  const headers = new Headers(response.headers);
  headers.set("X-CardVault-TrainingAI-Worker", SERVICE_NAME);
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }
  for (const [key, value] of Object.entries(extraHeaders)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function jsonResponse(payload, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", init.cacheControl || "no-store");
  return withResponseHeaders(new Response(JSON.stringify(payload, null, 2), {
    ...init,
    headers,
  }));
}

function htmlResponse(body, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  return withResponseHeaders(new Response(body, {
    ...init,
    headers,
  }));
}

function normalizeObjectKey(rawKey) {
  try {
    const key = decodeURIComponent(rawKey).replace(/^\/+/, "");
    if (!key || key.includes("\0") || key.includes("..")) {
      return "";
    }
    return key;
  } catch {
    return "";
  }
}

function getExtension(key) {
  const basename = key.split("/").pop() || "";
  const dotIndex = basename.lastIndexOf(".");
  if (dotIndex === -1) {
    return "";
  }
  return basename.slice(dotIndex + 1).toLowerCase();
}

function isAllowedObjectKey(key) {
  const normalizedKey = key.toLowerCase();
  if (!ALLOWED_IMAGE_EXTENSIONS.has(getExtension(normalizedKey))) {
    return false;
  }
  return !FORBIDDEN_PREFIXES.some((prefix) => normalizedKey.startsWith(prefix));
}

function encodeObjectKey(key) {
  return key.split("/").map((part) => encodeURIComponent(part)).join("/");
}

function parsePositiveInteger(value, fallback, max) {
  const parsed = Number.parseInt(value || "", 10);
  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }
  return Math.min(parsed, max);
}

function parseRangeHeader(rangeHeader) {
  if (!rangeHeader) {
    return null;
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
  if (!match || (!match[1] && !match[2])) {
    return null;
  }

  if (!match[1]) {
    return { suffix: Number.parseInt(match[2], 10) };
  }

  const start = Number.parseInt(match[1], 10);
  if (match[2]) {
    const end = Number.parseInt(match[2], 10);
    if (end < start) {
      return null;
    }
    return { offset: start, length: end - start + 1 };
  }

  return { offset: start };
}

function getBearerToken(request) {
  const authorization = request.headers.get("Authorization") || "";
  if (authorization.toLowerCase().startsWith("bearer ")) {
    return authorization.slice("bearer ".length).trim();
  }
  return new URL(request.url).searchParams.get("token") || "";
}

async function digestValue(value) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

async function timingSafeEqual(left, right) {
  const leftDigest = await digestValue(left);
  const rightDigest = await digestValue(right);
  let diff = left.length === right.length ? 0 : 1;
  for (let index = 0; index < leftDigest.length; index += 1) {
    diff |= leftDigest[index] ^ rightDigest[index];
  }
  return diff === 0;
}

async function isAuthorized(request, env) {
  if (!env.TRAININGAI_ACCESS_TOKEN) {
    return true;
  }
  const token = getBearerToken(request);
  return timingSafeEqual(token, env.TRAININGAI_ACCESS_TOKEN);
}

function renderIndex() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="Pokoin CardVault read-only image dataset guide for image-recognition training imports.">
    <meta name="robots" content="noindex, nofollow">
    <meta name="theme-color" content="#050816">
    <link rel="icon" href="https://pokoin.com/favicon.ico" sizes="any">
    <link rel="apple-touch-icon" href="https://pokoin.com/apple-touch-icon.png">
    <title>Pokoin CardVault Training Images</title>
    <style>
      :root {
        color-scheme: dark;
        --bg: #050816;
        --bg-soft: #090f22;
        --panel: rgba(15, 23, 42, 0.82);
        --panel-strong: rgba(17, 24, 39, 0.94);
        --line: rgba(250, 204, 21, 0.22);
        --line-soft: rgba(148, 163, 184, 0.18);
        --text: #f8fafc;
        --muted: #a7b0c3;
        --gold: #facc15;
        --gold-strong: #f59e0b;
        --blue: #38bdf8;
        --green: #34d399;
        --shadow: 0 24px 80px rgba(0, 0, 0, 0.42);
      }

      * {
        box-sizing: border-box;
      }

      html {
        scroll-behavior: smooth;
      }

      body {
        min-height: 100vh;
        margin: 0;
        background:
          radial-gradient(circle at 18% 12%, rgba(250, 204, 21, 0.18), transparent 28rem),
          radial-gradient(circle at 88% 8%, rgba(56, 189, 248, 0.16), transparent 25rem),
          linear-gradient(180deg, #050816 0%, #071020 48%, #030712 100%);
        color: var(--text);
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        line-height: 1.6;
      }

      body::before {
        position: fixed;
        inset: 0;
        z-index: -1;
        pointer-events: none;
        content: "";
        background-image:
          linear-gradient(rgba(255, 255, 255, 0.035) 1px, transparent 1px),
          linear-gradient(90deg, rgba(255, 255, 255, 0.035) 1px, transparent 1px);
        background-size: 52px 52px;
        mask-image: linear-gradient(to bottom, rgba(0, 0, 0, 0.76), transparent 82%);
      }

      a {
        color: var(--gold);
        text-decoration: none;
      }

      a:hover {
        text-decoration: underline;
      }

      code,
      pre {
        font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      }

      code {
        border: 1px solid rgba(250, 204, 21, 0.14);
        border-radius: 0.45rem;
        background: rgba(250, 204, 21, 0.08);
        color: #fde68a;
        padding: 0.08rem 0.36rem;
        font-size: 0.92em;
      }

      pre {
        overflow-x: auto;
        margin: 0;
        border-top: 1px solid var(--line-soft);
        background: rgba(2, 6, 23, 0.72);
        color: #dbeafe;
        padding: 1rem;
        line-height: 1.55;
        tab-size: 2;
      }

      .page {
        width: min(1120px, calc(100% - 32px));
        margin: 0 auto;
        padding: 24px 0 54px;
      }

      .nav {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        padding: 12px 0 28px;
      }

      .brand {
        display: inline-flex;
        align-items: center;
        gap: 0.8rem;
        font-weight: 800;
        letter-spacing: -0.02em;
      }

      .brand-mark {
        display: grid;
        width: 42px;
        height: 42px;
        place-items: center;
        border: 1px solid rgba(250, 204, 21, 0.38);
        border-radius: 14px;
        background: linear-gradient(135deg, rgba(250, 204, 21, 0.22), rgba(14, 165, 233, 0.16));
        box-shadow: 0 0 36px rgba(250, 204, 21, 0.16);
        color: var(--gold);
      }

      .brand small {
        display: block;
        color: var(--muted);
        font-size: 0.78rem;
        font-weight: 600;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      .nav-links {
        display: flex;
        flex-wrap: wrap;
        justify-content: flex-end;
        gap: 0.7rem;
      }

      .pill,
      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 38px;
        border: 1px solid var(--line);
        border-radius: 999px;
        background: rgba(15, 23, 42, 0.56);
        color: var(--text);
        padding: 0.48rem 0.82rem;
        font-size: 0.9rem;
        font-weight: 700;
      }

      .button.primary {
        border-color: rgba(250, 204, 21, 0.5);
        background: linear-gradient(135deg, var(--gold), var(--gold-strong));
        color: #111827;
        box-shadow: 0 14px 38px rgba(250, 204, 21, 0.18);
      }

      .hero {
        display: grid;
        grid-template-columns: minmax(0, 1.04fr) minmax(320px, 0.96fr);
        gap: 24px;
        align-items: start;
      }

      .hero-copy,
      .card {
        border: 1px solid var(--line-soft);
        border-radius: 28px;
        background: linear-gradient(180deg, rgba(15, 23, 42, 0.84), rgba(3, 7, 18, 0.88));
        box-shadow: var(--shadow);
      }

      .hero-copy {
        padding: clamp(1.45rem, 3.4vw, 2.55rem);
      }

      .eyebrow {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        margin: 0 0 1.2rem;
        color: #fde68a;
        font-size: 0.8rem;
        font-weight: 800;
        letter-spacing: 0.14em;
        text-transform: uppercase;
      }

      .eyebrow::before {
        width: 8px;
        height: 8px;
        border-radius: 999px;
        background: var(--green);
        box-shadow: 0 0 18px rgba(52, 211, 153, 0.8);
        content: "";
      }

      h1,
      h2,
      h3 {
        margin: 0;
        line-height: 1.08;
        letter-spacing: -0.045em;
      }

      h1 {
        max-width: 720px;
        font-size: clamp(2.4rem, 5.8vw, 4.55rem);
      }

      h2 {
        font-size: clamp(1.45rem, 2.6vw, 2.15rem);
      }

      h3 {
        font-size: 1rem;
        letter-spacing: -0.015em;
      }

      .lead {
        max-width: 700px;
        margin: 1rem 0 0;
        color: #cbd5e1;
        font-size: clamp(0.98rem, 1.7vw, 1.12rem);
      }

      .hero-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 0.8rem;
        margin-top: 1.35rem;
      }

      .status-card {
        display: flex;
        flex-direction: column;
        gap: 1.05rem;
        padding: clamp(1.15rem, 2.2vw, 1.55rem);
      }

      .status-card dl {
        display: grid;
        gap: 0;
        margin: 0;
        border: 1px solid var(--line-soft);
        border-radius: 18px;
        background: rgba(2, 6, 23, 0.28);
      }

      .status-row {
        display: flex;
        justify-content: space-between;
        gap: 1rem;
        border-bottom: 1px solid var(--line-soft);
        padding: 0.78rem 0.85rem;
      }

      .status-row:last-child {
        border-bottom: 0;
      }

      .contract-points {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 0.65rem;
      }

      .contract-point {
        min-height: 72px;
        border: 1px solid rgba(250, 204, 21, 0.18);
        border-radius: 18px;
        background: rgba(250, 204, 21, 0.07);
        padding: 0.75rem;
      }

      .contract-point strong {
        display: block;
        color: var(--gold);
        font-size: 1.22rem;
        line-height: 1;
      }

      .contract-point span {
        display: block;
        margin-top: 0.35rem;
        color: var(--muted);
        font-size: 0.78rem;
        font-weight: 700;
        line-height: 1.25;
      }

      dt {
        color: var(--muted);
      }

      dd {
        margin: 0;
        color: var(--text);
        font-weight: 800;
        text-align: right;
      }

      .section {
        margin-top: 24px;
      }

      .section-header {
        display: flex;
        align-items: end;
        justify-content: space-between;
        gap: 1rem;
        margin: 0 0 1rem;
      }

      .section-header p {
        max-width: 680px;
        margin: 0;
        color: var(--muted);
      }

      .grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 16px;
      }

      .grid.two {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .card {
        overflow: hidden;
        padding: 1.15rem;
      }

      .card p,
      .card ul {
        color: var(--muted);
      }

      .card p {
        margin: 0.65rem 0 0;
      }

      .card ul {
        margin: 0.8rem 0 0;
        padding-left: 1.1rem;
      }

      .endpoint {
        display: flex;
        min-height: 100%;
        flex-direction: column;
        gap: 0.75rem;
      }

      .endpoint strong {
        color: var(--text);
      }

      .endpoint code {
        word-break: break-word;
      }

      .code-card {
        overflow: hidden;
        border: 1px solid var(--line-soft);
        border-radius: 20px;
        background: rgba(15, 23, 42, 0.72);
      }

      .code-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        padding: 0.78rem 0.95rem;
      }

      .code-head span {
        color: #e2e8f0;
        font-weight: 800;
      }

      .copy {
        cursor: pointer;
        border: 1px solid rgba(250, 204, 21, 0.24);
        border-radius: 999px;
        background: rgba(250, 204, 21, 0.08);
        color: #fde68a;
        padding: 0.35rem 0.65rem;
        font: inherit;
        font-size: 0.78rem;
        font-weight: 800;
      }

      .copy:hover {
        border-color: rgba(250, 204, 21, 0.58);
      }

      .note {
        border-color: rgba(56, 189, 248, 0.24);
        background: linear-gradient(180deg, rgba(14, 165, 233, 0.12), rgba(15, 23, 42, 0.7));
      }

      .footer {
        margin-top: 30px;
        color: var(--muted);
        font-size: 0.95rem;
        text-align: center;
      }

      @media (max-width: 860px) {
        .nav,
        .section-header {
          align-items: flex-start;
          flex-direction: column;
        }

        .nav-links {
          justify-content: flex-start;
        }

        .hero,
        .grid,
        .grid.two {
          grid-template-columns: 1fr;
        }

        .hero {
          align-items: stretch;
        }
      }

      @media (max-width: 520px) {
        .page {
          width: min(100% - 22px, 1160px);
          padding-top: 16px;
        }

        .hero-copy,
        .card {
          border-radius: 22px;
        }

        .contract-points {
          grid-template-columns: 1fr;
        }

        pre {
          font-size: 0.78rem;
        }
      }
    </style>
  </head>
  <body>
    <main class="page">
      <nav class="nav" aria-label="Primary">
        <a class="brand" href="https://pokoin.com/" aria-label="Pokoin home">
          <span class="brand-mark">PKN</span>
          <span>
            Pokoin
            <small>CardVault Training AI</small>
          </span>
        </a>
        <div class="nav-links">
          <a class="pill" href="/manifest.json?limit=25">Manifest sample</a>
          <a class="pill" href="https://pokoin.com/marketplace">Marketplace</a>
          <a class="pill" href="https://pokoin.com/docs">Docs</a>
        </div>
      </nav>

      <section class="hero">
        <div class="hero-copy">
          <p class="eyebrow">Read-only image dataset</p>
          <h1>CardVault images for recognition training.</h1>
          <p class="lead">
            This Pokoin endpoint exposes a cache-friendly, read-only view of CardVault card images stored in Cloudflare R2.
            Use it to import card artwork and previews into image-recognition training pipelines without receiving bucket write credentials.
          </p>
          <div class="hero-actions">
            <a class="button primary" href="/manifest.json?limit=100">Open manifest</a>
            <a class="button" href="#examples">Copy import examples</a>
          </div>
        </div>
        <aside class="card status-card" aria-label="Dataset status">
          <div>
            <p class="eyebrow">Endpoint contract</p>
            <h2>Paginated, not capped.</h2>
            <p>
              The default manifest page size is <code>${DEFAULT_MANIFEST_LIMIT}</code>. You can request up to
              <code>${MAX_MANIFEST_LIMIT}</code> objects per page and keep following <code>nextCursor</code>
              until <code>hasMore</code> is <code>false</code>.
            </p>
          </div>
          <div class="contract-points" aria-label="Endpoint limits and access">
            <div class="contract-point"><strong>${DEFAULT_MANIFEST_LIMIT}</strong><span>default page size</span></div>
            <div class="contract-point"><strong>${MAX_MANIFEST_LIMIT}</strong><span>max per request</span></div>
            <div class="contract-point"><strong>0</strong><span>write routes exposed</span></div>
          </div>
          <dl>
            <div class="status-row"><dt>Origin</dt><dd>${BUCKET_NAME}</dd></div>
            <div class="status-row"><dt>Access</dt><dd>GET / HEAD only</dd></div>
            <div class="status-row"><dt>Writes</dt><dd>Not exposed</dd></div>
          </dl>
        </aside>
      </section>

      <section class="section" aria-labelledby="endpoints">
        <div class="section-header">
          <h2 id="endpoints">Endpoints</h2>
          <p>JSON lives at explicit manifest endpoints. The root URL is this guide page.</p>
        </div>
        <div class="grid">
          <article class="card endpoint">
            <strong>Paginated manifest</strong>
            <code>/manifest.json?limit=1000&amp;cursor=&lt;nextCursor&gt;</code>
            <p>Returns object metadata, download URLs, <code>hasMore</code>, and <code>nextCursor</code>.</p>
          </article>
          <article class="card endpoint">
            <strong>Compatibility alias</strong>
            <code>/images.json?limit=100</code>
            <p>Same manifest response for clients that were pointed at the older image index path.</p>
          </article>
          <article class="card endpoint">
            <strong>Best blueprint images</strong>
            <code>/blueprints/best-images.json</code>
            <p>One DB-selected non-homepage image per CardTrader blueprint, generated from Oracle for incremental embedding jobs.</p>
          </article>
          <article class="card endpoint">
            <strong>Object download</strong>
            <code>/images/&lt;object-key&gt;</code>
            <p>Streams the R2 object with image metadata, ETag, byte-range support, and long-lived cache headers.</p>
          </article>
          <article class="card endpoint">
            <strong>Card classifier</strong>
            <code>POST /api/classify</code>
            <p>Accepts an uploaded card image or JSON base64 payload and proxies it to the configured Hugging Face Space classifier.</p>
          </article>
        </div>
      </section>

      <section class="section" aria-labelledby="manifest-shape">
        <div class="section-header">
          <h2 id="manifest-shape">Manifest Shape</h2>
          <p>Each object entry includes fields useful for dataset importers and reproducible training runs.</p>
        </div>
        <div class="grid two">
          <article class="card">
            <h3>Top-level fields</h3>
            <ul>
              <li><code>bucket</code>, <code>access</code>, <code>prefix</code>, and <code>pageSize</code></li>
              <li><code>returned</code>, <code>hasMore</code>, and <code>nextCursor</code></li>
              <li><code>total</code> is intentionally <code>null</code>; iterate pages instead of assuming a total count.</li>
            </ul>
          </article>
          <article class="card">
            <h3>Object fields</h3>
            <ul>
              <li><code>key</code>, <code>size</code>, <code>uploaded</code>, <code>etag</code>, and <code>contentType</code></li>
              <li><code>url</code> for this training endpoint and <code>sameOriginUrl</code> for the Pokoin CDN path</li>
              <li>Optional prefix filtering: <code>/manifest.json?prefix=previews/&amp;limit=100</code></li>
            </ul>
          </article>
          <article class="card">
            <h3>Best blueprint image fields</h3>
            <ul>
              <li><code>count</code>, <code>generated_at</code>, and <code>strategy</code> describe the Oracle snapshot.</li>
              <li>Each object includes <code>blueprint_id</code>, <code>object_key</code>, <code>url</code>, <code>source</code>, <code>name</code>, <code>set_name</code>, and <code>collector_number</code>.</li>
              <li>Use this endpoint for classifier embeddings; it avoids homepage derivatives and lets importers skip already-embedded blueprint IDs.</li>
            </ul>
          </article>
        </div>
      </section>

      <section class="section" id="examples" aria-labelledby="examples-title">
        <div class="section-header">
          <h2 id="examples-title">Import Examples</h2>
          <p>All examples follow cursors until the manifest says there are no more pages.</p>
        </div>
        <div class="grid">
          <article class="code-card">
            <div class="code-head">
              <span>curl + Node JSON parsing</span>
              <button class="copy" data-copy="curl-example" type="button">Copy</button>
            </div>
            <pre id="curl-example">cursor=""
while :; do
  url="https://trainingai.pokoin.com/manifest.json?limit=1000"
  if [ -n "$cursor" ]; then
    url="$url&amp;cursor=$cursor"
  fi
  page="$(curl -fsS "$url")"
  printf '%s\n' "$page" | node -e "let d='';process.stdin.on('data',c=&gt;d+=c).on('end',()=&gt;JSON.parse(d).objects.forEach(o=&gt;console.log(o.url)))"
  cursor="$(printf '%s\n' "$page" | node -e "let d='';process.stdin.on('data',c=&gt;d+=c).on('end',()=&gt;{const j=JSON.parse(d); if (j.nextCursor) console.log(j.nextCursor)})")"
  [ -n "$cursor" ] || break
done</pre>
          </article>

          <article class="code-card">
            <div class="code-head">
              <span>Node fetch importer</span>
              <button class="copy" data-copy="node-example" type="button">Copy</button>
            </div>
            <pre id="node-example">const base = "https://trainingai.pokoin.com/manifest.json";
let cursor = "";

do {
  const url = new URL(base);
  url.searchParams.set("limit", "1000");
  if (cursor) url.searchParams.set("cursor", cursor);

  const page = await fetch(url).then((response) =&gt; response.json());
  for (const object of page.objects) {
    console.log(object.key, object.url, object.contentType, object.size);
    // Download object.url into your dataset store here.
  }
  cursor = page.hasMore ? page.nextCursor : "";
} while (cursor);</pre>
          </article>

          <article class="code-card">
            <div class="code-head">
              <span>Python requests importer</span>
              <button class="copy" data-copy="python-example" type="button">Copy</button>
            </div>
            <pre id="python-example">import requests

base = "https://trainingai.pokoin.com/manifest.json"
cursor = None

while True:
    params = {"limit": 1000}
    if cursor:
        params["cursor"] = cursor
    page = requests.get(base, params=params, timeout=30).json()
    for obj in page["objects"]:
        print(obj["key"], obj["url"], obj.get("contentType"), obj["size"])
        # Download obj["url"] into your dataset store here.
    cursor = page.get("nextCursor") if page.get("hasMore") else None
    if not cursor:
        break</pre>
          </article>

          <article class="code-card">
            <div class="code-head">
              <span>Best blueprint manifest</span>
              <button class="copy" data-copy="best-blueprint-example" type="button">Copy</button>
            </div>
            <pre id="best-blueprint-example">import requests

manifest = requests.get(
    "https://trainingai.pokoin.com/blueprints/best-images.json",
    timeout=120,
).json()

for item in manifest["objects"]:
    print(item["blueprint_id"], item["url"], item["source"])</pre>
          </article>

          <article class="code-card">
            <div class="code-head">
              <span>Classifier upload</span>
              <button class="copy" data-copy="classify-example" type="button">Copy</button>
            </div>
            <pre id="classify-example">curl -X POST https://trainingai.pokoin.com/api/classify \
  -F "image=@card.jpg" \
  -F "top_k=3"</pre>
          </article>
        </div>
      </section>

      <section class="section" aria-labelledby="safety">
        <div class="section-header">
          <h2 id="safety">Safety Notes</h2>
          <p>Designed for sharing data with training collaborators without widening bucket access.</p>
        </div>
        <div class="grid">
          <article class="card note">
            <h3>Read-only by design</h3>
            <p>Only <code>GET</code>, <code>HEAD</code>, and <code>OPTIONS</code> are allowed. Do not share R2 S3 keys or write credentials with import scripts.</p>
          </article>
          <article class="card note">
            <h3>Cache-friendly downloads</h3>
            <p>Image responses include immutable cache headers and ETags, so importers can avoid repeated downloads after the first sync.</p>
          </article>
          <article class="card note">
            <h3>Attribution</h3>
            <p>When publishing model notes or derived datasets, cite Pokoin CardVault as the image source when appropriate.</p>
          </article>
        </div>
      </section>

      <p class="footer">
        Need the marketplace instead? Visit <a href="https://pokoin.com/">Pokoin.com</a>.
        Need JSON? Use <a href="/manifest.json"><code>/manifest.json</code></a>.
      </p>
    </main>

    <script>
      for (const button of document.querySelectorAll("[data-copy]")) {
        button.addEventListener("click", async () => {
          const target = document.getElementById(button.dataset.copy);
          if (!target) return;
          const original = button.textContent;
          try {
            await navigator.clipboard.writeText(target.textContent);
            button.textContent = "Copied";
          } catch (_) {
            button.textContent = "Select text";
          }
          setTimeout(() => {
            button.textContent = original;
          }, 1600);
        });
      }
    </script>
  </body>
</html>`;
}

async function handleManifest(request, env) {
  const url = new URL(request.url);
  const prefix = normalizeObjectKey(url.searchParams.get("prefix") || "");
  if (prefix && FORBIDDEN_PREFIXES.some((blockedPrefix) => prefix.toLowerCase().startsWith(blockedPrefix))) {
    return jsonResponse({ error: "Prefix is not shared by this endpoint." }, { status: 403 });
  }

  const limit = parsePositiveInteger(url.searchParams.get("limit"), DEFAULT_MANIFEST_LIMIT, MAX_MANIFEST_LIMIT);
  const cursor = url.searchParams.get("cursor") || undefined;
  const listed = await env.CARD_IMAGES.list({
    cursor,
    include: ["httpMetadata"],
    limit,
    prefix,
  });
  const objects = listed.objects
    .filter((object) => isAllowedObjectKey(object.key))
    .map((object) => ({
      key: object.key,
      size: object.size,
      uploaded: object.uploaded.toISOString(),
      etag: object.httpEtag,
      contentType: object.httpMetadata?.contentType || null,
      url: `https://trainingai.pokoin.com/images/${encodeObjectKey(object.key)}`,
      sameOriginUrl: `https://pokoin.com/card-images/${encodeObjectKey(object.key)}`,
    }));

  return jsonResponse({
    bucket: BUCKET_NAME,
    access: env.TRAININGAI_ACCESS_TOKEN ? "token-protected-readonly" : "public-readonly",
    prefix,
    pageSize: limit,
    requestedCursor: cursor || null,
    returned: objects.length,
    hasMore: listed.truncated,
    nextCursor: listed.truncated ? listed.cursor : null,
    total: null,
    objects,
  });
}

async function handleBestBlueprintImages(request, env) {
  const object = await env.CARD_IMAGES.get(BEST_BLUEPRINT_IMAGES_KEY);
  if (!object) {
    return jsonResponse({
      ok: false,
      error: "Best blueprint image manifest has not been generated yet.",
    }, { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=3600");
  headers.set("ETag", object.httpEtag);
  headers.set("Content-Length", String(object.size));

  return withResponseHeaders(new Response(request.method === "HEAD" ? null : object.body, {
    headers,
    status: 200,
  }));
}

async function handleImage(request, env, rawKey) {
  const key = normalizeObjectKey(rawKey);
  if (!isAllowedObjectKey(key)) {
    return withResponseHeaders(new Response("Not Found", { status: 404 }));
  }

  const rangeHeader = request.headers.get("Range");
  const range = parseRangeHeader(rangeHeader);
  const object = await env.CARD_IMAGES.get(key, range ? { range } : undefined);
  if (!object) {
    return withResponseHeaders(new Response("Not Found", { status: 404 }));
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Accept-Ranges", "bytes");
  headers.set("Cache-Control", CACHE_CONTROL);
  headers.set("ETag", object.httpEtag);
  headers.set("Content-Length", String(object.size));

  if (range && object.range) {
    const offset = object.range.offset || 0;
    const length = object.range.length || object.size;
    headers.set("Content-Length", String(length));
    headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
  }

  return withResponseHeaders(new Response(request.method === "HEAD" ? null : object.body, {
    headers,
    status: range && object.range ? 206 : 200,
  }));
}

function classifierBaseUrl(env) {
  return String(env.TRAININGAI_CLASSIFIER_URL || env.TRAININGAI_HF_SPACE_URL || "").trim().replace(/\/+$/, "");
}

function classifierToken(env) {
  return String(env.TRAININGAI_HF_TOKEN || env.HF_TOKEN || "").trim();
}

function cleanTopK(value) {
  const parsed = Number.parseInt(value || "", 10);
  if (!Number.isFinite(parsed)) {
    return 3;
  }
  return Math.min(Math.max(parsed, 1), 10);
}

async function pingClassifier(env) {
  const baseUrl = classifierBaseUrl(env);
  if (!baseUrl) {
    console.log(JSON.stringify({
      event: "trainingai-classifier-keepalive-skipped",
      reason: "missing-classifier-url",
    }));
    return;
  }

  const headers = new Headers();
  const token = classifierToken(env);
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  const startedAt = Date.now();
  try {
    const response = await fetch(`${baseUrl}/health`, {
      method: "GET",
      headers,
    });
    console.log(JSON.stringify({
      event: "trainingai-classifier-keepalive",
      ok: response.ok,
      status: response.status,
      durationMs: Date.now() - startedAt,
    }));
  } catch (error) {
    console.log(JSON.stringify({
      event: "trainingai-classifier-keepalive-error",
      error: error && error.message ? error.message : "unknown error",
      durationMs: Date.now() - startedAt,
    }));
  }
}

async function handleClassify(request, env) {
  const baseUrl = classifierBaseUrl(env);
  if (!baseUrl) {
    return jsonResponse({
      ok: false,
      error: "TRAININGAI_CLASSIFIER_URL is not configured.",
      setupRequired: true,
    }, { status: 503 });
  }

  const contentType = request.headers.get("Content-Type") || "";
  const headers = new Headers();
  const token = classifierToken(env);
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  let targetUrl = `${baseUrl}/classify`;
  let body = request.body;

  if (contentType.toLowerCase().includes("application/json")) {
    const payload = await request.json().catch(() => null);
    if (!payload || typeof payload !== "object") {
      return jsonResponse({ ok: false, error: "Invalid JSON body." }, { status: 400 });
    }
    const imageBase64 = payload.imageBase64 || payload.image_base64 || payload.image || "";
    if (!imageBase64) {
      return jsonResponse({ ok: false, error: "imageBase64 is required." }, { status: 400 });
    }
    const topK = cleanTopK(payload.topK || payload.top_k);
    targetUrl = `${baseUrl}/classify/base64`;
    headers.set("Content-Type", "application/json");
    body = JSON.stringify({ imageBase64, topK });
  } else if (contentType.toLowerCase().includes("multipart/form-data")) {
    headers.set("Content-Type", contentType);
  } else {
    return jsonResponse({
      ok: false,
      error: "Use multipart/form-data with image, or application/json with imageBase64.",
    }, { status: 415 });
  }

  const response = await fetch(targetUrl, {
    method: "POST",
    headers,
    body,
  });
  const responseHeaders = new Headers(response.headers);
  responseHeaders.set("Cache-Control", "no-store");
  return withResponseHeaders(new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: responseHeaders,
  }));
}

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(pingClassifier(env));
  },

  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return withResponseHeaders(new Response(null, { status: 204 }));
    }

    if (!(await isAuthorized(request, env))) {
      return withResponseHeaders(new Response("Unauthorized", {
        headers: { "WWW-Authenticate": "Bearer" },
        status: 401,
      }));
    }

    const url = new URL(request.url);
    if (url.pathname === "/api/classify") {
      if (request.method !== "POST") {
        return withResponseHeaders(new Response("Method Not Allowed", {
          headers: { Allow: "POST, OPTIONS" },
          status: 405,
        }));
      }
      return handleClassify(request, env);
    }

    if (request.method !== "GET" && request.method !== "HEAD") {
      return withResponseHeaders(new Response("Method Not Allowed", {
        headers: { Allow: "GET, HEAD, POST, OPTIONS" },
        status: 405,
      }));
    }

    if (url.pathname === "/" || url.pathname === "") {
      return htmlResponse(renderIndex());
    }
    if (url.pathname === "/manifest.json" || url.pathname === "/images.json") {
      return handleManifest(request, env);
    }
    if (url.pathname === "/blueprints/best-images.json") {
      return handleBestBlueprintImages(request, env);
    }
    if (url.pathname.startsWith("/images/")) {
      return handleImage(request, env, url.pathname.slice("/images/".length));
    }

    return withResponseHeaders(new Response("Not Found", { status: 404 }));
  },
};
