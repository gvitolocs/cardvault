# Bugs and fixes (human backup)

Use this file for notable incidents and verified fixes. Link to PRs/commits when possible.

## Template

```markdown
### YYYY-MM-DD — Short title
- **Symptom**:
- **Root cause**:
- **Fix**:
- **Verify**:
- **Risk area** (payments / auth / wallet / migrations / blockchain):
```

### 2026-09-01 — Gold HR Lucario/Gardevoir lost foil texture
- **Symptom**: Homepage Mega Lucario ex 188 / Mega Gardevoir ex 187 looked like flat gold silhouettes with square corners and a white bottom strip.
- **Root cause**: Re-encode from pokemontcg `me1/188` / `me1/187` (D00000L). Those renders have no foil grain. Gold-foil JPEG path flattened onto white and skipped the die-cut.
- **Fix**: Restore CardTrader photos (foil texture). Gold-foil now diecut-only + 8× round onto dark matte. D00000R. Live leftover keys `?v=ct1`.
- **Verify**: API `703382` / `703380` `imageUrl` has `?v=ct1`. Corners `(11,10,15)`, mid still gold not `(255,211,0)`.
- **Risk area**: marketplace catalog images (not payments).

### 2026-09-01 — Mega Lopunny pink rectangle + jagged die-cut
- **Symptom**: English Mega Lopunny ex (Phantasmal Flames 084) had a magenta block on the grey rim left of STAGE 1, and stair-stepped corners.
- **Root cause**: Pink was already in the catalog JPEG (not painted by the sanitizer). Official `me2/84` has silver there. Jagged round was `diecut-only` using a 1× binary clip instead of the 8× coverage AA used on yellow rebuild-frame.
- **Fix**: `applySupersampledRoundedRectAlpha` (8× corner coverage) on every JPEG/PNG die-cut. Re-encode 084 from pokemontcg hires, leftover `356870_mega-lopunny-ex.jpg`, `?v=r8`.
- **Verify**: Local and live `?v=r8` TL 50×140 magenta count 0. API `imageUrl` `/card-images/713740_mega-lopunny-ex.jpg?v=r8`.
- **Risk area**: marketplace catalog images (not payments).

### 2026-09-01 — Team Up GX grey die-cut ears (class scan)
- **Symptom**: Same muddy grey corner flatten as Gengar 165/181 on other Team Up GX leftover JPEGs (short `{ct_id}_` keys, silver or yellow rim).
- **Root cause**: Old leftover encode flattened the rim into the dark JPEG matte. Scanning Milo’s long CardTrader filenames missed it — those are different objects. Live leftover keys had to be copied from R2 into the local CDN tree first.
- **Fix**: `scan-suspicious-grey-corners.js` reads exact leftover keys locally, confirms vs pokemontcg hires, re-encodes 16 Team Up hits `?v=fa2`, writes R2 + local CDN. JP unmapped not applied.
- **Verify**: Local 16/16 no longer smear. Live Ampharos FA `/card-images/259664_ampharos-gx.jpg?v=fa2`. Gengar 165/181 remains `?v=fa1`.
- **Risk area**: marketplace catalog images (not payments).

### 2026-09-01 — Gengar & Mimikyu GX FA grey die-cut ears
- **Symptom**: Bottom-left (and top-right) corner showed a flat mid-grey blob outside the silver rim on live catalog JPEG.
- **Root cause**: Old leftover encode flattened the SM silver rim into the dark JPEG matte. Official `sm9/165_hires.png` corners are transparent then silver/white `(225–228)`, not grey. Leftover key omits `full-art`.
- **Fix**: Re-encode from pokemontcg hires, leftover `129834_gengar-mimikyu-gx.jpg`, `?v=fa1`. Do not full-catalog apply.
- **Verify**: Live BL d=15 is `(228,228,230)`; TR `(214,214,216)`. API `imageUrl` has `?v=fa1`.
- **Risk area**: marketplace catalog images (not payments).

### 2026-09-01 — Turtwig / Gible yellow edges not era-width
- **Symptom**: Turtwig 17/17 yellow sides much thicker than top; Gible inner yellow/silver join is jagged along the whole side. Lucario/Pikachu POP6 stayed cropped (~1.5 mm) after br3.
- **Root cause**: (1) `isYellowHue` walk into Grass art → T=31 AABB. (2) pokemontcg transparent corners → `already-rounded` / no pad. (3) blit copied alpha holes over the yellow pad → black nicks inside the die-cut. (4) `weldOnly` did not straighten Gible’s inner join. (5) DP beige and Pikachu yellow art hit `isGoldFoilRaster` ≥40% despite a 11–13 px printed rim.
- **Fix**: `belongsToPrintedRim`; `cropped-alpha-corners` → rebuild-frame; blit skips alpha<40; `paintStraightFrame` fills holes; gold-foil false when tMed is a thin rim. POP Series 6 live `?v=br4`.
- **Verify**: Turtwig L=R=26 px / 2.65 mm, (20,20) yellow not matte, header green; Gible join spread 1; Lucario rebuild-frame 25/25/25. Tests 30/30 in `sanitize-card-image.test.js`.
- **Risk area**: marketplace catalog images (not payments).

### 2026-09-01 — DP silver header yellow nicks (Gible / Bidoof)
- **Symptom**: After rebuilding POP Series 6 thickness, Gible LV.8 and Bidoof LV.10 showed small yellow flecks in the inner corners of the silver name/HP bar.
- **Root cause**: Light DP silver matches `isPunchableEar`. `fillInsideDieCutEars` paints the quarter-circle at the original corner, which includes header pixels past measured T. The 4× supersample fan `orig + radius` did the same.
- **Fix**: Skip interior past measured T in the ear fill; weld original pixels only in the yellow band; `paintStraightFrame` `weldOnly` when pad > 0; `inCornerFan` is canvas-relative.
- **Verify**: sanitizer test `cropped DP header (Bidoof-class)`; live Gible `?v=br2` inner header `(182,172,163)` matches official `pop6/7` PNG. POP Series 6 25/25.
- **Risk area**: marketplace catalog images (not payments).

### 2026-08-31 — Mega Lucario / Gardevoir gold HR painted flat yellow
- **Symptom**: Gold Secret Rare Mega Lucario ex 188/132 (and Mega Gardevoir ex 187/132) looked like a flat yellow silhouette; outer millimetre lost the metallic highlight. Same class of mistake as Mega Gardevoir earlier and as Hilda UR orange / Lillie SIR yellow triangles.
- **Root cause**: Leftover keys (`351691_mega-lucario-ex.jpg`) omit `hyper-rare`, so `isBorderlessTreatment` is false. Outline family is yellow (~88% of pixels). `keepOriginalRaster` skipped only non-yellow die-cuts, then `weldToOutline` painted `(252,220,76)` → `(255,211,0)`. Encode was also stacked on a previously sanitized JPEG in some passes.
- **Fix**: `isGoldFoilRaster` (≥40% yellow hue) → `diecut-only` / `gold-foil`. Punch + round only. Always fetch pokemontcg.io PNG. Documented in `docs/card-border-rebuild-pass.md`.
- **Verify**: sanitizer test `gold foil (Mega Lucario / Gardevoir HR) is not a yellow frame`; official PNG mid-top stays washed gold, not saturated `(255,211,0)`.
- **Risk area**: marketplace catalog images (not payments).

### 2026-08-31 — Gyarados second yellow rim / Charizard white line
- **Symptom**: Shining Gyarados 65/64 after-rebuild had a pale extra frame around yellow that was already there. EX Charizard 100/97 had a bright white/yellow hairline on the outer edge.
- **Root cause**: `white-ears` studio shots were padded like cropped square-cuts. Outline colour was sampled from the 1.2% JPEG halo (Gyarados `(226,206,119)` vs real `(239,205,20)`). Original halo/highlight was blitted on top of the pad.
- **Fix**: `white-ears` → `diecut-only` (no pad). Sample the saturated frame. Weld washed/highlight fringe on the outer 3–4 px. Square-cut cropped cards (Gulpin, EX Charizard) still pad.
- **Verify**: sanitizer tests 18 pass; local `/tmp/card-border-samples/rares/08-…gyarados…` is 285×395 pad 0; Charizard top-mid is `(238,213,94)` not `(252,241,99)`. Catalog not rewritten.
- **Risk area**: marketplace catalog images (not payments).

### 2026-08-29 — Dachsbun 598052 black card art
- **Symptom**: Detail page black rectangle; slug metadata OK; no sellers.
- **Root cause**: (1) `refresh_marketplace_oracle_projections()` AccessExclusiveLock 74m. (2) versions SQL `card_id OR ct_id` seq scan (~1.1s). Public id is Dachsbun `598052`. Leftover R2 object happened to be named `299026_…jpg`.
- **Fix**: Cancelled refresh. Versions resolve card_id via search_candidates then PK. Versions lookup by our card_id. Index 020. Delta-import wrapper gated by `POKOIN_ALLOW_FULL_PROJECTION_REFRESH=1`. Doc: `pokemon_card_vault/docs/marketplace-card-image-pipeline.md`.
- **Verify**: `GET /api/marketplace-card-versions?cardId=598052&limit=1` 200 fast; image_url contains `299026_`; browser loads `/card-images/299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg`.
- **Risk area**: marketplace catalog / Oracle API (not payments).

## Notes

- Payment, balance, wallet, auth, migrations, and purchase flows need server-side verification after any fix.
- Do not document secrets or API keys here.
