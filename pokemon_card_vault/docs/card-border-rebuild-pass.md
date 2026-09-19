# Card border rebuild — full-pass spec

This is the recipe for a catalog JPEG pass on R2 `cardvault-images`. It does
**not** run until Giuseppe says go. D00000E: catalog stays JPEG/WebP; backup
`originals/{key}` once; never write sibling `.png`; never delete the live JPEG.

Code: `scripts/lib/sanitize-card-image.js`
(`classifyRebuildJob`, `rebuildEvenOuterBorder`). Era millimetres:
`docs/card-image-sanitize.md`. Local gallery (read-only Milo copy):
`/home/nez/Projects/pokoin/PokoinTest/index/cdn_images`.

When a CardTrader scan is messy (halo, thin top, washed fringe), **do not
invent geometry**. Pull the community scan from the Pokémon TCG API CDN
(`api.pokemontcg.io`, MIT data at PokemonTCG/pokemon-tcg-data):

`https://images.pokemontcg.io/{setId}/{number}_hires.png`

Order of operations (do not invert):

1. Rotate so the **inner printed rectangle** is upright (left/right join,
   not the name-bar). Gold / foil-to-edge: rotate the card silhouette
   against paper, never chase the illustration. FA / IR / SIR: skip rotate.
2. **Then** measure the outer rim and rebuild to era millimetres, or
   die-cut only (gold, FA, complete studio).

First reference: Shining Gyarados Neo Revelation **neo3/65**
(`https://images.pokemontcg.io/neo3/65_hires.png`, 600×825, square-cut,
yellow **21–22 px / 2.33 mm** on the sides, colour ≈ `(246,204,0)`). Inner
join is a straight rectangle; do not invent a thicker walk into gold. Wild
Growth Games serves that same asset. Catalog R2 stays CardTrader; this CDN is
the visual ground truth only. Catalog output from those PNGs is **JPEG**
(q100, 4:4:4, mozjpeg) — never a sibling `.png` on R2 (D00000E). Local pull:

`node scripts/import-pokemontcg-wizards-hires.js --dry-run`
`--limit=40` writes JPEGs under `/tmp/pokemontcg-wizards-jpg`. Does not upload.

## Physical constants

| Spec | Value |
| --- | --- |
| Trim | 63 × 88 mm worldwide (often quoted 63.5 × 88.9 poker) |
| Aspect | `63.5 / 88.9 ≈ 0.7143`. `isCardRaster` allows 0.62–0.82 |
| Corner radius | 3.175 mm = **5% of the short side**. CSS `5% / 3.571%` |
| Card stock | ~0.30 mm EN, ~0.32–0.34 mm JP |
| JPEG out | q100, 4:4:4, mozjpeg, flatten `#0b0b0f` |
| Round | 8× coverage sample on the four corners (partial alpha → matte AA) |

Japanese cards are **not** a smaller trim. They look bigger because the printed
frame is thinner.

## When the yellow looks “cut”

Square-cut scans crop the die-cut. Clipping a 90° yellow L at 5% **pinches**
the corner:

`radial remaining = R − √2(R − T)`

Gulpin 33/100 (500 px, T = 10, R = 25) → **~3.8 px (~0.5 mm)** vs ~2.5 mm on
the sides. Physical yellow is ~2.5 mm vs radius 3.175 mm (**T/R ≈ 0.79**).

The framed rebuild **pads outline colour outside the original pixels** until
T′ ≥ 0.78 R, then die-cuts. Pad is equal on all four sides, so original
centering is kept (Gulpin top 14 px vs bottom 11 px). Copyright lives **in**
the bottom yellow; do not paint over original interior.

Do **not** pad `white-ears` files. Those are photos of an already die-cut
card; the yellow/silver is already the printed width. Padding Gyarados 65/64
drew a second pale rim (sampled from the JPEG halo) around yellow that was
already there. On die-cut-only JPEGs, walk inward from each edge and paint
washed/white/muddy yellow into the **saturated** outline until the real
frame is reached (Wild Growth Games style: one coherent yellow band). Do
not punch the top halo to matte (that left a jagged hole) and do not pad a
second rim outside the card.

## Job classifier (`classifyRebuildJob`)

Every file gets one action:

| Action | Meaning |
| --- | --- |
| `skip` | Not a card, or corners already die-cut |
| `diecut-only` | White-ear fill + 5% round. **No pad** (studio photos already have the printed frame; padding draws a second rim) |
| `rebuild-frame` | Pad **square-cut cropped** yellow/gold/silver to era width, then die-cut |

Pass `filename` / `key` into `sanitizeCardImage`. Without a name, yellow
square-cut still `rebuild-frame` (tests). **White-ear studio shots are
always `diecut-only`** — Shining Gyarados 65/64 already had a full yellow
frame; padding painted a second pale rim on top of it.

### Filename treatments that are `diecut-only`

`full-v4` is CardTrader’s **full-resolution** file, not Full Art. Ignore it.

| Slug | What it is | Frame |
| --- | --- | --- |
| `full-art` | BW+ Ultra Rare / SV FA ex. Art + thin silver rim. Rule boxes sit **on** the rim | Silver rim ~2–4 px leftover. **Do not pad** |
| `illustration-rare` | SV IR (JP **AR**). One gold star. Full-bleed scene, thin silver | Same |
| `special-illustration-rare` | SV SIR (JP **SAR**). Two gold stars. Chase full-bleed | Same |
| `hyper-rare` | SV gold (JP **UR**). Three gold stars. Foil to the edge | Gold texture **is** the edge. **Do not pad yellow** |
| `rainbow-rare` | SwSh rainbow V/VMAX/Trainer | Foil to the edge |
| `shiny-rare` | SV shiny vault (e.g. 267/190) | Thin/no yellow |

Gallery counts (2026-08-31, filenames only): `full-art` 144, `illustration-rare`
561, `hyper-rare` present, `secret-rare` 1293, `full-v4` thousands (ignore).

### Over-number is not a skip

“Secret rare” / “outnumbered” means collector number **> set size** (`160/142`,
`168/165`, `258/198`, EX `100/97`). Parser: last `N-M` with **M ≥ 10** and
N > M. Rejects `bw30-2nd`.

| Example | Over? | Frame | Job |
| --- | --- | --- | --- |
| Dachsbun 099/198 SV | no | Silver, ~2.4 mm on some ex | `rebuild-frame` if yellow/silver T is real |
| Dachsbun ex 067/142 | no | Silver T ≈ 19 px / 500 | `diecut-only` (studio ears) |
| Dachsbun ex **FA 160/142** | +18 | Thin silver rim, art to the rim | `diecut-only` |
| Dachsbun ex **SIR 169/142** | +27 | Full-bleed | `diecut-only` |
| Charmander **IR 168/165** | +3 | Thin silver, art to the rim | `diecut-only` |
| Fighting Energy **HR 258/198** | +60 | Gold foil to the edge | `diecut-only` |
| Charizard VMAX rainbow **074/073** | +1 | Foil to the edge | `diecut-only` |
| Charizard **EX secret 100/97** | +3 | **Still yellow** T ≈ 10 px (cropped) | `rebuild-frame` |
| Hidden Fates GX “secret” 9/68 | no (subset) | Full-art GX, T ≈ 0 | `diecut-only` via thin non-yellow rim |
| Shining Gyarados **65/64** Neo | +1 | Use **pokemontcg.io neo3/65_hires** (even yellow). CT JPEG is a bad studio crop | `diecut-only` on CT; round-only on the API scan (pad 0) |

Pixel fallback: if the outline is **not** yellow/pale-gold and T < 1.2% of the
short side → `diecut-only` (Mega dark frames, FA silver rims).

### Gold foil is not a yellow frame

Mega Lucario ex **188/132** and Mega Gardevoir ex **187/132** (MEG EN Gold
Secret Rare) are foil to the edge. Official `me1/188` / `me1/187` PNGs are
~88% yellow hue; leftover keys are short (`351691_mega-lucario-ex.jpg`,
`351690_mega-gardevoir-ex.jpg`) so `isBorderlessTreatment` is false.

`sampleOutlineColor` then treats the gold art as a yellow frame.
`paintStraightFrame` / `weldToOutline` flatten the outer metallic highlight
`(252,220,76)` into saturated `(255,211,0)`. Same class of bug as painting
Hilda UR sunset orange or Lillie SIR hat yellow into silver corners.

If ≥40% of sampled opaque pixels are yellow hue (`isGoldFoilRaster`), job is
`diecut-only` / `gold-foil`. Punch + 8× round only. Do not weld. Flatten onto
the dark marketplace matte (not white). A real Wizards yellow rim is ~15–20%
yellow pixels (Gyarados still welds).

**Prefer CardTrader photos** for gold HRs — they keep the foil grain.
pokemontcg.io / Limitless gold renders are flat silhouettes (Giuseppe
rejected those on Mega Lucario 188 / Gardevoir 187). Never run sanitize on a
live catalog JPEG that already went through a yellow weld; use `originals/`
or a fresh CardTrader URL.

| Example | Leftover key | Job |
| --- | --- | --- |
| Mega Lucario ex gold 188/132 | `351691_mega-lucario-ex.jpg` | `diecut-only` (`gold-foil`) |
| Mega Gardevoir ex gold 187/132 | `351690_mega-gardevoir-ex.jpg` | `diecut-only` (`gold-foil`) |
| Hilda UR 164/086 White Flare | `343049_hilda.jpg` | `diecut-only` (lock silver rim; no orange) |
| Lillie’s Determination SIR | `351687_lillie-s-determination.jpg` | `diecut-only` (lock silver; no yellow triangles) |

## Measured frames (local gallery)

| File | Kind | Family | T | Notes |
| --- | --- | --- | --- | --- |
| Gulpin 33/100 EX CG | square-cut | yellow | 10 px / 1.3 mm | Cropped; pad +11 → 522×710 |
| Magma/Aqua Bulbasaur 39/95 | square-cut | yellow | 7–9 px | Pad +9 |
| Trapinch 83/149 BKT | white-ears | yellow | 19–22 px / ~2.5 mm | No pad; already era-correct |
| Base Set Bulbasaur 44/102 | white-ears | yellow | 16 px / ~3.2 mm | Wizards thick |
| Dachsbun 099/198 SV | white-ears | silver | ~0 (walk failed on white ears) | SV silver; die-cut + fill ears |
| Dachsbun ex 067/142 | white-ears | silver | 19 px | Standard SV ex **has** a silver frame |
| Dachsbun FA 160/142 | white-ears | silver | 2–3 px | FA rim; no pad |
| Charmander IR 168/165 | mixed | silver | sides 17 px (art/sky walk) | Treat as borderless from slug |
| Fighting Energy HR 258/198 | white-ears | gold-ish | 0 | Gold foil; no pad |
| EX Charizard secret 100/97 | square-cut | yellow | 10 px | Framed secret; pad. Weld the bright top ring |
| pokemontcg.io neo3/65 Gyarados | square-cut | yellow | **21–22 px / 2.33 mm** | API hires; pad 0; paint a straight AABB then round |
| pokemontcg.io pop6/7 Gible | square-cut | yellow | **13–15 px / 1.48 mm** | Cropped DP promo. `rebuild-frame`: pad then paint AABB at **pad + measured** (`weldOnly`). Do not weld the silver name bar. Live leftover was unsanitized 600×825 square-cut. |

JP Advent of Arceus (2009, pre-BW): pale gold, T ≈ 13–15 px / 500 ≈ **1.7–1.9 mm**.

## Straight inner edge (`paintStraightFrame`)

Once mid-side thickness is known, the inner yellow/blue join is **one
axis-aligned rectangle** (left/right equal, top and bottom from their own
walks). Fill that band; do not walk scanline-by-scanline. A greedy walk
followed gold (`isYellowHue`) and holo noise past T and produced the
Gyarados stair-step (left T 22→34) and the jagged top.

Cap T at 7% of the short side (~4.4 mm). Values past that are the gold art
window (~54 px / 600 on neo3/65), not the printed yellow. If every side
fails the cap (foil-to-edge), paint nothing.

On **cropped** yellow (`pad > 0`, e.g. POP Series 6 Gible 14 px vs 22 px
target): grow the canvas first, then `paintStraightFrame` at **pad +
measured** so the inner join is one straight era-width rim. Painting only
the old T on the original left the muddy 1.48 mm join in place. Era-complete
scans (`pad === 0`, Gyarados 21–22 px) still paint measured T only — do not
eat the gold art window.

The old 4× full-raster supersample used to weld `isPunchableEar` light pixels in a fan of
`orig + radius` (~42 px into Gible). That is the DP silver name/HP bar —
it became yellow nicks at the inner header corners (Bidoof LV.10, Gible
LV.8). The same class of fill happened earlier in `fillInsideDieCutEars`:
the quarter-circle at the original corner includes the silver header
(`x > T && y > T`). Skip that interior; only fill the outer crescent.
Weld original pixels only in the measured yellow band; skip light
non-yellow interior. `inCornerFan` is the canvas die-cut (`x < radius`),
not `orig + radius`. `paintStraightFrame(..., { weldOnly: true })` when
`pad > 0` so the AABB does not stamp yellow onto the rounded silver header.

Wizards/Neo printed yellow (neo3/65): **2.33 mm sides**, **~2.4 mm bottom**.

## Era cheat sheet (pad target as fraction of short side)

`FRAME_RATIO` in the sanitizer:

| Family | Ratio | ~mm on 63.5 | Use |
| --- | ---: | ---: | --- |
| `yellow` | 0.0367 | 2.33 | EN Wizards–Neo (neo3/65 22/600). Cropped EX still pads via 0.78 R |
| `gold-pale` | 0.028 | 1.78 | JP original–LEGEND |
| `silver` | 0.024 | 1.52 | JP BW+ (2010-12-17), EN SV+ (2023-03-31) |
| `other` | 0.036 | 2.3 | Dark Mega frames: usually `diecut-only` via thin rim |

Do not pad `silver` on FA/IR/SIR — the slug already forced `diecut-only`.
Leftover keys without the slug still must not paint art into the rim (lock
family at the shallowest silver sample; gold foil via `isGoldFoilRaster`).

## Script shape (when running the pass)

```
walk local gallery (not Milo writes)
  skip originals/, manifests/, *_homepage.webp, expansions/, artist-profiles/
  skip !isCardRaster
  classifyRebuildJob({ filename, …pixels })
  dry-run JSONL: action, pad, kind, family, overNumber
--apply:
  backupExistingObject → originals/{key} once
  sanitizeCardImage(..., { format: 'jpg', jpegQuality: 100, filename: key })
  PutObject same key (no URL change, no projection refresh)
```

Default dry-run. `--limit`, `--only`, `--concurrency`. Log:
`/home/nez/pokoincdn/cdn_images_digest/border-rebuild.log.jsonl`.

Read local gallery first (same lesson as PNG→JPEG). Do not download 70k from R2.

## Qwen VL (2026-08-31)

On the two Bulbasaur screenshots: EX Crystal Guardians = rounded die-cut
reference; BW Dark Explorers = square-cut, CSS 5% would pinch yellow. Qwen’s
“circle mask in the centre of the image” is **wrong** — we use a rounded rect
with circular corners at 5% of the short side, not a centred circle.

## 2026-09-01 edge audit (Turtwig / Gible)

The pipeline **did not check output millimetres**. POP Series 6 after
`?v=br2`: Turtwig 17/17 sides were **31 px / 3.28 mm** vs top **16 px /
1.69 mm** (spec 2.33 mm). Cause: pokemontcg alpha corners →
`already-rounded` / `diecut-only` / pad 0, then `isYellowHue` walk into
grass to T = 31, then `paintStraightFrame` fills that AABB. Gible’s
right inner join was chewed (spread 4 px) because cropped
`weldOnly` does not enforce D00000I’s straight line.

**Live `?v=br4`:** Turtwig L=R=26 px / 2.65 mm; Gible join spread 1;
Lucario/Pikachu rebuild (they were false gold-foil). Thickness walk is
`belongsToPrintedRim`. Blit skips transparent PNG corners. Gold foil
requires no thin printed rim. Full tables: `docs/card-border-edge-audit-2026-09-01.md`.
Do not full-catalog `--apply`.

## Do not

- Invent yellow on FA / IR / SIR / HR / rainbow / shiny
- Treat gold foil (~40%+ yellow pixels) as a yellow AABB (Lucario 188, Gardevoir 187)
- Sanitize a previously uploaded catalog JPEG — always fetch the pokemontcg PNG
- Treat `full-v4` as Full Art
- Treat every over-number as borderless (EX 100/97 is still yellow)
- Punch yellow corners to dark matte (thins the frame)
- Redraw the whole frame (destroys copyright / e-Reader strip)
- `refresh_marketplace_oracle_projections()`
- Delete `originals/` or live JPEGs
