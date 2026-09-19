# Pokoin / cardvault — current state

## 2026-09-01 — test.pokoin.com sanitize review + edge fringe

- Review page: [test.pokoin.com/sanitize](https://test.pokoin.com/sanitize) (`pokoin-web/market/public/review/`). Doc: `docs/test-pokoin-sanitize-review.md`. Regenerate: `node scripts/generate-sanitize-review-assets.js`.
- Studio crop edge fringe: opaque matte ears treated as clear surround; corner light specks **23 → 0** on `user-studio-precise.jpg`. 44/44 sanitizer tests.
- Charizard leftover precise deskew: **+1.57°**, remaining **−0.01°**. Do not PutObject `?v=ct3` until Giuseppe checks review page.

## 2026-09-01 — Gold leftover deskew: skip matte, four-side + min-area (not uploaded)

- Live Charizard 713832 leftover `356916_` (737×1021 on dark matte) read **0°** because `collectOuterSilhouette` treated marketplace matte as the card edge. The gold face was **−1.70°**.
- Fix: skip matte + gray rotate-AA; Theil–Sen on all four sides; min-area refine. AABB-clipped gold falls back to name/attack baselines (must agree, |tilt| ≥ 0.85°) so we do not chase foil art. Damp 0.92, stop at 0.12°.
- Leftover locally: applied **+1.57°**, remaining **−0.06°**. 713×1000 square crop stayed 0° (silhouette already AABB). 42/42 sanitizer tests. Preview `/tmp/sanitize-deskew-preview/cdn-leftover-precise.jpg`. Next encode `?v=ct3` after Giuseppe checks. Do not full-catalog `--apply`.

## 2026-09-01 — Sanitize pipeline: deskew inner rectangle, then era millimetres (D00000S)

- Order is locked: (1) rotate so the inner printed rectangle is upright (left/right yellow→face Theil–Sen, not the name-bar / evo-box); (2) then measure the outer rim and rebuild clipped yellow/silver to era mm, or die-cut only.
- Gold HR / foil-to-edge: align the card silhouette against studio paper (do not chase the illustration), then die-cut only. FA / IR / SIR filenames skip deskew. Side `atan(dx/dy)` is negated because image y grows down.
- 40/40 sanitizer tests. Charizard leftover `356916_` not re-uploaded this pass (still `?v=ct2` until Giuseppe checks; next encode `?v=ct3`). Do not full-catalog `--apply`.

## 2026-09-01 — Mega Charizard X ex 713832 live CardTrader leftover `?v=ct1`

- Public **713832**, `ct_id` **356916**, leftover `356916_mega-charizard-x-ex.jpg`. Live page had been serving `89229_` (pokemontcg gold flatten). Catalog URLs now `https://cdn.pokoin.com/356916_mega-charizard-x-ex.jpg?v=ct1`; API rewrites to `/card-images/713832_…?v=ct1`. Worker maps public → leftover.
- Gold HR die-cut only: punch white ears, 8× round onto `#0b0b0f`, no yellow weld. Originals backup already existed. Hard-refresh.

## 2026-09-01 — Milotic paper punch + Swampert tilt-then-rebuild (not uploaded)

- Milotic League **257448** leftover `128724_`: border-connected punch of studio paper (luma ≥ 220, chroma ≤ 22, not yellow). Stops at washed chroma-50 yellow. Crop to the card, 8× round, **no second rim**. 10 799 pixels punched; 333×450 → 324×444.
- Swampert theme-deck **257432** leftover `128716_`: inner-join −4.50° → rotate 0.7× (applied +3.15°) → **0.12°**. Then rebuild clipped left yellow to era **2.22 mm** sides (target 2.33 mm). Rare holo leftover `128758_` / public **257516** is a different file — do not mix.
- 35/35 sanitizer tests. Previews: `sanitize-five-preview/revised/*.preview.jpg`. Catalog not rewritten.

## 2026-09-01 — Milotic #3 punch + Swampert tilt (not uploaded)

- Milotic League 257448 leftover `128724_`: test 3 is the winner. Punch was eating chroma-50 washed yellow. Now stop at `isYellowHue`; cream C20 still punches. Rim starts ~1 px earlier than the old #3.
- Swampert screenshot tests leaned because 1–4 never deskewed, and test 5 rotated the inner-join −4.5° in one shot (overshoot to +1.7° the other way). Side `atan(dx/dy)` is the negative of inner `atan(dy/dx)` on a rectangle. Use the smaller angle so the yellow silhouette does not flip. The **catalog leftover** `128758_` is square-cut / upright — that is the file we would encode, not the screenshot.
- 34/34 sanitizer tests. Previews: `sanitize-five-preview/revised/*.preview.jpg` (JFIF). Do not commit that folder. Catalog not rewritten.

## 2026-09-01 — Studio white surround (Milotic League, not uploaded)

- Hard class: complete printed rim + inner square on a white studio JPEG (Milotic League 257448 leftover `128724_`). Yellow studio-diecut used to weld washed outline.
- Pipeline now: punch studio white from the edges (stop at the rim), 8× round onto `#0b0b0f`, keep the printed yellow. No flood-fill, no second rim. 33/33 tests. Catalog not rewritten.
- Do not full-catalog `--apply`.

## 2026-09-01 — Gold HR texture back to CardTrader (`?v=ct1`)

- Mega Lucario ex 188/132 public `703382` leftover `351691_mega-lucario-ex.jpg` and Mega Gardevoir ex 187/132 public `703380` leftover `351690_mega-gardevoir-ex.jpg`.
- pokemontcg / Limitless gold renders are flat silhouettes (white flatten, square corners). CT photos keep foil grain (art-window std ~25–30 vs ~10–16). CT sizes: Lucario **330×460**, Gardevoir **500×700** — that is all CT ships.
- Sanitizer: gold-foil is diecut-only + 8× round onto dark matte `#0b0b0f`, never yellow weld, never white flatten. D00000R supersedes D00000L source rule. Live `?v=ct1`. Hard-refresh.
- Do not full-catalog `--apply`.

## 2026-09-01 — Die-cut rounding 8× AA + Mega Lopunny pink (`?v=r8`)

- Silver/FA `diecut-only` used a 1× binary round (`applyHardRoundedRectAlpha`) — ~16 px stairs on a 5% radius. Sanitizer now fills round caps then clips with an **8× coverage sample** on the four corners (partial alpha → matte). Yellow rebuild-frame no longer allocates a 4× full raster + lanczos.
- Mega Lopunny ex Phantasmal Flames 084/094 public `713740`, leftover `356870_mega-lopunny-ex.jpg`: pink rectangle left of STAGE 1 was **in the live JPEG** `(235,95,121)` at ~`(24,36)`. Official `me2/84_hires.png` is silver `(222,223,222)` there. Sanitizer does not invent that magenta. Re-encoded from official PNG, `?v=r8`. Hard-refresh.
- Recipe applies to every future encode. Do not full-catalog `--apply` until Giuseppe says go (Prize Pack `?v=we1` still has the old 1× round).

## 2026-09-01 — Prize Pack white-ear studio photos (`?v=we1`)

- Example: Mega Abomasnow ex Play! Prize Pack public `782104`, leftover `391052_mega-abomasnow-ex.jpg`. Live corners were white `(255)` outside the silver rim (studio die-cut on white). Official `me1/36` is the Mega Evolution print, no Play! stamp — do not replace.
- Sanitizer `diecut-only` / `studio-diecut` (D00000G): punch white ears to matte `#0b0b0f`, no second rim. Prize Pack set on CDN: **392** white-ear JPEGs uploaded `?v=we1`, leftover key from the live URL, local copy written. Hard-refresh.
- Do not full-catalog `--apply`.

## 2026-09-01 — Suspicious grey-corner scan (`?v=fa2`)

- Local CDN mirror is `/home/nez/Projects/pokoin/PokoinTest/index/cdn_images` (exact leftover R2 keys). Catalog jobs read that tree; every R2 PutObject writes the same key there. Do not download catalog JPEGs from cdn.pokoin.com for scans.
- Scan: Tag Team / Full-Art / GX Ultra. 2190 candidates, 1221 leftover keys pulled from R2 into the local copy, 28 smeared, **16 confirmed Team Up** re-encoded from `sm9/{n}_hires.png`, leftover key from the live URL, `?v=fa2`. Local copies are clean. Ampharos FA public `259664` API `imageUrl` has `?v=fa2`.
- Gengar & Mimikyu GX 165/181 leftover `129834_…jpg` stayed `?v=fa1` (already clean). JP Tag All Stars / Miracle Twin / etc. smeared but unmapped — not rewritten from English hires.
- Evolving Skies / Fusion Strike alt arts looked grey on both live and official — skipped (`official-also-grey`).
- Do not `leftoverCdnObjectKey` an already-leftover key. Odd leftover names (`8115_`, `8116_`) stay as-is when that is the live URL. Do not full-catalog `--apply`.

## 2026-09-01 — Gengar & Mimikyu GX FA grey corners (`?v=fa1`)

- Team Up 165/181 public `259668`, leftover `129834_gengar-mimikyu-gx.jpg`. Live grey `(165)` at BL/TR was an old JPEG flatten, not the API hires. Re-encoded from `sm9/165_hires.png`. BL/TR now match official silver `(228)` / `(214)`. Hard-refresh.
- Do not run `leftoverCdnObjectKey` on an already-leftover `{ct_id}_` key (129834 is even and would halve to 64917).

## 2026-09-01 — POP Series 6 yellow edges (live `?v=br4`)

- Audit: `pokemon_card_vault/docs/card-border-edge-audit-2026-09-01.md`.
- Fixes in `scripts/lib/sanitize-card-image.js`: thickness walk is `belongsToPrintedRim` (not grass hue); pokemontcg alpha corners + thin yellow → `rebuild-frame`; AABB fill on sides; do not blit transparent PNG corners over the yellow pad; gold-foil skip if a thin printed rim exists (DP beige was 50% `isYellowHue`).
- POP Series 6 **25/25** re-uploaded `?v=br4`. Hard-refresh (immutable JPEG). Turtwig `248802` sides **26 px / 2.65 mm** (was 31/3.28 vs top 16/1.69). Gible inner join spread **1 px**. Lucario/Pikachu no longer diecut-only as fake gold foil.
- Output is still ~2.5–2.7 mm vs 2.33 spec because pad targets 0.78 R (corner pinch), not 22 px. Do not full-catalog `--apply`.

## 2026-09-01 — DP header yellow nicks (Gible / Bidoof)

- POP Series 6 Gible `248770` / Bidoof `248786` had yellow flecks in the silver name/HP inner corners after the thickness rebuild.
- Cause: `fillInsideDieCutEars` (and the 4× corner fan) treated light DP silver as punchable ears inside the 5% quarter-circle. Official `pop6/7` header at the same point is `(182,172,163)`.
- Fix: do not fill past measured T; `weldOnly` AABB on pad; skip light non-yellow interior. Live `?v=br2`. POP Series 6 25/25 uploaded. Hard-refresh (immutable JPEG cache).
- Untested expansions still wait.

## 2026-08-31 — tested expansions re-encoded (gold-foil sanitizer)

- Applied `--apply --force` only on sets we already checked: **Mega Evolution** 188, **White Flare** 173, **Stellar Crown** 175. Untested expansions/rarities not rewritten.
- Live checks: Lucario 188 / Gardevoir 187 mid-top `(252,220,77)` (foil highlight, not painted yellow). Lillie SIR and Hilda UR mid-top silver `(219,220,222)`, not yellow/orange. Dachsbun SIR 169/142 silver rim, no white AABB.
- Full catalog rewrite still waiting on Giuseppe.

## 2026-08-31 — gold HR not a yellow frame

- Mega Lucario ex 188/132 and Mega Gardevoir ex 187/132 are gold foil (~88% yellow). Sanitizer treated that as a Wizards yellow rim and welded `(252,220,76)` → `(255,211,0)`. Leftover keys omit `hyper-rare`.
- Fix: `isGoldFoilRaster` (≥40% yellow pixels) → die-cut only. Always encode from pokemontcg.io PNG, never live JPEG. Same family as Hilda orange / Lillie yellow-in-silver.
- Re-upload those two from `me1/188` and `me1/187` after the code fix.

## 2026-08-31 — pokemontcg JPEG catalog apply (done)

- Ran on **nezopt** (`scripts/import-pokemontcg-expansion-hires.js --apply`). **8,486** JPEGs in 25 min + **175** Stellar Crown retry (expansion-page 500 during the main pass). **8,661** uploaded. 122 skipped (already ≥1.2×). Forbidden Light JP not imported (English scans).
- `.env.local` `MARKETPLACE_DATABASE_URL` / name-search / Poko readonly host is **130.61.251.250** (was dead `92.5.23.133` / `141.147.62.244`).
- Live: Black Bolt Victini `/card-images/342603_victini.jpg`; Stellar Crown Bravery Charm `/card-images/299069_bravery-charm-…jpg`. Leftover `{ct_id}_` keys, `originals/{key}` backup, no projection refresh.
- Reports: `/tmp/pokemontcg-expansion-jpg/pokemontcg-expansion-jpg.json`, `/tmp/pokemontcg-expansion-jpg-stellar/`.

## 2026-08-31 — all expansions vs pokemontcg.io + Qwen

- Sampled **819** marketplace expansions (`GET /api/marketplace-expansion-page?limit=2000`), one card each vs `images.pokemontcg.io/{setId}/{number}_hires.png`.
- After Qwen: **67 download**, **17 keep**, **677 unmapped** (JP/movie/product), 38 no collector number, 20 errors. Report: `/tmp/pokemontcg-expansion-samples/expansion-sample-compare.json`.
- Biggest gaps are live **CardTrader 180×250 previews** (Black Bolt, Destined Rivals, White Flare, Journey Together, Prismatic Evolutions, Surging Sparks, Team Up) vs API 733×1024 — real missing full JPEGs, not a sample bug.
- Qwen3-VL 32B local (`qwen3-vl:32b-instruct` on 127.0.0.1:11434) judged close ratios only. Brilliant Stars 1.05× → download; Celestial Storm 1.04× and Fossil 0.97× → keep (tie). Helper, not source of truth.
- Script: `scripts/compare-expansion-samples.js` (`--qwen`, `--write` local JPEG only). Catalog R2 untouched.
- Expansion-page slugs with `&` 404; sampler falls back to `expansionName`.

## 2026-08-31 — card border rebuild (not a full R2 pass yet)

- Spec: `pokemon_card_vault/docs/card-border-rebuild-pass.md`. Classifier in `sanitize-card-image.js`.
- **Inner yellow/blue join is a straight AABB** (`paintStraightFrame`): one measured T per side, no scanline walk into gold. Greedy walk caused Gyarados left step (22→34 px) and jagged top.
- Wizards/Neo printed yellow (pokemontcg.io neo3/65): **21–22 px / 2.33 mm sides**, bottom ~2.4 mm. Cap T at 7% of short side so the gold art window cannot win.
- **White-ear studio shots are die-cut only, never padded.** When the CT scan is messy, use **images.pokemontcg.io** (`neo3/65_hires.png` for Shining Gyarados) as the visual ground truth — do not invent a second rim. Era-complete square-cuts (T ≥ 85% of target) also pad 0.
- Square-cut cropped yellow (Gulpin, EX Charizard 100/97): pad outside until T′ ≥ 0.78 R, 4× die-cut, JPEG q100 4:4:4. D00000E still holds.
- Full art / IR / SIR / hyper-rare / rainbow / shiny: **die-cut only, never invent yellow**. `full-v4` is CT resolution, not Full Art.
- Over-number (`160/142`) is not enough to skip: EX secret 100/97 is still yellow.
- Local pull of Wizards-era **pokemontcg.io hires → JPEG** when that scan is larger than ours: `scripts/import-pokemontcg-wizards-hires.js` (q100 4:4:4). Default local `/tmp`; catalog R2 untouched until go.

## 2026-08-31 — public CDN prefixes (D00000B)

- Image **URLs** use our id (`598052_…`). Leftover R2 **keys** stay `{ct_id}_`.
- Worker tries the requested key, then even-prefix `/ 2`. Do not rename R2.
- API `rewriteCdnPokoinPrefix` and Flutter `rewriteCdnPrefixToOurId` emit our id.
- Local digest: `/home/nez/pokoincdn/cdn_images_digest/2026-08-30` (symlink at `Projects/artifacts/cdn_images_digest`).
- Deploy the CDN Worker before the Oracle API, or public-id URLs 404 until the Worker is live.
- Sanitizer exists for corners, but lossless PNG is not the catalog format (D00000E). Live JPEG/WebP stay. `originals/{key}` is the unsanitized backup. Do not write sibling `.png`.


## 2026-08-30 — shutdown hook removed; homepage MEGA arrivals + Flutter web

- Removed Mac `stop` hook that called `shutdown -h now`. Honcho hook remains.
- Homepage `newArrivalIds` now keep Mega Evolution first (merge before the 140-card cap). Live: Mega Lucario ex `703382` with leftover R2 key `/card-images/351691_mega-lucario-ex.jpg` (public URL prefix `703382_`).
- Flutter web redeployed (`USE_ORACLE_API=1`) with `preferDetailMarketplaceImage` and Hive `snapshot_v3_cdn_hero`.
- Remaining CardTrader CDN ingest running on `pokoin-oracle-api` (~25k rows; check `/tmp/oracle-image-import-remaining.log`).

## 2026-08-30 — MEGA-era digest images on CDN

- Downloaded CardTrader full+preview for Mega Evolution, Phantasmal Flames, Inferno X, Mega Brave, Mega Symphonia, MEGA Dream ex singles (776). Uploaded to R2 `cardvault-images`; local copy `artifacts/cdn_images_digest/2026-08-30` (1552 files).
- Importer derives full art from `/preview_` URLs. Do not treat 180px previews as heroes.
- Those six sets are 100% `cdn.pokoin.com` for singles. Catalog still has ~24841 CardTrader URLs on older sets.
- Script: `scripts/import-oracle-cardtrader-images.js` (`ORACLE_IMAGE_EXPANSION_IDS`, `ORACLE_IMAGE_LOCAL_DIR`). Doc: `pokemon_card_vault/docs/marketplace-card-image-pipeline.md`.
- Do not run full projection refresh.

## 2026-08-30 — React page BFFs (home/search/card/expansion)

- New public APIs for the Next.js cutover (no Vercel serverless):
  - `GET /api/marketplace-card-page?cardId=`
  - `GET /api/marketplace-search-page?query=`
  - `GET /api/marketplace-expansion-page?expansionName=`
  - `GET /api/marketplace-home?recentCardIds=`
- Docs: `pokemon_card_vault/docs/react-page-apis.md` + `GET /api/__contract` version `2026-08-30`.
- React must use `gridImageUrl` / `heroImageUrl` (full JPEG). Do not paint `/previews/` as heroes.
- Flutter stays Android/iOS. Local tests mock the composed handlers (no Postgres).
- Hosted route count is 82.

## 2026-08-29 — marketplace nav images + new cards

- Flutter web: browser <img> for card art (`WebHtmlElementStrategy.prefer`); Hero disabled on web so CanvasKit does not decode progressive JPEG during flight.
- Homepage API adds `sections.newArrivalIds` (newest singles with images). Live 12 Thunderclap Spark ids.
- Deployed `marketplace-home.js` + `_marketplace_row.js` to pokoin-oracle-api; pokoin.com Flutter web aliased.


## 2026-08-29 — React / JS API contract

- Canonical docs: `pokemon_card_vault/docs/react-api-architecture.md` + `docs/react-api-contract.json`.
- Live: `GET https://api.pokoin.com/api/__contract` (after Oracle API deploy of `_client_contract.js` + server patch).
- Public web → Next.js/React; Flutter stays native. No Vercel serverless. IDs = public card_id (CT×2); CDN keys stay `ct_id_`. API owns `isMarketAvailable` / image URLs.
- BFF still missing: `GET /api/marketplace-card-page`.



## 2026-08-29 — website assistant → Poko

- Canned “I don’t know the answer yet…” is `generalReply()` in `api/pokoin-assistant.js` when the Poko fetch fails (old default was dead peer2 `130.162.242.213:8787`).
- Live: `POKONTACT_SERVICE_URL=http://10.0.0.170:8789/api/poko`, token = Hermes `POKO_API_TOKEN` (docs `Hermes/docs/poko-handoff.md`). Aliases: `HERMES_POKO_API_TOKEN`, `POKO_API_TOKEN`.
- pokoin.com already rewrites `/api/pokoin-assistant` to api.pokoin.com (via Caddy). `serviceDelivery.source` is `poko-peer1`.
- Flutter widget timeout was 18s; Poko/Gemini often ~20–26s. Source now 60s; production JS bundle still 18s until web deploy.

## 2026-08-29 — exact marketplace image URL log

- Live dump: `GET https://api.pokoin.com/api/marketplace-image-log?limit=40`
- `source=marketplace-home` (and cards/versions) = URLs the API served (`prefixKind: ct_id` is correct).
- `source=cdn-worker` = exact R2 404 the browser requested. Doubled public-id prefixes 404.
- Flutter `errorWidget` beacons need a web deploy; CDN 404s log without it.

## 2026-08-29 — card detail image pipeline

- Black detail art was API/DB stall + versions seq scan, not missing R2.
- Do not run `refresh_marketplace_oracle_projections()` on live pokoin-marketplace during traffic.
- Versions lookup: search_candidates (card_id / ct_id) then `marketplace_card_versions` PK.
- Doc: `pokemon_card_vault/docs/marketplace-card-image-pipeline.md`.


## 2026-08-29 — marketplace images / recently-seen / event pool

- Our id is `card_id` (old CardTrader blueprint × 2). We do not use `ct_id` in URLs, API, Flutter, or image URLs.
- Leftover R2 object names may still start with the old blueprint number; that is storage, not an id we expose.
- `marketplace-event` no longer runs `refresh_marketplace_hot_blueprints()` on the click path; insert resolves `card_id` or `ct_id`. Pool default 4.
- Search/home click seeds Recently seen immediately (`rememberNow` + `cacheCards`). Recently seen keeps unavailable viewed cards. Flutter web still needs a Vercel deploy for that UI.
- Joins use `ct_id` / `pokoin_card_id`, not `blueprint_id * 2` (that seq-scanned the listing cache and exhausted the pool).


Last updated: 2026-05-28

## Active focus

- Pokoin marketplace / CardVault monorepo under `cardvault/`
- Primary app tree: `pokemon_card_vault/`
- Production API (**2026-09-18**): `https://api.pokoin.com` on **pi-home** (not peer3). Oracle `pokoin-marketplace` is dump Postgres only.
- Production web: `https://pokoin.com`
- Prisma is now initialized in `pokemon_card_vault/` as a secondary Oracle
  Postgres access layer. It introspects the existing `pokoin_marketplace`
  schema from `MARKETPLACE_DATABASE_URL`; SQL under
  `pokemon_card_vault/oracle-postgres/schema/` remains canonical for DDL.
- English marketplace autocomplete/searchbar is live on Meilisearch in
  production. `api.pokoin.com` runs `MARKETPLACE_SEARCH_ENGINE=meili` for
  `search_language=en`; non-English remains on the legacy Oracle/Supabase path.
  The public `pokoin.com/api/*` production rewrite points to `api.pokoin.com`.

## Memory stack (Cursor)

| Layer | Role |
|-------|------|
| Honcho (`pokoin-cursor` workspace) | Cross-session chat memory via MCP `honcho-pokoin` |
| Codevira | Structured decisions, roadmap, conventions |
| This `memory/` folder | Human-readable backup |

Hermes/Flareon do **not** store full Pokoin code in `hermes-peer1`. Flareon gets a **short summary** via `memory/flareon-handoff.md` (synced to peer1).

## Deploy reminders

Updated **2026-09-18**: public api.pokoin.com / cdn.pokoin.com run on **pi-home**
(Raspberry Pi, Cloudflare tunnel). **peer3 (141.147.62.244) is dead** — do not
deploy API there. Oracle pokoin-marketplace (130.61.251.250) is CardTrader
dump / Postgres **writer** only.

- Web production: ORACLE_API_BASE_URL=https://api.pokoin.com POKOIN_WEB_DEPLOY_TARGET=production ./deploy-pokoin-web.sh
- API production: rsync api/*.js and server/*.js to pi-home /srv/pokoin/api/current,
  then docker restart pokoin-oracle-api. Stripe env (STRIPE_SECRET_KEY,
  STRIPE_WEBHOOK_SECRET) belongs in the pi-home container/env for that service,
  not on peer3.
- Meili is localhost 127.0.0.1:7700 on pi-home next to the API.
- pokoin-web typeahead is GET /api/marketplace-suggest; Flutter still uses
  POST /api/marketplace-autocomplete. Opening https://api.pokoin.com/ is the
  operator index; omit /api and the handler 404s.
- Prisma checks: from pokemon_card_vault/, run npm run prisma:validate,
  npm run prisma:sync, and npm run prisma:smoke.
- See pokemon_card_vault/docs/marketplace-search-ranking.md for typeahead vs
  Postgres search_weight.

## 2026-08-29 Pokoin card_id cutover

Marketplace `card_id` is now the public Pokoin number (CardTrader id * 2). Original CardTrader blueprint id is `ct_id`. CDN filenames stay on the CardTrader number. Espurr: `ct_id=110481`, `card_id=220962`. Dumps: Oracle `/var/backups/pokoinpos-postgres/` and nezopt `artifacts/backups/marketplace-postgres/` (pre + post). Flutter web on Vercel still needs a deploy so it stops doubling `card.id`.


## 2026-08-29 New cards catalog
- Projected 3295 missing EN-set blueprints into marketplace_cards/search (52270). Live homepage newArrivalIds = Mega Evolution (Mega Lucario ex first).
- CDN ingest required: hasCdnBackedImages rejects CardTrader URLs. Mega Evolution singles going to R2.
- pokoin.com Flutter Hive home cache may still be 12h until web rebuild (`snapshot_v2_new_arrivals`).
- Do not run full refresh_marketplace_cards_from_blueprints() live.
