const fs = require('fs');
const path = require('path');

const { routeDefinitions } = require('../server/api-route-manifest');

const repoRoot = path.join(__dirname, '..');
const outputPath = path.join(repoRoot, 'docs', 'oracle-api-migration.md');

function bulletList(values) {
  if (!values || values.length === 0) return 'None documented.';
  return values.map((value) => `\`${value}\``).join(', ');
}

function paramsText(params = {}) {
  const entries = Object.entries(params);
  if (entries.length === 0) return 'None documented.';
  return entries.map(([key, value]) => `- ${key}: ${value}`).join('\n');
}

function routeSection(route) {
  return `### ${route.path}

- File: \`api/${route.file}\`
- Methods: ${route.methods.map((method) => `\`${method}\``).join(', ')}
- Purpose: ${route.purpose}
- Auth: ${route.auth}
- Migration status: Hosted by \`server/oracle-api-server.js\`; Vercel fallback remains available until the proxy rewrite is enabled.
- Required query/body/path params:
${paramsText(route.params)}
- Notable env vars: ${bulletList(route.dependencies?.env)}
- External dependencies: ${(route.dependencies?.services || []).join(', ') || 'None documented.'}${route.rawBody ? '\n- Raw body: required. The standalone server does not pre-parse this route so Stripe signature verification receives the original bytes.' : ''}
`;
}

const content = `# Oracle API Migration And Route Reference

This document tracks the first version of moving Pokoin backend API routes from
many Vercel serverless functions into one long-running Node service suitable for
Oracle/peer3. It is generated from \`server/api-route-manifest.js\` so the route
list stays tied to the standalone server configuration.

## Architecture

- Static Flutter web remains deployed by Vercel.
- Existing handlers in \`api/*.js\` remain the business-logic source of truth.
- \`server/oracle-api-server.js\` adapts Node HTTP requests to the current
  Vercel-style \`handler(req, res)\` API, including \`req.query\`, JSON bodies,
  Vercel-like response helpers, and legacy \`.js\` route compatibility.
- \`/healthz\` and \`/api/healthz\` expose service health. \`/api/__routes\`
  exposes a compact route index.
- \`/api/stripe-webhook\` is treated as a raw-body route and is not JSON parsed
  before the existing Stripe signature code reads the request stream.

## peer3 Discovery

\`web/bootstrap-peers.json\` contains \`oracle-peer-3\` / \`pokoin-vm3\` at
\`141.147.62.244\` for the Pokoin peer network. Local SSH config also resolves
\`peer3\`, but no repository script previously deployed this API service there.
The new deployment script uses \`ORACLE_API_SSH_TARGET\` with a default of
\`peer3\`; it does not include or assume credentials.

## Running Locally

\`\`\`bash
npm run api:server
\`\`\`

Useful local variables:

\`\`\`text
PORT=8080
ORACLE_API_HOST=0.0.0.0
ORACLE_API_JSON_LIMIT_BYTES=10485760
ORACLE_API_BASE_URL=https://api.example.com
\`\`\`

The backend also needs the same service env vars already required by the Vercel
functions, such as Firebase Admin, Oracle/Postgres marketplace URLs, Supabase,
Stripe, R2, and Pokoin RPC keys. Keep values out of docs and logs.

## Production Cutover

\`vercel.json\` proxies \`/api/*\` to the Oracle service when
\`deploy-pokoin-web.sh\` runs with \`ORACLE_API_BASE_URL\`. Keep this rewrite
before all local \`/api/*.js\` rewrites:

\`\`\`json
{
  "source": "/api/:path*",
  "destination": "$ORACLE_API_BASE_URL/api/:path*"
}
\`\`\`

The production backend base URL is \`https://api.pokoin.com\`. Treat this API
origin as first-class production infrastructure. \`deploy-pokoin-web.sh\`
switches to the no-serverless workflow whenever \`ORACLE_API_BASE_URL\` is set
or \`USE_ORACLE_API=1\` is set. In that mode the web build must not copy
\`api/*.js\`, \`server/*\`, \`package.json\`, or \`package-lock.json\` into
\`build/web\`, so Vercel deploys a static Flutter frontend and proxies
\`/api/*\` to the Oracle API service. Avoid the checked-in Vercel serverless
fallback unless explicitly requested for an emergency rollback.

Do not run the production Vercel deploy until \`https://api.pokoin.com\` is
healthy. A broken API origin would make production \`/api/*\` routes fail.

## Production Deployment Commands

The Oracle/peer3 backend service should be exposed at \`api.pokoin.com\`.
For production keep the workflow simple: \`pokoin.com\` serves only the Vercel
Flutter frontend, and every \`/api/*\` request rewrites to \`api.pokoin.com\`.

Before switching production, verify the backend directly:

\`\`\`bash
curl -fsS https://api.pokoin.com/marketplace >/dev/null
curl -fsS https://api.pokoin.com/healthz
curl -fsS https://api.pokoin.com/api/__routes
\`\`\`

Deploy production with no bundled Vercel functions only after those origin
checks pass:

\`\`\`bash
ORACLE_API_BASE_URL=https://api.pokoin.com \\
POKOIN_WEB_DEPLOY_TARGET=production \\
./deploy-pokoin-web.sh
\`\`\`

After deployment, verify the production frontend and API rewrite:

\`\`\`bash
curl -fsS https://pokoin.com/ >/dev/null
curl -fsS https://pokoin.com/marketplace >/dev/null
curl -fsS https://pokoin.com/api/healthz
curl -fsS https://pokoin.com/api/__routes
\`\`\`

DNS target: \`api.pokoin.com\` should point at Oracle peer3 \`141.147.62.244\`
through the configured reverse proxy/TLS layer. \`pokoin.com\` should point at
Vercel for the frontend.

Backend landing page:

\`\`\`text
https://api.pokoin.com/marketplace
\`\`\`

Package only:

\`\`\`bash
npm run peer3:bundle
\`\`\`

Upload to peer3 without starting:

\`\`\`bash
ORACLE_API_SSH_TARGET=peer3 npm run peer3:deploy -- --no-restart
\`\`\`

Upload and restart with PM2 if available, otherwise \`nohup\`:

\`\`\`bash
ORACLE_API_SSH_TARGET=peer3 \\
ORACLE_API_REMOTE_DIR=/opt/pokoin/oracle-api \\
ORACLE_API_PORT=8080 \\
npm run peer3:deploy
\`\`\`

If \`api.pokoin.com\` is reachable at DNS but HTTP/S times out, check peer3's
firewall and reverse proxy before deploying production:

\`\`\`bash
sudo ss -ltnp | grep -E ':(80|443|8080)\\\\b'
sudo systemctl status nginx --no-pager || true
sudo systemctl status caddy --no-pager || true
curl -fsS http://127.0.0.1:8080/healthz
\`\`\`

OCI peer3 ingress must allow public TCP \`80\` and \`443\` to the VM. The API
container should stay bound to \`127.0.0.1:18080\` behind Caddy; avoid exposing
the internal API port publicly unless it is an intentional temporary diagnostic.

The script deliberately does not copy \`.env.local\`; provide production
environment variables through the host supervisor or service env file.

## CardTrader Live And Snapshot Routes

The card detail page live route is:

\`\`\`text
GET /api/cardtrader-live-listings?blueprintId=316600
GET /api/cardtrader-live-listings?cardId=248856
\`\`\`

This route calls CardTrader \`GET /api/v2/marketplace/products?blueprint_id=:id\`
with the trusted server global token (\`CARDTRADER_AUTH_TOKEN\` or legacy
fallback \`CARDTRADER_API_TOKEN\`) and does not persist the returned listings.
\`blueprintId\` is a CardTrader blueprint ID; \`cardId\` is a Pokoin card ID that
can be resolved through Oracle card data, with numeric IDs falling back to the
same CardTrader blueprint value. Responses include safe public listing metadata
only and use short in-process/HTTP caching. Without a \`limit\` query param, the
route returns all rows CardTrader returns for the blueprint; explicit limits only
cap the client response. Live rows include inferred
\`shippingMode\`/\`shippingLabel\` metadata; CardTrader does not expose a direct
shipping-type field, so the route derives one-day-ready only from explicit
\`1-Day Ready\` seller/listing text, then derives CardTrader Zero from hub/Zero
flags such as \`can_sell_via_hub\` or
\`can_sell_sealed_with_ct_zero\`. Professional seller status alone is not a Zero
signal, and the inferred metadata is not persisted.

The Oracle/peer4-hosted historical/daily snapshot read route is:

\`\`\`text
GET /api/cardtrader-blueprint-listings?blueprintId=316600
GET /api/cardtrader-blueprint-listings?cardId=274416
\`\`\`

\`blueprintId\` matches CardTrader blueprint columns. \`cardId\` matches
\`pokoin_card_id\` and numeric values also check the blueprint columns for
compatibility with card pages that use blueprint IDs as card IDs. The route reads
current public listing metadata from
\`public.cardtrader_market_listing_snapshots\`; it must not call CardTrader live.
Daily ingestion on peer4 owns snapshot writes from \`GET /marketplace/products\`,
snapshot upserts, and removed-history writes to
\`public.cardtrader_market_listing_removed_history\`. The same peer4 ingestion
path refreshes \`public.cardtrader_blueprint_listing_cache\`, the one-row-per-
blueprint availability cache used by marketplace home/catalog tile payloads to
avoid false out-of-stock states. It may provide a cheapest effective PKN hint
when safely available, but card detail/version rows and seller listing detail
must not use this cache in place of the live CardTrader parser. Tile rendering
must read that Oracle cache internally rather than making CardTrader live calls.

Vercel should proxy these routes to the Oracle API service when \`/api/*\` is
routed to \`api.pokoin.com\`, or serve only temporary compatibility functions
during rollout. Flutter may use the live route on card pages to show CardTrader
current listings/metadata, but responses must contain safe public fields only and
never return tokens, shared secrets, encrypted secret envelopes, raw ingestion
headers, or unbounded CardTrader source payloads.

The generated manifest below lists both routes when the standalone handler and
Vercel compatibility rewrite are available.

## API Routes

${routeDefinitions.map(routeSection).join('\n')}
`;

fs.writeFileSync(outputPath, content);
console.log(`Wrote ${path.relative(repoRoot, outputPath)} with ${routeDefinitions.length} routes.`);
