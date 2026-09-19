# Charizard 713832 — nezopt bake-off (2026-09-04)

Host: **nezopt** (this machine). GPU: AMD Radeon RX 7900 XTX via ROCm torch 2.9.1 + OpenCV 4.13.  
Source: **true ct2 leftover** `pokoin-web/market/public/review/charizard-leftover.jpg` (737×1021).  
**Not** CardTrader. **Not** `/home/nez/Projects/pokoin/PokoinTest/index/cdn_images/356916_mega-charizard-x-ex.jpg` — that local mirror is now **761×1038 sanitized** (overwritten; do not use as “before”).

Raw outputs: `/tmp/charizard-nezopt-bakeoff/` (`report.json`, `qwen-vl.json`, one JPEG per trial).  
Harness: `pokemon_card_vault/scripts/lib/charizard-nezopt-bakeoff.py`.

Attack sharpness = mean horizontal |ΔRGB| on the Inferno X band (y 58–68%, x 20–80%). Source = **28.27**. Higher ≈ sharper text. Giuseppe’s red-line = **bright outer gold edge**, not inset-mean.

---

## What people publish vs what we actually ran

| Claim (online) | Source | Our test | Result |
| --- | --- | --- | --- |
| Ignore rounded corners; fit **straight sides**, then intersect to a quad | [AWS Builder Cards / DEV.to](https://dev.to/aws-builders/where-exactly-is-the-card-in-this-photo-image-segmentation-model-inside-a-maxed-out-lambda-51da) | 18% inset LS on four sides | **Trap:** mean of 4 angles ≈ **−0.01°** while right side is **−0.36°** and bright edge is **−1.58°**. Horizontal vs vertical **cancel**. They **intersect lines**, they do not average angles. Our 06/06b **failed to deskew**. |
| `approxPolyDP` + `warpPerspective` finds the card | PyImageSearch / [SO 76942415](https://stackoverflow.com/questions/76942415/find-accurate-approximate-contour-of-a-warped-card-with-rounded-corners-with-ope) | Trial 10 | **FAIL.** 4 corners returned, but warp **sliced/resampled** the face (sharp 28.27→23.83). Matches SO: rounded poker corners fool `approxPolyDP`. |
| `minAreaRect` is better than `approxPolyDP` for round-corner cards | [Stackguides 39565584](https://stackguides.com/questions/39565584/better-edge-detection-with-opencv-and-rounded-corner-cards) | minAreaRect = **−1.79°** vs bright **−1.58°** | **GOOD estimator** (close to red-line). Using it as the rotate amount + NN **almost** upright (bright **+0.20°**). |
| Default `INTER_LINEAR` smears after warp | [SO 39371507](https://stackoverflow.com/questions/39371507/image-loses-quality-with-cv2-warpperspective) | Trials 02, 07 | **FAIL interior.** Sharp **21.22** and **22.07**. Confirmed. |
| Use `INTER_NEAREST` to keep edges | same SO; PyImageSearch warns blocky diagonals | 03, 08 | **Best deskew so far.** 08 bright-edge NN: remaining bright **−0.013°**, sharp **25.8**. Cost: **NN stairs + 105 corner specks**. |
| `INTER_CUBIC` / Lanczos = “high quality” | OpenCV resize folklore | 04, 05 | **Not** lossless. Sharp ~25.2 (same class as NN) but **less** blocky than NN. Still **−3** sharpness vs source. Lanczos 243 ms (slowest CPU). |
| Hough lines on Canny | Classic; Qwen ranked **worst** for foil | 09 | **FAIL to detect.** `HoughLinesP` returned **null** (gold etching + dark matte). Trial was a no-op. |
| 2× supersample then rotate | Common “quality” trick | 13 GPU | **Worst interior.** Sharp **22.04** (−6.23). Matches 2026-09-02 GPU variant A. |
| Neural 4-corners + dewarp to 252×352 | [CollectorVision / Cornelius](https://blog.hanclin.to/posts/gh-20/) | not run as catalog output | **Skip for masters.** Output is an ID crop; they document failure on **full-art / no light border** (gold HR). |
| rembg / SAM for silhouette | rembg-mcp, u2net | not run | **Skip.** Leftover already on `#0b0b0f`. Non-deterministic edges. |
| Clip rounded-rect, do **not** resample face | Qwen VL 2026-09-04 | 01 | **Perfect interior** (sharp 28.27). **Tilt unchanged −1.58°**. 61 source white specks remain. Correct **if** we accept the lean. |
| VL can judge 0.3° stairs | our prior Qwen VL | 6 frames | **FAIL as judge.** Every frame: `interior_text: clean`, `usable_for_catalog: yes`, tilt stuck at **−1.2°** except supersample **−2.5°**. Use **numbers**, not VL, for this card. |

---

## Operational fails (before pixels)

1. **Local CDN mirror mutated.** `PokoinTest/.../356916_mega-charizard-x-ex.jpg` is **761×1038** sanitized, not ct2. Bake-off would have been wrong if we had used D00000Q blindly. Frozen before-file: `charizard-leftover.jpg` 737×1021.
2. **Rotation sign.** Sharp `rotate(+deg)` = **clockwise**. OpenCV `getRotationMatrix2D(+deg)` = **counter-clockwise**. First harness pass applied `−tilt` as in JS and **doubled** the lean (bright −1.58° → −3.37°). Documented, then inverted. Torch `grid_sample` is a **third** convention: even with the OpenCV-corrected angle, GPU trials landed at bright **≈ −2.75°** (wrong way / wrong magnitude). **Do not copy Sharp degrees into OpenCV/torch without a sign test.**
3. **Inset-mean as “upright”.** Four-side average **−0.01°** while Giuseppe’s right gold edge is **−1.4° to −1.6°**. First verdict table marked clip-only as `tilt_ok`. That was a **metric fail**, not a pixel fail.

---

## Source geometry (ct2 leftover, no processing)

| Estimator | Degrees | Notes |
| --- | --- | --- |
| Bright outer edge (Theil–Sen, our red-line) | **−1.584** | Matches 2026-09-02 JS |
| Right-edge LS (visible gold) | **−1.393** | RMS 0.69 px — already a fairly straight line, just **tilted** |
| `minAreaRect` | **−1.787** | Closest cheap box to red-line |
| Inset 18% **right** | −0.364 | Silhouette ≠ bright gold |
| Inset 18% **left** | −0.018 | |
| Inset 18% **mean** | **−0.011** | **Cancelled** — do not use |
| Inset 18% vertical mean | −0.191 | Still 8× too small vs red-line |
| Hough | **null** | No usable lines |
| Attack sharpness | 28.27 | Baseline |
| Corner light specks | 61 | Source ears / fringe |

---

## All trials (correct OpenCV sign)

Pass rule: `|bright_edge| ≤ 0.20°` **and** sharpness loss ≤ 4 **and** (specks noted, not auto-fail). Table uses **bright_edge** as tilt.

| ID | Method | Applied ° | Bright after | Sharp (Δ) | Specks | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 15 | Source control | 0 | −1.584 | 28.27 (0) | 61 | Tilt remains |
| 01 | Geometric 5% die-cut only | 0 | −1.584 | 28.27 (0) | 61 | Interior win; tilt remains |
| 09 | Hough + NN | 0 (null) | −1.584 | 28.27 (0) | 61 | Detector fail |
| 06 | Inset-mean + NN | −0.011 | −1.448 | 27.92 (−0.36) | 59 | Angle too small |
| 06b | Inset vertical + NN | −0.191 | −1.368 | 27.94 (−0.33) | 61 | Still too small |
| 07 | Inset-mean + LINEAR | −0.011 | −1.580 | **22.07 (−6.21)** | 0 | Tiny bilinear still smears |
| 08 | **Bright-edge + NN** | −1.584 | **−0.013** | 25.80 (−2.47) | 105 | **Best upright**; NN stairs |
| 03 | minAreaRect + NN | −1.787 | +0.201 | 25.20 (−3.08) | 102 | Close; slight overshoot |
| 04 | minAreaRect + CUBIC | −1.787 | +0.205 | 25.16 (−3.11) | 13 | Softer; fewer specks |
| 05 | minAreaRect + Lanczos4 | −1.787 | +0.195 | 25.21 (−3.06) | 9 | Same as cubic; slow |
| 02 | minAreaRect + LINEAR | −1.787 | +0.201 | **21.22 (−7.05)** | 15 | Deskewed + destroyed text |
| 10 | approxPolyDP perspective NN | homography | 0.0 | **23.83 (−4.45)** | 16 | Upright crop, face damaged |
| 12 | GPU nearest (torch) | −1.584 | **−2.719** | 28.56 (+0.29) | 0 | Sign/convention fail; interior ok |
| 11 | GPU bilinear | −1.584 | −2.751 | 24.21 (−4.07) | 0 | Wrong tilt + smear |
| 13 | GPU 2× supersample | −1.584 | −2.756 | **22.04 (−6.23)** | 0 | Worst interior |
| 14 | GPU crop–rotate–crop bilinear | −1.584 | −2.751 | 24.21 (−4.07) | 0 | Same as 11 |

---

## Qwen VL (`qwen3-vl:32b-instruct` on the 7900)

Unloaded the text model first (mutually exclusive, ~24 GiB). Six frames, JSON judge.

| Frame | VL tilt | VL interior | VL usable | vs metrics |
| --- | --- | --- | --- | --- |
| Source | −1.2 | clean | yes | Misses 61 specks; tilt in the ballpark |
| Clip-only | −1.2 | clean | yes | Same as source — correct that interior is untouched |
| minAreaRect LINEAR | −1.2 | **clean** | yes | **Wrong.** Sharp 21.22; text is smeared |
| Bright-edge NN | −1.2 | clean | yes | Misses remaining ~0° vs source −1.6°; missed 105 specks |
| approxPolyDP | −1.2 | clean | yes | **Wrong.** Sharp −4.45 |
| GPU supersample | −2.5 | clean | yes | Only trial VL called more tilted; still said clean at sharp 22 |

**Choice:** keep VL for “is this a gold card / is the face destroyed-to-mush?”, not for catalog QA of 1° / 1 px fringe.

Text Qwen (`qwen38aggressive`) earlier ranked: line-fit > minAreaRect > Hough; skip SAM; NN RGB. That ranking **matched the numbers**; VL did not.

---

## Choices locked from this bake-off

1. **Measure tilt on the bright gold edge** (or `minAreaRect`), never the mean of four inset angles.
2. **Builder Cards recipe** is “four lines → **intersect** → homography”, not “average four slopes → `warpAffine`”. On this leftover the card is **planar**; homography via `approxPolyDP` **hurt** the face. Prefer **2D rotate** with a red-line angle.
3. **`INTER_LINEAR` is disallowed** on gold HR leftovers (even a 0.01° LINEAR pass dropped sharpness by 6).
4. **`INTER_NEAREST` after bright-edge −1.58°** is the only trial that both **stands the card up** (bright −0.013°) and keeps sharpness in the mid-25s. Accept NN stairs or follow with the existing **geometric 5% die-cut + matte JPEG guard** (specks 105 → should drop; not re-tested in this pass).
5. **Do not** 2× supersample, **do not** torch-rotate until the affine sign is unit-tested against OpenCV on this file.
6. **Clip-only** is the right choice only if Giuseppe prefers **zero interior change** and lives with **−1.6°** lean.
7. **CollectorVision / rembg / Hough / SAM** are out for this leftover.

---

## Files to look at

```
/tmp/charizard-nezopt-bakeoff/00-source.jpg
/tmp/charizard-nezopt-bakeoff/01-clip-only-rounded-rect.jpg    # interior perfect, still tilted
/tmp/charizard-nezopt-bakeoff/08-bright-edge-nearest.jpg     # best upright
/tmp/charizard-nezopt-bakeoff/02-minarearect-linear.jpg      # literature-confirmed smear
/tmp/charizard-nezopt-bakeoff/10-approx-poly-perspective.jpg # rounded-corner trap
/tmp/charizard-nezopt-bakeoff/13-gpu-supersample2x.jpg       # worst interior
/tmp/charizard-nezopt-bakeoff/report.json
/tmp/charizard-nezopt-bakeoff/qwen-vl.json
```

Re-run: ` /home/nez/Projects/ai-toolkit/venv/bin/python pokemon_card_vault/scripts/lib/charizard-nezopt-bakeoff.py`

Not uploaded to CDN. Not `?v=ct3`. Next product step is Giuseppe picking **clip-only (keep lean)** vs **08 NN deskew (upright, slight text/NN cost)** then a fringe-guard pass.
