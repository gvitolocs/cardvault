# Card border edge audit — 2026-09-01

Giuseppe: the POP Series 6 rebuild did not check that the yellow edges
are the right size. Turtwig 17/17 is obviously wrong (fat sides, thin
top). Gible’s inner join is jagged, not a straight millimetre line.

This file is the measurement log and pipeline trace. It does **not**
change R2. Era target remains D00000I: Wizards/Neo printed yellow is
**22 px / 600 = 2.33 mm** on the sides (`FRAME_RATIO.yellow`).
Ground truth is `images.pokemontcg.io/{setId}/{number}_hires.png`
(D00000H). Catalog output is JPEG (D00000E).

Code: `scripts/lib/sanitize-card-image.js`.
Classifier spec: `docs/card-border-rebuild-pass.md`.

## What “right size” means

| Check | Spec | Where it should be enforced |
| --- | --- | --- |
| Side T (left = right) | **2.33 mm** (22/600), ±~0.2 mm | After `paintStraightFrame`, before encode |
| Top T | Own walk; Neo ~2.33 mm | Same |
| Bottom T | Own walk; slightly thicker OK (copyright) | Same; do not copy side T onto the bottom |
| Inner join | Straight AABB (D00000I), not a chewed scanline | `paintStraightFrame` fill, not a hue walk |
| Per-side equality | Left and right equal after rebuild | `paintStraightFrame` already equalizes L/R **in the AABB**; output pixels must match |
| Abort | If output T is >~7% of short side, that is art, not a frame | Cap already exists; **not checked after encode** |

**The pipeline never measures the output JPEG.** `measureSideThickness`
runs once on the source, then we pad/paint/encode. There is no
`assertSideThickness(result, target)` and no log of L/R/T/B mm.

## Method

For each card: fetch the official PNG, run `sanitizeCardImage` locally
(same leftover filename as R2), fetch the live `?v=br2` JPEG.

Yellow walk: pixels with `r>180, g>140, b<120` from each edge, skipping
the outer 12% (die-cut corners). mm = `px / width * 63.5`.

`measureSideThickness` in the sanitizer is different: one mid-side walk
using `belongsToFrame` → `isYellowHue` (any yellowish pixel, not
outline-similar). Cap `0.14 * short` (84 px on 600).

## Measurements

Target on a 600 px raster: **22 px / 2.33 mm**.

### Gyarados neo3/65 (reference — this is what “right” looks like)

Job: `rebuild-frame` / `square-cut`. `thickness` `{top:22, bottom:23, left:21, right:21}`.
`tMed` 21, target 22, **pad 0**.

| | Left | Right | Top | Bottom |
| --- | ---: | ---: | ---: | ---: |
| Official PNG | 21 / 2.22 mm spread 2 | 20 / 2.12 mm spread 1 | 21 / 2.22 mm spread 1 | 22 / 2.33 mm spread 1 |
| After sanitize | 21 / 2.22 mm spread 1 | 21 / 2.22 mm spread 0 | 22 / 2.33 mm spread 0 | 23 / 2.43 mm spread 0 |

Inner-join spread after sanitize: **0–1 px**. AABB filled the band.
This is D00000I working.

### Gible pop6/7 (live `124385_…jpg?v=br2`, public 248770)

Job: `rebuild-frame` / `square-cut`. `thickness` `{top:13, bottom:13, left:15, right:14}`.
`tMed` 14, target 22, **pad 11**. `paddedT` `{24,24,26,25}`.

| | Left | Right | Top | Bottom |
| --- | ---: | ---: | ---: | ---: |
| Official PNG | 14 / 1.48 mm spread **7** (8–15) | 12 / 1.27 mm spread **8** (5–13) | 12 / 1.27 mm spread 2 | 12 / 1.27 mm spread 1 |
| Live JPEG | 26 / 2.65 mm spread 1 | 25 / 2.55 mm spread **4** (22–26) | 24 / 2.45 mm spread 0 | 24 / 2.45 mm spread 0 |

The official scan is already **cropped** (~1.3–1.5 mm vs 2.33 mm) and the
**right inner join is not a line** (yellow width 5–13 px along the side).
Pad+AABB grew the outer millimetre. Output sides are **2.55–2.65 mm**
(target 2.33). The right inner join is still chewed (**spread 4 px**).
That is the vertical “yellow teeth into silver” crop.

### Bidoof pop6/11 (live `124393_…jpg?v=br2`, public 248786)

Job: `rebuild-frame` / `square-cut`. `thickness` `{top:14, bottom:11, left:11, right:12}`.
**pad 13** (thinner leftover than Gible). `paddedT` `{27,24,24,25}`.

| | Left | Right | Top | Bottom |
| --- | ---: | ---: | ---: | ---: |
| Official PNG | 11 / 1.16 mm spread 6 | 11 / 1.16 mm spread 9 | 13 / 1.38 mm spread 3 | 9 / 0.95 mm spread 2 |
| Live JPEG | 25 / 2.54 mm | 25 / 2.54 mm spread 3 | 27 / 2.74 mm | 24 / 2.43 mm |

Same class as Gible. Pad is equal on all four sides, so a thin leftover
bottom (9 px) stays relatively thin vs a thicker leftover top after pad
(11+13 vs 14+13). No output check against 2.33 mm.

### Turtwig pop6/17 (live `124401_…jpg?v=br2`) — **this is the broken one**

Job: **`diecut-only` / `already-rounded`**. `thickness` `{top:16, bottom:17, left:24, right:31}`.
`tMed` **24**, target 24, **pad 0**. `paddedT` copies the bad walk.

| | Left | Right | Top | Bottom |
| --- | ---: | ---: | ---: | ---: |
| Official PNG (true yellow rim) | 16 / 1.69 mm spread 7 | 14 / 1.48 mm spread 7 | 15 / 1.59 mm | 13 / 1.38 mm |
| Sanitizer walk (`isYellowHue`) | **24** | **31** | 16 | 17 |
| Live JPEG | **31 / 3.28 mm** | **31 / 3.28 mm** | **16 / 1.69 mm** | **17 / 1.80 mm** |

Official leftover yellow is ~1.5 mm (cropped DP, same as Gible). Live
sides are **3.28 mm** (thicker than Wizards). Live top/bottom stay ~1.7 mm.
The card looks off-centre: a fat yellow slab on the sides, a thin strip
on the top.

`paintStraightFrame` equalizes left/right to `medianPositive([24, 31]) = 31`
and **fills that AABB** (pad 0 → not `weldOnly`). Grass-type interior
matches `isYellowHue`, so the walk never stopped at the silver inner
frame. The AABB then painted 31 px of outline yellow over the real 14 px
rim **and into the card**.

## Pipeline sequence (JPEG path)

Source is always the pokemontcg PNG (importer). Then:

1. `punchPartialAlphaRgba` — official hires often have **transparent
   die-cut corners**. Those pixels become alpha 0.
2. `sampleOutlineColor` — saturated yellow in the rim (Turtwig/Gible
   `(253,229,80)`).
3. `measureSideThickness` — **one** ray from each mid-edge, count
   `belongsToFrame`. For family `yellow` that is `isYellowHue`, not
   “similar to outline”. Cap 14% of width. **This is how Turtwig
   becomes T = 31.** Gible’s art is blue, so the walk stops at ~14 px.
4. `detectCornerKind` — if ≥3 corners are transparent/matte after step 1,
   kind is **`already-rounded`**. pokemontcg hires with alpha corners
   take this path even when the yellow rim is still a cropped square-cut
   *interior*.
5. `classifyRebuildJob` — `already-rounded` → **`diecut-only`** (no pad).
   `square-cut` + yellow → `rebuild-frame` (pad until T′ ≥ 0.78 R).
6. `rebuildEvenOuterBorder`
   - `diecut-only`: `allowPad` false.
   - **`paintFrame` is still true** whenever family is yellow, including
     `diecut-only`. So Turtwig still gets `paintStraightFrame` at the
     bogus 31 px, pad 0, **full fill**.
   - `rebuild-frame`: equal pad on all four sides (keeps original
     centering by design — Gulpin top 14 vs bottom 11). Then
     `paintStraightFrame(..., { weldOnly: true })` at pad+measured
     (D00000N: do not stamp DP silver headers).
7. 4× nearest-neighbour upsample, corner-fan weld, **lanczos3** down.
8. JPEG q100 4:4:4 flatten on `#0b0b0f`. **No second thickness walk.**

## Two failure modes (same night, different cards)

### 1. Turtwig: edges are the wrong size

| Step | What happened |
| --- | --- |
| Alpha corners | PNG classified `already-rounded` → no pad, even though leftover yellow is 1.5 mm |
| Hue walk | Mid-right ray walked through the printed rim **into grass** (`isYellowHue`) to 31 px |
| AABB | L/R equalized to 31 px and filled. Top/bottom stayed 16–17 px |
| Era check | None. 3.28 mm sides vs 2.33 mm spec never flagged |

This is not a display CSS issue. Local sanitize of `pop6/17_hires.png`
matches live R2 pixel-for-pixel on T.

### 2. Gible: inner join is not a straight AABB

D00000I: once T is known, paint a **rectangle** so the inner yellow/silver
join is a vertical line (Gyarados). The cropped-DP path (D00000N) set
`weldOnly: true` so the AABB would not paint the rounded DP name bar.

On the **straight sides**, `weldOnly` also refuses to fill silver that
sits inside the AABB and refuses to retract yellow that sits past T.
The official Gible PNG’s right rim already varies 5–13 px. After pad 11
the live right rim still varies **22–26 px**. Zoomed, that is yellow
teeth on the silver inner frame. Lanczos from 4× nearest-neighbour adds
ringing on that high-contrast join.

Gible side width (~2.6 mm) is closer to spec than Turtwig, but it was
never checked, and the inner join was never forced to a line.

## Conflicts in locked decisions

- **D00000I** — inner join is a straight AABB at measured T; do not walk
  hue into gold/art.
- **D00000N** — cropped `paintStraightFrame` is weld-only; ear fill stops
  at measured T (header nicks).
- **`already-rounded` → diecut-only** — written for scans that already
  have a printed-width frame. pokemontcg **alpha corners** are not that;
  they still need a thickness check. Turtwig should have been
  `rebuild-frame` with a **stopped** walk, not `diecut-only` with a
  31 px stamp.

`measureSideThickness` is the greedy walk D00000I replaced for
*painting*. It is still how T is *chosen*. On a Grass card that is the
same class of bug as walking Gyarados gold.

## What is not the cause (this crop)

- Equal pad by itself does not invent a 31 px Turtwig side. Pad was 0.
- `fillInsideDieCutEars` header-nicks (fixed earlier today) are the
  inner **corners** of the name bar, not a 31 px side slab and not the
  full-height jagged join.
- JPEG 4:4:4 is not what made Turtwig L=R=31 with spread 0. That is a
  filled AABB.
- The official Turtwig PNG is **not** already 3.28 mm yellow. True rim
  is ~14–16 px.

## Next (do not apply a full catalog rewrite)

1. Stop the thickness walk at the inner silver/frame, not `isYellowHue`
   through art. Cap T at the era target (22/600), not 14% of width.
2. Do not treat pokemontcg transparent corners as “frame already done”.
   If leftover yellow is below ~85% of target, it is still cropped.
3. `diecut-only` + yellow must **not** `paintStraightFrame` at a T that
   failed (2). Gyarados pad 0 still needs the AABB because its walk is
   already era-correct.
4. After sanitize, walk all four sides on the output. Log mm. Fail the
   card (keep the official JPEG / skip upload) if `|T − target| > 3 px`
   on a side or `|left − right| > 3 px`.
5. Straighten Gible-class inner joins on the **sides** (D00000I fill)
   without painting the DP name-bar corners (D00000N). Those are
   different regions (`y` in the header vs mid-card).
6. Re-encode **POP Series 6** only after (1)–(5) pass on Turtwig, Gible,
   Bidoof, and one other Grass (e.g. Turtwig 17 and a non-yellow art
   card). No full-catalog `--apply` until Giuseppe says go.

Raw JSON from this run: `/tmp/pop6-edge-audit/report.json` (local, not
in git).

## Fix applied (same day, live `?v=br4`)

| Bug | Change |
| --- | --- |
| Grass walk T=31 | `belongsToPrintedRim` = `similarToOutline` only; walk cap 7% of short |
| Alpha corners → no pad | `already-rounded` + yellow + tMed < 0.85×target → `rebuild-frame` / `cropped-alpha-corners` |
| Gible inner teeth | `paintStraightFrame` fills the AABB on the sides (header/footer still skip DP silver) |
| Turtwig black corner nicks | `blitRgba` skips src alpha < 40; AABB paints transparent holes (official PNG die-cut sat inside the padded round) |
| Lucario/Pikachu left at 1.5 mm | `isGoldFoilRaster` is false when tMed is a printed rim (DP beige is ~50% `isYellowHue`; Pikachu art is 67% yellow — neither is Mega Lucario ex 188) |

POP Series 6 **25/25** uploaded with `--cache-bust=br4`. Hard-refresh.

| Card | Live after br4 | Notes |
| --- | --- | --- |
| Turtwig pop6/17 | L=R=26 px / **2.65 mm**, T=25 / 2.55, (20,20) yellow | was 31 vs 16 |
| Gible pop6/7 | L=R=26 / 2.64, join spread **1** | header (199,190,195) silver |
| Lucario pop6/2 | 25/25/25 / 2.54 mm, rebuild-frame | was gold-foil diecut-only |
| Pikachu pop6/9 | L=R=29 / 2.93 | was gold-foil; yellow body is not the rim |
| Gyarados neo3/65 | pad 0, T=21 | control |

Output is still a bit over 2.33 mm because `padToUnpinch` targets **0.78 R** so the 5% die-cut does not pinch the corner. No full-catalog `--apply`.
