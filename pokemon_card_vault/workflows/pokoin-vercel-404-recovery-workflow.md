# Pokoin Vercel 404 Recovery Workflow

Use this when `pokoin.com`, `/marketplace`, or other Flutter routes return
Vercel `404: NOT_FOUND` with `x-vercel-error: NOT_FOUND`.

## Root cause (most common)

A bare `vercel --prod` from the repo root deploys **API/serverless only** and
does **not** include the Flutter `build/web` static app. Production then 404s on
`/`, `/marketplace`, `/wallet`, etc.

The correct production path is always:

```bash
cd /Users/giuseppe/cardvault/pokemon_card_vault
./deploy-pokoin-web.sh
```

Never use `vercel --prod` alone for the main Pokoin web project unless you have
already run `flutter build web` and packaged `build/web` exactly as the script
does.

## Fast triage (30 seconds)

```bash
# 1) Confirm symptom
curl -sI https://pokoin.com/ | rg 'HTTP|x-vercel-error'
curl -sI https://pokoin.com/marketplace | rg 'HTTP|x-vercel-error'

# 2) List recent production deploys (note Duration)
vercel ls web --prod | head -12

# 3) Find last good deployment (expect HTTP 200 on / and /marketplace)
GOOD=https://web-ina33so5y-giuseppevitolo17s-projects.vercel.app
curl -sI "$GOOD/" | head -3
curl -sI "$GOOD/marketplace" | head -3
```

Broken deploys often show **Duration ~3–5s** (API-only). Good deploys show **~2m+**
and return `200` for `/` and `/marketplace`.

## Emergency rollback (restore traffic in ~1 minute)

```bash
GOOD_DEPLOYMENT_URL=https://web-ina33so5y-giuseppevitolo17s-projects.vercel.app

for domain in \
  pokoin.com \
  www.pokoin.com \
  wallet.pokoin.com \
  forum.pokoin.com \
  cards.pokoin.com \
  cardcaveau.pokoin.com \
  cardvault.pokoin.com \
  explorer.pokoin.com
do
  vercel alias set "$GOOD_DEPLOYMENT_URL" "$domain"
done

curl -sI https://pokoin.com/marketplace | rg 'HTTP|x-vercel-error'
```

Replace `GOOD_DEPLOYMENT_URL` with the newest deployment that returns `200`.

## Proper fix (ship latest code)

From `pokemon_card_vault`:

```bash
flutter analyze
./deploy-pokoin-web.sh
```

`deploy-pokoin-web.sh` must:

1. `flutter build web --release --pwa-strategy=none`
2. Copy `api/*.js` into `build/web/api` and helpers into `build/web/server`
3. Copy root `vercel.json` into `build/web`
4. `vercel build --prod` + `vercel deploy --prebuilt --prod` from `build/web`
5. Run `scripts/verify-production-aliases.js --set-aliases`

## Post-deploy verification

```bash
python3 - <<'PY'
import urllib.request
urls = [
  'https://pokoin.com/',
  'https://pokoin.com/marketplace',
  'https://pokoin.com/wallet',
  'https://pokoin.com/scan',
  'https://pokoin.com/api/marketplace-home',
]
for url in urls:
    req = urllib.request.Request(url, headers={'User-Agent': 'PokoinDeployCheck/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            print(res.status, url, res.headers.get('x-vercel-error', ''))
    except Exception as exc:
        print('ERR', url, exc)
PY
```

Expect:

- `/`, `/marketplace`, `/wallet`, `/scan` → **200** (HTML)
- `/api/marketplace-home` → **200** JSON (or auth-gated 4xx, not Vercel NOT_FOUND)

## Codex CLI usage

Codex is installed globally:

```bash
npm i -g @openai/codex
codex --version
```

Run from repo root with this workflow in context:

```bash
cd /Users/giuseppe/cardvault/pokemon_card_vault
codex "Read workflows/pokoin-vercel-404-recovery-workflow.md and workflows/card-market-page-workflow.md. pokoin.com/marketplace returns Vercel 404 NOT_FOUND after vercel --prod. Roll back aliases if needed, then run ./deploy-pokoin-web.sh and verify /marketplace returns 200."
```

## Related docs

- `workflows/card-market-page-workflow.md` — deploy + alias promotion checklist
- `deploy-pokoin-web.sh` — canonical production deploy script
- `vercel.json` — SPA fallback `/(.*) -> /index.html` (must ship inside `build/web`)

## Prevention

- User says **deploy** → run `./deploy-pokoin-web.sh`, not `vercel --prod` from root.
- After any manual Vercel deploy, check `curl -sI https://pokoin.com/` before closing the task.
- If Duration in `vercel ls` is only a few seconds, assume API-only broken deploy.
