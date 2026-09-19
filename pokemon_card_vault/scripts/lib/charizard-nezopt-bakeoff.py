#!/usr/bin/env python3
"""Charizard 713832 bake-off on nezopt (RX 7900 + OpenCV).

Source is the true live leftover JPEG (737x1021 ct2), NOT the overwritten
local CDN mirror (761x1038 sanitized). No CardTrader download.

Each trial is tagged with the online source that motivated it.
"""

from __future__ import annotations

import json
import math
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image

MATTE = np.array([11, 11, 15], dtype=np.uint8)
MATTE_F = MATTE.astype(np.float32)
SRC = Path("/home/nez/Projects/pokoin-web/market/public/review/charizard-leftover.jpg")
OUT = Path("/tmp/charizard-nezopt-bakeoff")
RADIUS_RATIO = 0.05
JPEG_Q = 100


def load_bgr(path: Path) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(path)
    return img


def save_jpg(path: Path, bgr: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(
        str(path),
        bgr,
        [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_Q, int(cv2.IMWRITE_JPEG_OPTIMIZE), 1],
    )


def card_mask(bgr: np.ndarray) -> np.ndarray:
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.float32)
    dist = np.abs(rgb - MATTE_F).sum(axis=2)
    mask = (dist > 40).astype(np.uint8) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    return cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k)


def largest_contour(mask: np.ndarray):
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cnts:
        return None
    return max(cnts, key=cv2.contourArea)


def min_area_tilt(mask: np.ndarray) -> float | None:
    """OpenCV minAreaRect angle converted to 'card tilt' (CCW negative)."""
    c = largest_contour(mask)
    if c is None or len(c) < 20:
        return None
    (_cx, _cy), (rw, rh), ang = cv2.minAreaRect(c)
    tilt = float(ang) if rw < rh else float(ang) + 90.0
    # Normalize to [-45, 45]
    while tilt > 45:
        tilt -= 90
    while tilt < -45:
        tilt += 90
    return tilt


def inset_side_angles(mask: np.ndarray, inset: float = 0.18) -> dict:
    """AWS Builder Cards recipe: ignore rounded corners, LS-fit four sides."""
    c = largest_contour(mask)
    empty = {"top": None, "bottom": None, "left": None, "right": None, "mean": None, "n": {}}
    if c is None:
        return empty
    (cx, cy), (_rw, _rh), ang = cv2.minAreaRect(c)
    pts = c.reshape(-1, 2).astype(np.float64)
    M = cv2.getRotationMatrix2D((cx, cy), ang, 1.0)
    P = (M @ np.hstack([pts, np.ones((len(pts), 1))]).T).T
    minx, maxx = P[:, 0].min(), P[:, 0].max()
    miny, maxy = P[:, 1].min(), P[:, 1].max()
    W, H = maxx - minx, maxy - miny
    bx, by = inset * W, inset * H
    cxlo, cxhi = minx + bx, maxx - bx
    cylo, cyhi = miny + by, maxy - by
    bands = {
        "top": P[(P[:, 1] <= miny + by * 0.6) & (P[:, 0] >= cxlo) & (P[:, 0] <= cxhi)],
        "bottom": P[(P[:, 1] >= maxy - by * 0.6) & (P[:, 0] >= cxlo) & (P[:, 0] <= cxhi)],
        "left": P[(P[:, 0] <= minx + bx * 0.6) & (P[:, 1] >= cylo) & (P[:, 1] <= cyhi)],
        "right": P[(P[:, 0] >= maxx - bx * 0.6) & (P[:, 1] >= cylo) & (P[:, 1] <= cyhi)],
    }

    def fit(edge, axis: str):
        if len(edge) < 15:
            return None
        xs, ys = edge[:, 0], edge[:, 1]
        if axis == "h":
            A = np.vstack([xs, np.ones(len(xs))]).T
            m, _ = np.linalg.lstsq(A, ys, rcond=None)[0]
        else:
            A = np.vstack([ys, np.ones(len(ys))]).T
            m, _ = np.linalg.lstsq(A, xs, rcond=None)[0]
        return float(np.degrees(np.arctan(m)))

    top = fit(bands["top"], "h")
    bottom = fit(bands["bottom"], "h")
    left = fit(bands["left"], "v")
    right = fit(bands["right"], "v")
    vals = [v for v in (top, bottom, left, right) if v is not None]
    return {
        "top": top,
        "bottom": bottom,
        "left": left,
        "right": right,
        "mean": float(np.mean(vals)) if vals else None,
        "n": {k: int(len(v)) for k, v in bands.items()},
    }


def theil_sen_bright_edge(bgr: np.ndarray) -> float | None:
    """First bright gold pixel from left/right mid-band. Matches our JS estimator sign."""
    h, w = bgr.shape[:2]
    y0, y1 = int(h * 0.2), int(h * 0.8)
    x_lim = max(8, int(w * 0.32))

    def collect(from_right: bool):
        xs, ys = [], []
        for y in range(y0, y1):
            xs_range = range(w - 1, w - 1 - x_lim, -1) if from_right else range(0, x_lim)
            for x in xs_range:
                b, g, r = bgr[y, x]
                luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                chroma = max(r, g, b) - min(r, g, b)
                if luma < 80:
                    continue
                if luma >= 230 and chroma <= 16:
                    continue
                if abs(int(r) - 11) + abs(int(g) - 11) + abs(int(b) - 15) < 30:
                    continue
                xs.append(x)
                ys.append(y)
                break
        return np.array(xs, dtype=np.float64), np.array(ys, dtype=np.float64)

    def angle(xs, ys):
        n = len(xs)
        if n < 16:
            return None
        span = max(10, int(h * 0.06))
        slopes = []
        step = max(1, n // 80)
        for i in range(0, n, step):
            for j in range(i + step, n, step):
                dy = ys[j] - ys[i]
                if abs(dy) < span:
                    continue
                slopes.append((xs[j] - xs[i]) / dy)
        if len(slopes) < 8:
            return None
        slopes.sort()
        m = slopes[len(slopes) // 2]
        return float(-np.degrees(np.arctan(m)))

    a = angle(*collect(False))
    b = angle(*collect(True))
    vals = [v for v in (a, b) if v is not None]
    if not vals:
        return None
    return float(np.mean(vals))


def hough_tilt(mask: np.ndarray) -> float | None:
    edges = cv2.Canny(mask, 50, 150)
    h, w = mask.shape
    # Mid-band only — skip corners
    roi = np.zeros_like(edges)
    roi[int(h * 0.18) : int(h * 0.82), int(w * 0.18) : int(w * 0.82)] = edges[
        int(h * 0.18) : int(h * 0.82), int(w * 0.18) : int(w * 0.82)
    ]
    lines = cv2.HoughLinesP(roi, 1, np.pi / 1800, threshold=80, minLineLength=int(h * 0.25), maxLineGap=8)
    if lines is None:
        return None
    angs = []
    for x1, y1, x2, y2 in lines[:, 0]:
        dx, dy = x2 - x1, y2 - y1
        if abs(dx) < 4 and abs(dy) < 4:
            continue
        ang = math.degrees(math.atan2(dy, dx))
        # Fold to near-vertical / near-horizontal residual
        if abs(abs(ang) - 90) < 20:
            angs.append(ang - (90 if ang > 0 else -90))
        elif abs(ang) < 20:
            angs.append(ang)
    if len(angs) < 4:
        return None
    return float(np.median(angs))


def approx_poly_quad(mask: np.ndarray):
    c = largest_contour(mask)
    if c is None:
        return None
    peri = cv2.arcLength(c, True)
    approx = cv2.approxPolyDP(c, 0.02 * peri, True)
    return approx.reshape(-1, 2) if len(approx) == 4 else None


def attack_sharpness(bgr: np.ndarray) -> float:
    h, w = bgr.shape[:2]
    y0, y1 = int(h * 0.58), int(h * 0.68)
    x0, x1 = int(w * 0.2), int(w * 0.8)
    band = bgr[y0:y1, x0:x1]
    if band.size == 0:
        return 0.0
    dx = np.abs(band[:, 1:].astype(np.int16) - band[:, :-1].astype(np.int16)).sum(axis=2)
    return float(dx.mean())


def right_edge_rms(bgr: np.ndarray) -> dict:
    h, w = bgr.shape[:2]
    xs, ys = [], []
    y0, y1 = int(h * 0.2), int(h * 0.8)
    for y in range(y0, y1):
        for x in range(w - 1, max(0, w - 80), -1):
            b, g, r = bgr[y, x]
            luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if luma < 80:
                continue
            if abs(int(r) - 11) + abs(int(g) - 11) + abs(int(b) - 15) < 30:
                continue
            xs.append(x)
            ys.append(y)
            break
    if len(xs) < 16:
        return {"deg": None, "rms": None, "n": len(xs)}
    xs = np.array(xs, dtype=np.float64)
    ys = np.array(ys, dtype=np.float64)
    A = np.vstack([ys, np.ones(len(ys))]).T
    m, c = np.linalg.lstsq(A, xs, rcond=None)[0]
    pred = m * ys + c
    rms = float(np.sqrt(np.mean((xs - pred) ** 2)))
    deg = float(-np.degrees(np.arctan(m)))
    return {"deg": round(deg, 3), "rms": round(rms, 3), "n": int(len(xs))}


def corner_specks(bgr: np.ndarray, depth: int = 40) -> int:
    h, w = bgr.shape[:2]
    n = 0
    for y in range(h):
        for x in range(w):
            if not ((x < depth or x >= w - depth) and (y < depth or y >= h - depth)):
                continue
            b, g, r = bgr[y, x]
            if abs(int(r) - 11) + abs(int(g) - 11) + abs(int(b) - 15) < 30:
                continue
            luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if luma < 200:
                continue
            matte_n = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    bb, gg, rr = bgr[ny, nx]
                    if abs(int(rr) - 11) + abs(int(gg) - 11) + abs(int(bb) - 15) < 30:
                        matte_n += 1
            if matte_n >= 3:
                n += 1
    return n


def rounded_rect_mask(h: int, w: int, radius: int) -> np.ndarray:
    mask = np.zeros((h, w), dtype=np.uint8)
    r = max(1, radius)
    cv2.rectangle(mask, (r, 0), (w - r - 1, h - 1), 255, -1)
    cv2.rectangle(mask, (0, r), (w - 1, h - r - 1), 255, -1)
    for cx, cy in ((r, r), (w - 1 - r, r), (r, h - 1 - r), (w - 1 - r, h - 1 - r)):
        cv2.circle(mask, (cx, cy), r, 255, -1)
    return mask


def flatten_matte(bgr: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    a = (alpha.astype(np.float32) / 255.0)[..., None]
    bg = np.full_like(bgr, MATTE.reshape(1, 1, 3))
    out = (bgr.astype(np.float32) * a + bg.astype(np.float32) * (1 - a)).round()
    return np.clip(out, 0, 255).astype(np.uint8)


def content_box(mask: np.ndarray, margin: int = 2):
    ys, xs = np.where(mask > 0)
    if len(xs) < 16:
        h, w = mask.shape
        return 0, 0, w, h
    left = max(0, int(xs.min()) - margin)
    top = max(0, int(ys.min()) - margin)
    right = min(mask.shape[1], int(xs.max()) + 1 + margin)
    bottom = min(mask.shape[0], int(ys.max()) + 1 + margin)
    return left, top, right - left, bottom - top


def rotate_cv(bgr: np.ndarray, deg: float, flags: int) -> np.ndarray:
    h, w = bgr.shape[:2]
    rad = math.radians(deg)
    cos_a, sin_a = abs(math.cos(rad)), abs(math.sin(rad))
    nw = int(math.ceil(w * cos_a + h * sin_a))
    nh = int(math.ceil(w * sin_a + h * cos_a))
    M = cv2.getRotationMatrix2D((w / 2, h / 2), deg, 1.0)
    M[0, 2] += (nw - w) / 2
    M[1, 2] += (nh - h) / 2
    return cv2.warpAffine(
        bgr,
        M,
        (nw, nh),
        flags=flags,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(int(MATTE[2]), int(MATTE[1]), int(MATTE[0])),
    )


def crop_to_card(bgr: np.ndarray) -> np.ndarray:
    box = content_box(card_mask(bgr), margin=2)
    x, y, w, h = box
    return bgr[y : y + h, x : x + w]


def diecut(bgr: np.ndarray) -> np.ndarray:
    h, w = bgr.shape[:2]
    r = max(1, int(round(min(w, h) * RADIUS_RATIO)))
    alpha = rounded_rect_mask(h, w, r)
    return flatten_matte(bgr, alpha)


def metrics(bgr: np.ndarray, src_sharp: float) -> dict:
    mask = card_mask(bgr)
    inset = inset_side_angles(mask)
    edge = right_edge_rms(bgr)
    sharp = attack_sharpness(bgr)
    return {
        "w": int(bgr.shape[1]),
        "h": int(bgr.shape[0]),
        "minAreaRect": round_or_none(min_area_tilt(mask)),
        "inset_mean": round_or_none(inset["mean"]),
        "inset_right": round_or_none(inset["right"]),
        "bright_edge": round_or_none(theil_sen_bright_edge(bgr)),
        "right_edge": edge,
        "attack_sharp": round(sharp, 2),
        "sharp_vs_src": round(sharp - src_sharp, 2),
        "corner_specks": corner_specks(bgr),
    }


def round_or_none(v, nd=3):
    return None if v is None else round(float(v), nd)


def verdict(m: dict, rotated: bool) -> str:
    # Giuseppe / red-line: bright outer edge, not inset-mean (sides cancel).
    tilt = m.get("bright_edge")
    if tilt is None:
        tilt = (m.get("right_edge") or {}).get("deg")
    if tilt is None:
        tilt = m.get("inset_mean")
    sharp_loss = m.get("sharp_vs_src") or 0
    specks = m.get("corner_specks") or 0
    rms = (m.get("right_edge") or {}).get("rms")
    parts = []
    if tilt is not None and abs(tilt) <= 0.2:
        parts.append("tilt_ok")
    elif tilt is not None and abs(tilt) <= 0.45:
        parts.append("tilt_close")
    else:
        parts.append("tilt_fail")
    if sharp_loss >= -1.5:
        parts.append("interior_ok")
    elif sharp_loss >= -4:
        parts.append("interior_soft")
    else:
        parts.append("interior_fail")
    if specks == 0:
        parts.append("corners_ok")
    else:
        parts.append("corners_specks")
    if rms is not None and rms <= 1.2:
        parts.append("edge_straight")
    elif rms is not None:
        parts.append("edge_wobbly")
    if not rotated:
        parts.append("no_resample")
    return "+".join(parts)


# --- GPU helpers (RX 7900) -------------------------------------------------

DEVICE = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")


def bgr_to_nchw(bgr: np.ndarray) -> torch.Tensor:
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    t = torch.from_numpy(rgb).permute(2, 0, 1).unsqueeze(0)
    return t.to(DEVICE, non_blocking=True)


def nchw_to_bgr(t: torch.Tensor) -> np.ndarray:
    arr = (t.detach().cpu().clamp(0, 1).squeeze(0).permute(1, 2, 0).numpy() * 255.0).round()
    rgb = np.clip(arr, 0, 255).astype(np.uint8)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)


def gpu_rotate(bgr: np.ndarray, deg: float, mode: str) -> np.ndarray:
    t = bgr_to_nchw(bgr)
    rad = math.radians(deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    _, _, h, w = t.shape
    new_w = int(math.ceil(abs(w * cos_a) + abs(h * sin_a)))
    new_h = int(math.ceil(abs(w * sin_a) + abs(h * cos_a)))
    pad_x = max(0, (new_w - w) // 2)
    pad_y = max(0, (new_h - h) // 2)
    pad_xr = max(0, new_w - w - pad_x)
    pad_yb = max(0, new_h - h - pad_y)
    matte = torch.tensor([11 / 255, 11 / 255, 15 / 255], device=DEVICE).view(1, 3, 1, 1)
    canvas = matte.expand(1, 3, new_h, new_w).clone()
    canvas[:, :, pad_y : pad_y + h, pad_x : pad_x + w] = t
    theta = torch.tensor(
        [[cos_a, sin_a, 0.0], [-sin_a, cos_a, 0.0]],
        dtype=torch.float32,
        device=DEVICE,
    ).unsqueeze(0)
    grid = F.affine_grid(theta, size=canvas.size(), align_corners=False)
    out = F.grid_sample(canvas, grid, mode=mode, padding_mode="zeros", align_corners=False)
    mask = (out.abs().sum(dim=1, keepdim=True) < 1e-5)
    out = torch.where(mask, matte.expand_as(out), out)
    return nchw_to_bgr(out)


def gpu_supersample(bgr: np.ndarray, deg: float) -> np.ndarray:
    t = bgr_to_nchw(bgr)
    up = F.interpolate(t, scale_factor=2.0, mode="bilinear", align_corners=False)
    rot = gpu_rotate(nchw_to_bgr(up), deg, "bilinear")
    down = F.interpolate(bgr_to_nchw(rot), scale_factor=0.5, mode="bilinear", align_corners=False)
    return nchw_to_bgr(down)


def run_trial(name: str, cite: str, hypothesis: str, fn, src: np.ndarray, src_sharp: float, rotated: bool) -> dict:
    t0 = time.perf_counter()
    try:
        out = fn(src)
        err = None
    except Exception as e:  # noqa: BLE001 — bake-off must record failures
        return {
            "id": name,
            "cite": cite,
            "hypothesis": hypothesis,
            "ok": False,
            "fail": str(e),
            "ms": round((time.perf_counter() - t0) * 1000, 1),
        }
    ms = (time.perf_counter() - t0) * 1000
    path = OUT / f"{name}.jpg"
    save_jpg(path, out)
    m = metrics(out, src_sharp)
    v = verdict(m, rotated)
    fail_reason = None
    if "tilt_fail" in v or "interior_fail" in v:
        fail_reason = v
    return {
        "id": name,
        "cite": cite,
        "hypothesis": hypothesis,
        "ok": fail_reason is None,
        "verdict": v,
        "fail": fail_reason,
        "ms": round(ms, 1),
        "file": str(path),
        **m,
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    src = load_bgr(SRC)
    src_sharp = attack_sharpness(src)
    save_jpg(OUT / "00-source.jpg", src)

    mask = card_mask(src)
    inset = inset_side_angles(mask)
    min_t = min_area_tilt(mask)
    bright = theil_sen_bright_edge(src)
    hough = hough_tilt(mask)
    quad = approx_poly_quad(mask)

    source_geo = {
        "file": str(SRC),
        "shape": [int(src.shape[1]), int(src.shape[0])],
        "attack_sharp": round(src_sharp, 2),
        "minAreaRect": round_or_none(min_t),
        "inset": {k: round_or_none(v) if k != "n" else v for k, v in inset.items()},
        "bright_edge": round_or_none(bright),
        "hough": round_or_none(hough),
        "approxPolyDP_corners": None if quad is None else int(len(quad)),
        "device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu",
    }

    # Deskew amount. OpenCV getRotationMatrix2D: POSITIVE = CCW.
    # Sharp.rotate: POSITIVE = CW (opposite). Our JS estimators use the Sharp
    # convention (negative = CCW card). First bake-off pass applied -tilt as if
    # we were in Sharp — that rotated the SAME way as the lean. Correct OpenCV
    # undo is rotate(tilt) when tilt is already signed Sharp-style.
    inset_mean = inset["mean"] if inset["mean"] is not None else 0.0
    bright_deg = bright if bright is not None else 0.0
    min_deg = min_t if min_t is not None else 0.0
    hough_deg = hough if hough is not None else 0.0
    vertical_mean = None
    if inset["left"] is not None and inset["right"] is not None:
        vertical_mean = (inset["left"] + inset["right"]) / 2.0

    apply_inset = inset_mean
    apply_vertical = vertical_mean if vertical_mean is not None else inset_mean
    apply_bright = bright_deg
    apply_min = min_deg
    apply_hough = hough_deg

    trials = []

    def add(name, cite, hyp, fn, rotated=True):
        trials.append((name, cite, hyp, fn, rotated))

    add(
        "01-clip-only-rounded-rect",
        "Qwen VL 2026-09-04 + poker 5% die-cut (D00000G). No resample.",
        "If leftover is already ~upright, clip geometric rounded-rect; do not rotate foil.",
        lambda im: diecut(crop_to_card(im)),
        rotated=False,
    )
    add(
        "02-minarearect-linear",
        "OpenCV default warpAffine INTER_LINEAR. StackOverflow 39371507 says this smears.",
        "minAreaRect tilt + bilinear rotate will deskew but blur Inferno X.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_min, cv2.INTER_LINEAR))),
    )
    add(
        "03-minarearect-nearest",
        "SO 39371507 INTER_NEAREST; PyImageSearch notes blocky diagonals.",
        "NN rotate preserves foil/text; stairs on diagonal edges are acceptable vs smear.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_min, cv2.INTER_NEAREST))),
    )
    add(
        "04-minarearect-cubic",
        "OpenCV INTER_CUBIC — common 'high quality' default for photos.",
        "Bicubic still averages neighbors — expect interior smear on gold/black text.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_min, cv2.INTER_CUBIC))),
    )
    add(
        "05-minarearect-lanczos4",
        "OpenCV INTER_LANCZOS4 8x8. Docs: better for zoom; ringing risk on text.",
        "Lanczos may ring around Inferno X on gold.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_min, cv2.INTER_LANCZOS4))),
    )
    add(
        "06-inset18-nearest",
        "AWS Builder Cards DEV.to 2025: ignore 18% corners, LS-fit four sides.",
        "Straight-side fit is the correct tilt for rounded poker cards; NN keeps interior.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_inset, cv2.INTER_NEAREST))),
    )
    add(
        "06b-inset18-vertical-nearest",
        "Builder Cards uses four lines then INTERSECT (quad). Averaging 4 angles cancels. Vertical sides only = red-line.",
        "Mean of left+right inset angles, INTER_NEAREST. Should be closer to bright-edge than 4-side mean.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_vertical, cv2.INTER_NEAREST))),
    )
    add(
        "07-inset18-linear",
        "Same Builder Cards angle, but INTER_LINEAR (control).",
        "Correct angle + wrong interpolator still fails interior.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_inset, cv2.INTER_LINEAR))),
    )
    add(
        "08-bright-edge-nearest",
        "Our JS Theil-Sen bright outer edge (Charizard red-line test).",
        "Matches Giuseppe's visible gold edge better than silhouette; NN rotate.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_bright, cv2.INTER_NEAREST))),
    )
    add(
        "09-hough-nearest",
        "HoughLinesP on Canny of mask. Qwen ranked this worst for foil.",
        "Etched concentric/radial gold lines pollute Hough; angle will be wrong or noisy.",
        lambda im: diecut(crop_to_card(rotate_cv(im, apply_hough, cv2.INTER_NEAREST))),
    )

    def approx_warp(im):
        q = approx_poly_quad(card_mask(im))
        if q is None:
            raise RuntimeError("approxPolyDP did not return 4 corners (rounded card)")
        # order tl,tr,br,bl
        s = q.sum(axis=1)
        d = np.diff(q, axis=1).ravel()
        tl, tr, br, bl = q[np.argmin(s)], q[np.argmin(d)], q[np.argmax(s)], q[np.argmax(d)]
        src_pts = np.array([tl, tr, br, bl], dtype=np.float32)
        h_out, w_out = 1021, 737
        dst = np.array([[0, 0], [w_out - 1, 0], [w_out - 1, h_out - 1], [0, h_out - 1]], dtype=np.float32)
        H = cv2.getPerspectiveTransform(src_pts, dst)
        warped = cv2.warpPerspective(im, H, (w_out, h_out), flags=cv2.INTER_NEAREST)
        return diecut(warped)

    add(
        "10-approx-poly-perspective",
        "SO 76942415 / PyImageSearch card finders: approxPolyDP + warpPerspective.",
        "Rounded corners make approxPolyDP place vertices inside the arc — slices foil.",
        approx_warp,
    )
    add(
        "11-gpu-bilinear",
        "torch grid_sample bilinear on RX 7900 (previous variant A/C).",
        "GPU bilinear ≈ CPU LINEAR — interior smear.",
        lambda im: diecut(crop_to_card(gpu_rotate(im, apply_bright, "bilinear"))),
    )
    add(
        "12-gpu-nearest",
        "torch grid_sample nearest on RX 7900 (previous variant B winner).",
        "NN on GPU should match CPU INTER_NEAREST sharpness.",
        lambda im: diecut(crop_to_card(gpu_rotate(im, apply_bright, "nearest"))),
    )
    add(
        "13-gpu-supersample2x",
        "2x upsample + bilinear rotate + downsample. Common 'quality' trick.",
        "Extra resample footprint — previous test dropped attack sharp 28→18.",
        lambda im: diecut(crop_to_card(gpu_supersample(im, apply_bright))),
    )

    def crop_rot_crop(im):
        box = content_box(card_mask(im), 4)
        x, y, w, h = box
        cropped = im[y : y + h, x : x + w]
        rot = gpu_rotate(cropped, apply_bright, "bilinear")
        return diecut(crop_to_card(rot))

    add(
        "14-gpu-crop-rotate-crop",
        "Crop then rotate (smaller canvas). Previous variant C.",
        "Less pad, still bilinear — interior still soft.",
        crop_rot_crop,
    )
    add(
        "15-zero-rotate-source",
        "Control: metrics on raw ct2 leftover, no die-cut.",
        "Baseline tilt and sharpness before any pipeline.",
        lambda im: im.copy(),
        rotated=False,
    )

    # Serial OpenCV is fast; GPU trials share one device — run GPU after CPU
    # but still use threads for metric-heavy CPU group.
    cpu_ids = {t[0] for t in trials if not t[0].startswith("1") or t[0].startswith("10") or t[0][:2] in {"01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "15"}}
    results = []
    cpu_trials = [t for t in trials if t[0] not in {"11-gpu-bilinear", "12-gpu-nearest", "13-gpu-supersample2x", "14-gpu-crop-rotate-crop"}]
    gpu_trials = [t for t in trials if t[0] in {"11-gpu-bilinear", "12-gpu-nearest", "13-gpu-supersample2x", "14-gpu-crop-rotate-crop"}]

    with ThreadPoolExecutor(max_workers=6) as pool:
        futs = [
            pool.submit(run_trial, name, cite, hyp, fn, src, src_sharp, rot)
            for name, cite, hyp, fn, rot in cpu_trials
        ]
        for fut in futs:
            results.append(fut.result())

    for name, cite, hyp, fn, rot in gpu_trials:
        results.append(run_trial(name, cite, hyp, fn, src, src_sharp, rot))

    results.sort(key=lambda r: r["id"])
    report = {
        "host": "nezopt",
        "gpu": source_geo["device"],
        "source": source_geo,
        "applied_deg": {
            "note": "OpenCV/torch: pass Sharp-signed tilt directly (positive OpenCV = CCW; Sharp positive = CW).",
            "inset18_mean": round(apply_inset, 4),
            "inset18_vertical": round(apply_vertical, 4),
            "bright_edge": round(apply_bright, 4),
            "minAreaRect": round(apply_min, 4),
            "hough": round(apply_hough, 4),
        },
        "literature": [
            "DEV.to AWS Builder Cards: 18% corner inset + four-side line fit (rounded cards).",
            "SO 39371507: INTER_NEAREST to avoid warp smear; LINEAR is default and blurs.",
            "SO 76942415: approxPolyDP fails on rounded TCG corners.",
            "Stackguides 39565584: minAreaRect better than approxPolyDP for round-corner cards.",
            "CollectorVision Cornelius: neural 4-corners then warp to 252x352 — ID crop, not catalog master.",
            "OpenCV docs: warpPerspective only if trapezoid; planar leftover → warpAffine.",
            "Qwen VL 2026-09-04: clip rounded-rect, do not resample face if already near-upright.",
        ],
        "trials": results,
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"source": source_geo, "applied_deg": report["applied_deg"], "n": len(results)}, indent=2))
    for r in results:
        mark = "OK " if r.get("ok") else "FAIL"
        extra = r.get("verdict") or r.get("fail")
        print(f"{mark:4} {r['id']:32} sharp={r.get('attack_sharp')} inset={r.get('inset_mean')} {extra}")


if __name__ == "__main__":
    main()
