# Agent instructions (Pokoin / CardVault)

## Mobile app working branch (user workflow)

- `AppMobile` is the user-requested working branch for this mobile app checkout.
- It replaces `codex/search-images-mobile-filters`; keep local work tracking
  `origin/AppMobile` after the GitHub branch rename.
- Do not merge into `main`, force-push, publish releases or deploy production
  unless the user explicitly requests it.
- Keep APKs, generated caches and machine-local Android SDK configuration out
  of source commits. Continue the local APK and Obsidian workflows below.

## Local Android emulator APK (user workflow)

- After changes affecting the Flutter app, Android configuration, dependencies or
  bundled assets, rebuild the debug emulator APK before handing off the work.
- On this Windows checkout, run `./scripts/build-emulator-apk.ps1` from
  `pokemon_card_vault/`. It builds for `android-x64`, checks the packaged Flutter
  ABI and copies the APK to
  `C:\Users\raffa\ApkProjects\pokoin-debug-emulator-x86_64\pokoin-debug-emulator-x86_64.apk`.
- The script backs up the previous APK under `build/emulator-apk-backups/`.
  Only replace the APK; do not edit the APK Analyzer's extracted `lib/`, `smali/`,
  manifest or Android Studio project files in that destination directory.
- Request execution/write approval when the sandbox requires it. If the build or
  copy fails, report the failure and do not claim the destination is updated.
- This is a local debug artifact, not a release or production deployment. It
  does not install the APK on the emulator unless the user asks for installation.

## Local Obsidian updates (user workflow)

- Update the user's local Obsidian documentation after every project change set,
  before handing off. The existing vault is
  `C:\Users\raffa\Documents\Obsidian\Pokoin Collaborator\Pokoin`.
- Read the current hub and relevant notes, update existing claims rather than
  duplicating them, and keep the file-map MOC and dated Events linked.
- Preserve existing notes, back up overwritten files, and request write approval
  when required. Report if an update remains pending; staged notes alone do not
  count as updating the vault.
- Follow `../memory/obsidian-documentation.md` for note structure. This local
  workflow does not synchronize or replace the canonical Pi vault.

## Production deploy

- **Always** use `./deploy-pokoin-web.sh` for `pokoin.com` production.
- **Never** run bare `vercel --prod` from the repo root; it deploys API-only and
  breaks `/`, `/marketplace`, and all Flutter routes with Vercel `404 NOT_FOUND`.

## Incidents

If the site or `/marketplace` shows Vercel `404: NOT_FOUND`, follow:

`workflows/pokoin-vercel-404-recovery-workflow.md`

## Marketplace / cards

`workflows/card-market-page-workflow.md`

Our marketplace id is **our id** (`docs/marketplace-public-ids.md`):
`marketplace_cards.card_id` = old CardTrader blueprint × 2. We do not use `ct_id`
in URLs, API, Flutter, or image URLs. Never × 2 a catalog `card.id` or a Fast
Milo/TCGplayer id. pokoin-marketplace has 018 applied. Codevira D00000B.

## Multi-game CardTrader dump (One Piece / Riftbound)

Qwen: follow these two files. Do not print secrets.

- `workflows/cardtrader-multigame-marketplaces-workflow.md` (importer flags)
- `/home/nez/secrets/docs/CARDTRADER_MULTIGAME_DUMP.md` (hosts, WARP netns, 403)

Isolated DBs only (`pokoin_one_piece`, `pokoin_riftbound`). Never write into
Pokemon `public.cardtrader_pokemon_blueprints`. Frankfurt image hosts are
Cloudflare-403; use netns `igvpn` (nezopt) or `ctvpn` (peer1 WARP). Full
multithread (`--image-concurrency` 12–16, both games in parallel).

## Crypto swap / bridge

`workflows/swap_bridge-workflow.md`

`workflows/crypto-pkn-purchase-workflow.md`

## Codex in Cursor (local dev)

Use ChatGPT Plus/Pro Codex models inside Cursor via the local proxy:

`workflows/codex-cursor-proxy-workflow.md`

Quick start: `npm run codex:cursor-proxy` (Bun + `codex` auth). Auto-start at login: `npm run codex:cursor-proxy:install-launchagent`. Source: `github:wellbritto98/codex-cursor-proxy`.
