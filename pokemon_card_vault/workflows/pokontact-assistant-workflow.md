# Pokontact Assistant Workflow

Use this workflow when changing the Pokontact chatbot/helper assistant, its
Oracle-hosted AI service, Vercel proxy API, email escalation behavior, or the
floating site widget.

`peer2` is the Oracle Cloud instance that should host the real Pokontact AI
service. Do not use `peer2` as the public assistant name.

Naming rule:

- The product/widget/header name can stay `Pokontact ✨`.
- The virtual avatar/persona name is `Poko`. When the assistant introduces
  itself in chat, curated replies, model prompts, or training examples, use
  `Poko`, not `Pokontact`.
- Internal service names, env vars, paths, and operational labels may keep
  `pokontact` / `Pokontact`.

## Current Surfaces

- `lib/widgets/pokoin_assistant.dart`
  - Floating Pokontact chat bubble mounted globally.
  - Sends messages to `/api/pokoin-assistant`.
  - Includes Firebase ID token when the user is signed in.
  - Shows quick prompts for project explanation, cute card picks, wallet basics,
    and bug reporting.
- `lib/main.dart`
  - Mounts `PokoinAssistant` through the `MaterialApp.router` builder.
- `api/pokoin-assistant.js`
  - Vercel gateway/proxy endpoint.
  - Verifies Firebase identity when present.
  - Forwards message, page URL, user identity, and bounded chat transcript to the
    Oracle peer2 Pokontact service when configured.
  - Must return JSON even when the peer2 service is missing, down, or
    misconfigured. Simple greetings such as `ciao` should use the local Poko
    fallback instead of surfacing a generic UI/network error.
  - Keeps email forwarding behavior for likely inquiries/bug reports.
- `services/pokontact/`
  - Dedicated Pokontact AI service intended to run on Oracle Cloud peer2.
  - Exposes `/health`, `/chat`, and the separate social-copy route
    `/social-post`.
  - Must be protected by a shared service token and only called by the Vercel
    gateway or local health checks.
  - Loads `knowledge.md` as the compact project knowledge base used for
    model-backed answers.
- `vercel.json`
  - Rewrites `/api/pokoin-assistant` to `/api/pokoin-assistant.js`.
- `deploy-pokoin-web.sh`
  - Copies API helper modules into `build/web/server`.
  - Requires `build/web/api/pokoin-assistant.js` before deploy so stale helper
    paths such as `require('./_marketplace_db')` fail locally instead of becoming
    a production `FUNCTION_INVOCATION_FAILED`.
- `.env.example`
  - Documents `POKOIN_ASSISTANT_EMAIL`, `POKOIN_ASSISTANT_FROM`,
    `POKONTACT_SERVICE_URL`, `POKONTACT_SERVICE_TOKEN`, and
    `POKONTACT_SERVICE_TIMEOUT_MS`.

## Target Architecture

Pokontact should be a serious AI service with this flow:

1. Flutter widget sends user message and bounded chat record to
   `/api/pokoin-assistant`.
2. Vercel API verifies Firebase ID token when present and attaches safe user
   context.
3. Vercel API calls the peer2 service at `POKONTACT_SERVICE_URL` using
   `POKONTACT_SERVICE_TOKEN`. If `POKONTACT_SERVICE_URL` is unset, the gateway
   defaults to the documented public peer2 URL `http://130.162.242.213:8787`;
   the token is still required for live service calls.
4. Before calling peer2, Vercel must classify marketplace/card/analytics intents
   and fetch grounding data from Oracle-backed APIs/tables. Price, listing,
   floor, "best deal", card lookup, and popularity answers must never come from
   model memory, stale knowledge text, or generated guesses.
5. Peer2 service generates the assistant reply with the Poko persona when the
   request is not fully answered by deterministic site grounding.
6. Assistant navigation/open-page actions are returned as structured client
   actions with sanitized internal paths only.
7. Vercel API returns the reply to the browser and forwards bug/inquiry chat
   records to `POKOIN_ASSISTANT_EMAIL`.

Vercel should be treated as the web/auth/email gateway. Oracle peer2 should be
treated as the assistant runtime.

## Marketplace Grounding Architecture

`/api/pokoin-assistant` owns site-side marketplace grounding. Keep this logic in
the gateway unless a public API is useful for another client.

Payload sent by Flutter:

```json
{
  "message": "most expensive charizard card",
  "messages": [{ "role": "user", "text": "..." }],
  "page": "https://pokoin.com/marketplace/en/cards/633200/...",
  "pageContext": {
    "url": "https://pokoin.com/...",
    "path": "/marketplace/en/cards/633200/...",
    "title": "Marketplace card detail",
    "cardId": "316600",
    "cardTitle": "Rare Leafeon 005 131 Prismatic Evolutions"
  }
}
```

The widget must keep `messages` bounded. Current behavior sends the latest 12
non-empty messages plus route/card context derived from `GoRouterState` and
`Uri.base`.

Gateway data sources:

- `marketplace_user_listings`: active seller listings for highest price, floor
  price, and best-deal style queries. Filter to `status = 'active'`,
  `quantity_available > 0`, and positive `price_pkn`.
- `marketplace_blueprint_price_summary`: active listing floor/listed quantity
  summary shown as context beside cards.
- `marketplace_search_candidates`: card/blueprint resolution by name, set,
  number, and current page card id.
- `marketplace_card_urls`: canonical direct card URLs. Assistant links,
  card-result actions, and user-facing card navigation must use the stored
  `canonical_path` from this table or `/api/marketplace-card-url`; do not
  synthesize slugs from card names in assistant/client code.
- `marketplace_hot_blueprints`: popularity/analytics context such as views,
  searches, clicks, cart/reserve/sale counts, and hot scores.

For grounded intents the gateway may return a deterministic answer immediately.
It should also pass `marketplaceContext` to peer2 when a model-backed wording path
is used. The peer2 prompt must treat that context as the only allowed source for
prices, listings, popularity, and direct card links. If the context is empty or
data is missing, Poko must say that marketplace data is unavailable rather than
guessing.

Follow-ups such as `leafeon?` after `most expensive charizard card` should reuse
the previous marketplace intent from the bounded chat history and apply it to the
new short subject.

Grounded replies must cite the source in plain language, for example "active
Pokoin marketplace listings" or `marketplace_hot_blueprints`, and include "not
financial advice" for price/popularity contexts.

Card recommendation/navigation rules:

- When Poko chooses a concrete card, return a direct card-page `navigate` action.
  Do not send the user to `/marketplace/search?...` unless exact card-page
  resolution fails.
- Cute-card, illustration-card, and "show/open the most expensive card" replies
  must resolve `marketplace_card_urls.canonical_path` and use that path in both
  the structured action and any user-visible link.
- Normalize command phrases out of lookup subjects before querying. Examples:
  `fammi vedere la carta di leafeon più costosa` resolves the subject
  `leafeon`, not `vedere leafeon`; `show me the most expensive Leafeon card`
  resolves `Leafeon`, not `show me Leafeon`.
- Treat `fammi vedere`, `mostrami`, `show me`, `find me`, `carta di`, and
  `card of` as action scaffolding, not search terms.

Current-card contextual answers:

- On card detail pages, questions such as `come lo vedi come investimento
  questo?`, `vale la pena?`, `what do you think of this card?`, and `is this a
  good investment?` are current-card value/opinion questions, not docs/node
  questions.
- Use `pageContext` first: card name, expansion, collector number, rarity, artist,
  condition, price, stock, and current route when available.
- Keep the answer in the user's language and mention the current card directly.
- Always frame value/investment wording as collector context, not financial
  advice. Do not predict guaranteed returns.
- Bounded public community sentiment may be used as soft context, but do not say
  "people on Reddit think" or "la gente su Reddit pensa". Prefer wording like
  `nel sentiment collezionistico online` or `tra i collezionisti emerge`.

## Navigation And Current Page Actions

Assistant actions that navigate, open, or update a page must go through one of
these controlled paths:

- A structured client action such as `{ "type": "navigate", "path": "/..." }`.
- A user-current-page/session page API that stores or opens the current page for
  the signed-in session.

Navigation rules:

- Accept internal paths only. Strip origin, reject external URLs, block protocol
  tricks such as `javascript:`, and keep query strings bounded.
- Marketplace card paths must come from `marketplace_card_urls` or
  `/api/marketplace-card-url`, including card suggestions and grounded
  marketplace/card-price answers.
- Tile/card taps in the Flutter UI must also use the DB canonical URL. Generated
  fallback slugs are only for legacy direct URL repair/redirect paths such as
  short links, never for user-facing tile taps or assistant actions.
- If a user-current-page/current-session-page API is added, update
  `server/api-route-manifest.js`, `vercel.json`, `deploy-pokoin-web.sh`,
  `docs/pokoin-api.md` or regenerated API docs, and
  `api/pokoin-checkout-deploy-layout.test.js` in the same change. Do not leave a
  debug/session API routable but absent from deploy packaging or the route
  manifest.

## Oracle Peer2 Deployment

Peer2 public host from the bootstrap manifest:

```text
130.162.242.213
```

Before deploying, verify SSH access:

```bash
cd /Users/giuseppe/pokoinpos
chmod 600 "keys/peer2/ssh-key-2026-05-15.key"
ssh -i "keys/peer2/ssh-key-2026-05-15.key" \
  -o BatchMode=yes \
  -o ConnectTimeout=8 \
  ubuntu@130.162.242.213 'hostname'
```

The peer2 SSH key lives in the private PokoinPoS keys folder:

```text
/Users/giuseppe/pokoinpos/keys/peer2/ssh-key-2026-05-15.key
```

Always check `/Users/giuseppe/pokoinpos/keys/ORACLE_ACCESS_GUIDE.md` before
trying generic SSH commands. The key folder is private and gitignored; do not
print key contents or commit anything from it.

Only if the explicit key command above fails, try the generic agent/default-key
checks:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 ubuntu@130.162.242.213 'hostname'
```

If `ubuntu` fails, try the expected Oracle Linux user:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 opc@130.162.242.213 'hostname'
```

If both fail with `Permission denied (publickey)`, stop and restore/add the
correct SSH key for peer2 before continuing. Do not claim Pokontact is running on
Oracle peer2 until this check succeeds and `/health` responds from the service.

Recommended service shape on peer2:

- app directory: `/opt/pokontact`
- env file: `/opt/pokontact/.env`
- Docker image: `pokontact-service:local`
- container name: `pokontact-service`
- local port: `8787`
- public exposure: HTTPS reverse proxy, private tunnel reachable by Vercel, or
  an Oracle security-list opening for TCP `8787`
- health endpoint: `/health`
- chat endpoint: `/chat`
- social-copy endpoint: `/social-post` for autoposter copy generation only; do
  not route support chatbot traffic there and do not point social autoposting at
  `/chat`.

Minimum env:

```env
POKONTACT_SERVICE_TOKEN=
POKONTACT_AI_BASE_URL=http://pokontact-ollama:11434/v1
POKONTACT_AI_API_KEY=ollama-local
POKONTACT_MODEL_PROVIDER=local-ollama
POKONTACT_MODEL=qwen2.5:0.5b
POKONTACT_MAX_TOKENS=96
POKONTACT_TEMPERATURE=0.7
POKONTACT_MODEL_TIMEOUT_MS=3500
POKONTACT_ESCALATED_MODEL_TIMEOUT_MS=6000
POKONTACT_OLLAMA_KEEP_ALIVE=30m
POKONTACT_OLLAMA_THREADS=2
POKONTACT_WARM_INTERVAL_MS=240000
POKOIN_ASSISTANT_EMAIL=pokoinpos@gmail.com
POKOIN_ASSISTANT_FROM=Poko <poko@pokoin.com>
```

Pokontact must use a real model provider in production, but the cost-safe default
is a local Ollama model on peer2. Vercel AI Gateway has free credits, but model
usage can become billable, so do not use Gateway as the default runtime unless
the user explicitly approves paid/credit-based usage.

### Optional DeepSeek Provider

The Kimi Code CLI path is not used for Pokontact: it requires Kimi Code quota and
returned `402 Payment Required` during peer2 testing. Keep Pokontact on the
cost-safe local Ollama provider unless the user explicitly asks to use a funded
cloud provider.

For the early "wow effect" stage, Pokontact can use a multi-provider chain that
spends free external quotas first and falls back to local Ollama automatically.
Treat these free providers as best-effort: short timeouts, no secrets in prompts,
and always keep Ollama last.

```env
POKONTACT_MODEL_CHAIN=llm7_fast,llm7_default,llm7_gpt_oss,llm7_codestral,llm7_glm_flash,pollinations_fast,pollinations_openai,ollama
POKONTACT_PROVIDER_COOLDOWN_MS=60000
POKONTACT_OLLAMA_FALLBACK_MODEL=qwen2.5:0.5b
```

The built-in free selectors are:

- `llm7_fast`, `llm7_default`, `llm7_gpt_oss`, `llm7_codestral`,
  `llm7_glm_flash` using `https://api.llm7.io/v1`.
- `pollinations_fast`, `pollinations_openai` using the no-key Pollinations text
  endpoint.

If a provider rate-limits, returns quota/payment errors, breaks, or returns an
empty response, the service tries the next provider and temporarily cools down
that provider before retrying it.

DeepSeek has no official free server-side CLI equivalent for production Poko
traffic. Its supported production path is the OpenAI-compatible API:

```env
POKONTACT_MODEL_PROVIDER=openai-compatible
POKONTACT_AI_BASE_URL=https://api.deepseek.com
POKONTACT_AI_API_KEY=<deepseek api key>
POKONTACT_MODEL=deepseek-v4-flash
POKONTACT_MAX_TOKENS=160
POKONTACT_TEMPERATURE=0.5
POKONTACT_MODEL_TIMEOUT_MS=6000
POKONTACT_ESCALATED_MODEL_TIMEOUT_MS=9000
```

Store live keys only on peer2, never in git. If the DeepSeek API returns
`Insufficient Balance` or HTTP `402`, do not switch the live Pokontact container
to DeepSeek as the only provider. Keep it in the chain only if you want it to be
tried after free providers and before Ollama.

For terminal experiments on peer2, the user-selected wrapper is:

```bash
sudo npm install -g run-deepseek-cli
sudo ln -sfn /usr/bin/deepseek-cli /usr/local/bin/deepseek
```

The package uses `deepseek-cli` as its real binary name. Local mode can talk to
Ollama; cloud mode still requires a funded `DEEPSEEK_API_KEY`.

Known Pokoin/project/card/crypto/support intents should use curated local
answers so they are fast and accurate. Common greetings and clarification
messages such as `ciao`, `hi`, `in che senso?`, and `what do you mean?` should
also use curated local replies. Do not send these tiny conversational messages to
the local LLM; on the current 2-vCPU peer2 VM, even small Ollama models can take
several seconds for free-form generation.

Common node/peer/validator questions must also be curated. If a user says
`node`, `nodo`, `creare un nodo`, `validator`, `peer`, or similar without naming
another chain, Pokontact should assume PokoinPoS, not Bitcoin/Ethereum. Ask
whether they want a local test node, public Oracle/VPS node, or production
validator/peer before giving deployment steps.

Production routing should be multilingual for common support paths. Keep
accent-normalized intent matching for at least English, Italian, Spanish, French,
German, and Portuguese phrases around:

- greetings and clarification
- bug/support/inquiry
- cards and cute suggestions
- NFTs and minting
- chain ID, RPC, explorer, and network metadata
- nodes, validators, peers, and bootstrap
- wallet, MetaMask, PKN, wPKN, Swap, and bridge basics
- project/marketplace explanation
- live status / online / health questions
- earning/rewards questions

For these common paths, prefer curated replies or tightly grounded knowledge
sections over open-ended local LLM generation. The local model is a fallback for
true free-form conversation, not the source of truth.

For earning questions such as `how do I earn`, `come si guadagna`, `rewards`,
`ricompense`, `ganar`, `gagner`, `verdienen`, or `ganhar`, never invent
achievements, reward programs, price opportunities, or fake guide URLs. State
that there is no public automatic rewards/achievements program unless explicitly
launched. Mention only realistic current paths: marketplace selling/listing,
available PKN app features, or node/peer participation if opened by the team.
Always avoid financial advice.

Earning detection must tolerate common typos such as `cosa gudagno`,
`gudagno`, and similar near-misses.

Technical questions should not be improvised by the model. For project, wallet,
PKN, Swap, network, node, status, NFT, marketplace, buying, and earning
questions, Pokontact should point users to the official site documentation at
`https://pokoin.com/docs` and name the most relevant section. Use the local
model only for casual chat or prompts that are clearly not technical.

Intent routing must be typo-tolerant before falling back to unknown answers.
Common technical misspellings such as `ode` for node, `walet`, `metamsk`,
`swpa`, `marektplace`, or similar near-misses should still route to the relevant
docs section. Use normalized text plus edit-distance matching for short
technical keywords.

For unknown/off-topic casual questions, the first response should be instant,
lightly varied, and honest: "I don't know the answer yet, but I'm always
improving." If the user asks again after that unsure reply, escalate to the
local model with a lower temperature, a stricter prompt, and a separate longer
timeout (`POKONTACT_ESCALATED_MODEL_TIMEOUT_MS`). This gives fast first contact
without pretending to know, while still improving accuracy when the user insists.

Funny/joke prompts may use curated local replies. If a casual prompt reaches the
local model, model calls must still have a short timeout
(`POKONTACT_MODEL_TIMEOUT_MS`) and fall back quickly instead of making users wait
tens of seconds.

## Better Fine-Tuning Strategy

Current best practice is not to fine-tune a model to memorize live Pokoin facts.
Use the docs page/RAG-style grounding for facts, because docs change and
fine-tuned knowledge goes stale. Fine-tuning is useful for behavior: tone,
refusal style, "I don't know yet" behavior, typo tolerance, language matching,
and when to point to docs.

Recommended production loop:

1. Build an eval set before training. Include real bad prompts and expected
   outcomes: `how do i run an ode` -> docs `Run a node`, `my name is giuseep`
   -> casual introduction, `what is your pokemon preferito` -> casual favorite,
   `can you explian pokoin` -> docs `Overview`.
2. Keep deterministic routing for high-risk/site facts: PKN, wallet, node,
   marketplace, Swap, NFT, status, earning, support, and docs links.
3. Collect 50-100 high-quality chat examples first. More examples are useful
   only after quality and consistency are good.
4. Format examples as chat JSONL: system message, user message, assistant
   response. Match the exact production prompt style.
5. Balance the dataset. Do not make most examples "I don't know", or the model
   will overuse it. Include casual chat, playful replies, docs referrals,
   bug-report escalation, multilingual typos, and card suggestions.
6. Train behavior with LoRA/QLoRA if staying local. Use RAG/docs for knowledge.
   For single-GPU/low-cost training, tools like Unsloth or Axolotl are the
   common path; export/merge and convert to GGUF for Ollama afterward.
7. Compare the fine-tuned model against the current rule/RAG baseline using the
   eval set before deployment. Do not deploy just because training completed.
8. Keep a fallback. If the local model is slow or uncertain, return the curated
   answer or docs link rather than hallucinating.

For the current Oracle peer2 setup, the next practical step is an eval/test
file, not training. The model is tiny and slow under contention, so quality gains
should first come from routing, typo normalization, and a curated dataset. Once
the eval set is stable, train a LoRA on a stronger small model or move inference
to a larger/faster host.

Implemented local assets:

- `services/pokontact/evals/pokontact-eval-cases.json` keeps regression cases
  for routing, typo handling, docs referrals, casual chat, and escalation.
- `services/pokontact/scripts/run-evals.js` runs those cases against
  `POKONTACT_EVAL_ENDPOINT` (defaults to local peer2 service).
- `services/pokontact/training/pokontact-behavior-seed.jsonl` is the seed
  chat-format behavior dataset for future LoRA/QLoRA fine-tuning.
- `services/pokontact/scripts/validate-training-jsonl.js` verifies the seed data
  has valid chat JSONL structure.

Useful commands:

```bash
cd services/pokontact
npm run check
npm run validate:training

# Local service eval, requires the service running and token if configured.
POKONTACT_SERVICE_TOKEN=... npm run eval

# Public site eval through Vercel proxy.
POKONTACT_EVAL_ENDPOINT=https://pokoin.com/api/pokoin-assistant npm run eval
```

When the user asks whether Pokoin, RPC, Scan, the chain, or the network is
online/live/up/healthy, Pokontact should call public APIs with short timeouts
before answering. Use live checks such as:

- `https://rpc.pokoin.com/health`
- `https://rpc.pokoin.com/chain/status`
- `https://pokoin.com/bootstrap-peers.json`

Do not claim live status from memory.

The local model handles only open-ended/rude/free-form messages that are not
covered by deterministic routing. The old rule engine is otherwise a fallback for
provider outages or missing AI credentials. The current service speaks
OpenAI-compatible chat completions, so `POKONTACT_AI_BASE_URL` can point to local
Ollama or another OpenAI-compatible endpoint.

Current measured baseline:

- Curated project answer through `pokoin.com`: about `0.2s`.
- Curated project answer direct to peer2: about `0.04s`.
- Free-form local model through `pokoin.com` on `qwen2.5:0.5b`: about `10s`.
- Free-form local model direct to peer2 can be much slower during contention or
  cold paths, observed around `24s`.
- `qwen2.5:1.5b` is a better model but is not a speed fix on this VM; a simple
  warm CLI check was slower than `qwen2.5:0.5b`.

If `POKONTACT_AI_API_KEY` is missing, `/health` reports `"ai": false` and the
assistant is not considered production-ready.

Deploy/update the current Dockerized service:

```bash
cd /Users/giuseppe/cardvault/pokemon_card_vault
tar -C services -czf /tmp/pokontact-service.tgz pokontact

cd /Users/giuseppe/pokoinpos
scp -i "keys/peer2/ssh-key-2026-05-15.key" \
  /tmp/pokontact-service.tgz \
  ubuntu@130.162.242.213:/tmp/pokontact-service.tgz

ssh -i "keys/peer2/ssh-key-2026-05-15.key" ubuntu@130.162.242.213 '
  set -e
  sudo mkdir -p /opt/pokontact
  sudo tar -xzf /tmp/pokontact-service.tgz -C /opt
  sudo chown -R ubuntu:ubuntu /opt/pokontact
  if [ ! -f /opt/pokontact/.env ]; then
    token=$(openssl rand -hex 32)
    printf "POKONTACT_SERVICE_TOKEN=%s\nPOKONTACT_AI_BASE_URL=http://pokontact-ollama:11434/v1\nPOKONTACT_AI_API_KEY=ollama-local\nPOKONTACT_MODEL_PROVIDER=local-ollama\nPOKONTACT_MODEL=qwen2.5:0.5b\nPOKONTACT_MAX_TOKENS=96\nPOKONTACT_TEMPERATURE=0.7\nPOKONTACT_OLLAMA_KEEP_ALIVE=30m\nPOKONTACT_OLLAMA_THREADS=2\nPOKONTACT_WARM_INTERVAL_MS=240000\n" "$token" |
      sudo tee /opt/pokontact/.env >/dev/null
    sudo chmod 600 /opt/pokontact/.env
  fi
  cd /opt/pokontact
  sudo docker build -t pokontact-service:local .
  sudo docker rm -f pokontact-service >/dev/null 2>&1 || true
  sudo docker run -d \
    --name pokontact-service \
    --restart unless-stopped \
    --env-file /opt/pokontact/.env \
    -p 8787:8787 \
    pokontact-service:local
  curl -fsS http://127.0.0.1:8787/health
'
```

Run local Ollama on the same Docker network:

```bash
ssh -i "keys/peer2/ssh-key-2026-05-15.key" ubuntu@130.162.242.213 '
  set -e
  sudo docker network create pokontact-net >/dev/null 2>&1 || true
  sudo docker volume create pokontact-ollama >/dev/null
  sudo docker rm -f pokontact-ollama pokontact-service >/dev/null 2>&1 || true
  sudo docker run -d \
    --name pokontact-ollama \
    --network pokontact-net \
    --restart unless-stopped \
    -v pokontact-ollama:/root/.ollama \
    -p 127.0.0.1:11434:11434 \
    ollama/ollama:latest
  sudo docker exec pokontact-ollama ollama pull qwen2.5:0.5b
'
```

Then start/recreate Pokontact on that network:

```bash
ssh -i "keys/peer2/ssh-key-2026-05-15.key" ubuntu@130.162.242.213 '
  cd /opt/pokontact
  sudo docker rm -f pokontact-service
  sudo docker run -d \
    --name pokontact-service \
    --network pokontact-net \
    --restart unless-stopped \
    --env-file /opt/pokontact/.env \
    -p 8787:8787 \
    pokontact-service:local
  curl -fsS http://127.0.0.1:8787/health
'
```

Use `docker rm` + `docker run`, not only `docker restart`, after changing
`/opt/pokontact/.env`; Docker does not reload `--env-file` values on restart.

Successful `/health` must include:

```json
{"ai":true,"provider":"local-ollama"}
```

If local VM health works but this command from the local machine times out:

```bash
curl -fsS --connect-timeout 8 http://130.162.242.213:8787/health
```

the service is running, but Oracle Cloud networking is not exposing TCP `8787`.
Open that port in the Oracle VCN/security list, or put the service behind an
HTTPS reverse proxy/tunnel and use that URL as `POKONTACT_SERVICE_URL`.

For the current peer2 VM, the OCI CLI path is:

```bash
TENANCY_OCID=$(awk -F= '/^tenancy=/{print $2}' "$HOME/.oci/config")
PEER2_INSTANCE=$(oci compute instance list \
  --compartment-id "$TENANCY_OCID" \
  --all \
  --query "data[?\"display-name\"=='pokoin-vm2'].id | [0]" \
  --raw-output)
VNIC_ID=$(oci compute vnic-attachment list \
  --compartment-id "$TENANCY_OCID" \
  --instance-id "$PEER2_INSTANCE" \
  --all \
  --query "data[0].\"vnic-id\"" \
  --raw-output)
SUBNET_ID=$(oci network vnic get \
  --vnic-id "$VNIC_ID" \
  --query "data.\"subnet-id\"" \
  --raw-output)
SEC_LIST=$(oci network subnet get \
  --subnet-id "$SUBNET_ID" \
  --query "data.\"security-list-ids\"[0]" \
  --raw-output)
```

Then add a TCP `8787` ingress rule to `$SEC_LIST` while preserving existing
rules. After it is open, verify:

```bash
curl -fsS --connect-timeout 12 http://130.162.242.213:8787/health
```

Set Vercel production env after the service URL and token are known. The URL can
be omitted if peer2 remains exposed at the documented public endpoint, but set it
explicitly if peer2 moves behind HTTPS, a reverse proxy, or a tunnel:

```bash
printf '%s' 'http://130.162.242.213:8787' |
  vercel env add POKONTACT_SERVICE_URL production --force
printf '%s' '<token from /opt/pokontact/.env>' |
  vercel env add POKONTACT_SERVICE_TOKEN production --force
printf '%s' '12000' |
  vercel env add POKONTACT_SERVICE_TIMEOUT_MS production --force
```

## Personality Rules

- Pokontact should be cheerful, funny, and emoji-rich.
- Pokontact explains Pokoin simply:
  - marketplace for cards
  - PokoinPoS chain and native PKN
  - wallet, Scan, Swap, validators, MetaMask basics
- Crypto explanations must be beginner-friendly and avoid jargon unless it is
  immediately explained.
- Card suggestions must be by Pokontact's cute/personal collector taste only.
  Never present card suggestions as financial advice, price predictions, or
  investment recommendations.
- Card suggestion links should resolve to direct card detail routes when Oracle
  marketplace candidates can match the suggested name/collector number. Use the
  stored canonical path from `marketplace_card_urls` or
  `/api/marketplace-card-url`; do not rebuild the public-number slug in assistant
  code. Only fall back to `/marketplace/search?q=<query>` when no card candidate
  can be resolved.
- Pokontact can be playful, but should not mock users or make risky promises about
  money, security, or support timelines.

## Knowledge Base

The peer2 service must not rely on a tiny local model's raw memory for project
facts. Keep `services/pokontact/knowledge.md` as the compact, curated source of
truth for Pokontact.

The knowledge base now includes a `Site Navigation And Actions For Pokontact`
section. Treat it as the chatbot-facing site manual: it documents public routes,
mobile menu entries, page-specific guidance, and the action payloads Pokontact can
trigger. Keep it written for the assistant, not for developers.

When adding or changing user-facing routes/actions, update that section so Poko
can guide users without inventing navigation. In particular, update it when:

- A route is added, renamed, protected by auth, or removed.
- The mobile side menu changes.
- A frontend assistant action type is added beyond `navigate`.
- The Vercel gateway adds a deterministic tool such as marketplace lookup,
  card suggestion resolution, search, cart, wallet, or support forwarding.
- A screen gains important user actions Poko should explain.

Update `knowledge.md` when any of these change:

- Pokoin project positioning, public routes, wallet behavior, or Scan.
- PokoinPoS network metadata, RPC URLs, chain ID, validators, or bootstrap rules.
- Marketplace architecture, Oracle-backed APIs, search behavior, listings, carts,
  or analytics.
- PokoinSwap, PKN, wPKN, BNB Chain contract/pair/reserve details.
- Native NFT APIs, minting workflow, metadata model, or card NFT direction.
- Assistant role, support/bug escalation language, privacy rules, or forbidden
  requests.

Keep the knowledge base compact. It should contain high-signal facts and answer
rules, not whole documentation pages. The service injects relevant sections into
the local model prompt based on message keywords, while known project/card/crypto
support intents should still use curated instant replies.

Recommended source docs:

- `README.md`
- `docs/common-user-actions.md`
- `docs/native-nfts.md`
- `oracle-postgres/README.md`
- `/Users/giuseppe/pokoinpos/docs/public-network.md`
- `/Users/giuseppe/pokoinpos/docs/wpkn-bnb-pancakeswap.md`
- `/Users/giuseppe/pokoinpos/docs/pokoin-swap.md`

## Inquiry And Bug Escalation

When a message looks like a bug report, support request, or project inquiry:

- Forward it to `POKOIN_ASSISTANT_EMAIL` / `pokoinpos@gmail.com`.
- Send forwarded bug/support emails from `POKOIN_ASSISTANT_FROM`, defaulting to
  `Poko <poko@pokoin.com>`. Make sure `poko@pokoin.com` is configured/verified
  with the active email provider before relying on production delivery.
- Include:
  - username when known
  - Firebase UID when known
  - email when known
  - current page URL
  - latest user message
  - bounded chat record/transcript
  - raw user message
  - timestamp
- If email forwarding fails because `RESEND_API_KEY` or email configuration is
  missing, Pokontact should not tell the user to email manually. It should ask
  the user for additional details and explain that forwarding will be retried
  when available.
- Pokontact should tell the user: "I am forwarding your issue to the
  development team. They will respond to you directly. In the meantime, please
  give me any additional information..."
- Do not forward unrelated casual messages unless they look like support,
  inquiry, or bug intent.

When forwarding through Vercel, include the full bounded chat record received
from the widget, not only the latest user message.

## Security And Privacy

- Never expose Firebase tokens, API keys, private keys, service role keys, or
  wallet private keys in responses or emails.
- The widget may send the Firebase ID token only in the `Authorization` header.
- The server must verify the token before trusting username/email/UID.
- Bound and sanitize user text before email rendering.
- Keep forwarded messages admin-only. Do not create public forum posts or public
  issue pages from assistant messages.

## Widget Performance

The floating widget is mounted globally on top of every route, including heavy
marketplace/card pages. Opening the chat must not trigger page-wide jank or a
frozen frame.

Rules:

- Keep open/close cheap. Do not wrap the full chat panel in `AnimatedSwitcher`,
  `Hero`, or large scale/opacity transitions.
- Do not use the same `Hero` tag in the closed bubble and open panel while an
  animated transition can keep both widgets alive.
- Keep the closed bubble visually simple: icon + unread badge only. Avoid large
  gradients, oversized shadows, blur effects, or network images.
- Put the assistant shell behind a `RepaintBoundary` so chat updates do not force
  expensive repaint work in the marketplace beneath it.
- Do not call `/api/pokoin-assistant`, Firebase, marketplace providers, or other
  network/data loaders when the panel merely opens. Only send requests after the
  user submits a message or taps a prompt.
- After changing the widget, test opening/closing it on heavy pages such as
  `/marketplace` and direct card pages. The page should remain scrollable and
  interactive immediately after opening the panel.

## Verification

After changing Pokontact:

```bash
node --check api/pokoin-assistant.js
node --check services/pokontact/server.js
node --test api/pokoin-assistant.test.js
dart format lib/widgets/pokoin_assistant.dart test/pokoin_assistant_link_test.dart
flutter test test/pokoin_assistant_link_test.dart
flutter analyze lib/widgets/pokoin_assistant.dart test/pokoin_assistant_link_test.dart
```

Also verify:

- `vercel.json` contains the `/api/pokoin-assistant` rewrite.
- `vercel.json`, `server/api-route-manifest.js`, and `deploy-pokoin-web.sh`
  contain every debug/session/current-page API touched by the change.
- `deploy-pokoin-web.sh` leaves the built endpoint loadable:
  ```bash
  node -e "require('./build/web/api/pokoin-assistant.js')"
  ```
- `api/pokoin-checkout-deploy-layout.test.js` covers route-manifest/deploy
  packaging for `/api/pokoin-assistant`, `/api/marketplace-card-url`, and any
  newly added user-current-page/session page endpoint.
- `.env.example` documents `POKOIN_ASSISTANT_EMAIL`, `POKOIN_ASSISTANT_FROM`,
  `POKONTACT_SERVICE_URL`, and `POKONTACT_SERVICE_TOKEN`.
- The assistant bubble does not block core mobile navigation or checkout actions.
- Peer2 service health responds:
  ```bash
  curl -fsS <peer2-service-url>/health
  ```
- Vercel gateway can reach peer2 service and returns `assistant: "Pokontact"`.
- Bug/inquiry test messages return `forwarded: true` when email env is configured.
- Non-support messages, like cute card suggestions, do not trigger forwarding.

## Deployment

Pokontact has two deployment layers:

1. Deploy/update the peer2 service on Oracle Cloud.
2. Deploy the web/API gateway through the standard web workflow:

```bash
./deploy-pokoin-web.sh
```

Do not assume updating this workflow makes Pokontact live. The Oracle peer2
service must be running and healthy, and the Flutter build/API files must be
deployed.
