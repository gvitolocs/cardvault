#!/usr/bin/env python3
"""GPU affine rotate helpers for Charizard deskew variants (ROCm torch).

Reads a JPEG/PNG path, writes rotated PNGs for each variant.
Uses AMD GPU (device 0) — no CardTrader download.

Variants:
  supersample  — 2× upsample → rotate (bilinear) → 0.5× downsample
  mask_nn      — nearest RGB rotate + bilinear alpha (preserves text pixels)
  crop_rotate  — tight matte crop → rotate → recrop content
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import torch
import torch.nn.functional as F
from PIL import Image
import numpy as np


MATTE = np.array([11, 11, 15], dtype=np.float32)


def load_rgba(path: Path) -> tuple[torch.Tensor, dict]:
    """Return float tensor NCHW on CPU, values 0..1, 4 channels."""
    img = Image.open(path).convert("RGBA")
    arr = np.asarray(img).astype(np.float32) / 255.0
    t = torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).contiguous()
    return t, {"width": img.width, "height": img.height}


def save_rgba(t: torch.Tensor, path: Path) -> None:
    t = t.detach().cpu().clamp(0, 1)
    arr = (t.squeeze(0).permute(1, 2, 0).numpy() * 255.0).round().astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path, optimize=True)


def affine_rotate(t: torch.Tensor, deg: float, mode: str, device: torch.device) -> torch.Tensor:
    """Rotate NCHW tensor by deg (CCW positive, matching sharp rotate)."""
    t = t.to(device, non_blocking=True)
    rad = math.radians(deg)
    cos_a = math.cos(rad)
    sin_a = math.sin(rad)
    # Expand canvas so corners fit.
    _, _, h, w = t.shape
    new_w = int(math.ceil(abs(w * cos_a) + abs(h * sin_a)))
    new_h = int(math.ceil(abs(w * sin_a) + abs(h * cos_a)))
    # Pad to new size centered.
    pad_x = max(0, (new_w - w) // 2)
    pad_y = max(0, (new_h - h) // 2)
    pad_xr = max(0, new_w - w - pad_x)
    pad_yb = max(0, new_h - h - pad_y)
    # Fill matte in RGB, alpha 0 outside.
    matte = torch.tensor([MATTE[0] / 255.0, MATTE[1] / 255.0, MATTE[2] / 255.0, 0.0], device=device).view(
        1, 4, 1, 1
    )
    canvas = matte.expand(1, 4, new_h, new_w).clone()
    canvas[:, :, pad_y : pad_y + h, pad_x : pad_x + w] = t

    # torchvision-style affine: theta maps output→input.
    # For rotation by +deg (CCW) around center:
    theta = torch.tensor(
        [[cos_a, sin_a, 0.0], [-sin_a, cos_a, 0.0]],
        dtype=torch.float32,
        device=device,
    ).unsqueeze(0)
    grid = F.affine_grid(theta, size=canvas.size(), align_corners=False)
    out = F.grid_sample(
        canvas,
        grid,
        mode=mode,
        padding_mode="zeros",
        align_corners=False,
    )
    # Flatten transparent pad onto catalog matte (opaque JPEG path).
    alpha = out[:, 3:4]
    rgb = out[:, 0:3]
    matte_rgb = matte[:, 0:3]
    mask = alpha < 0.08
    rgb = torch.where(mask, matte_rgb.expand_as(rgb), rgb)
    alpha = torch.ones_like(alpha)
    return torch.cat([rgb, alpha], dim=1)


def content_box(t: torch.Tensor, margin: int = 2) -> tuple[int, int, int, int]:
    """AABB of non-matte pixels. Returns left, top, width, height."""
    arr = t.squeeze(0).permute(1, 2, 0).cpu().numpy()
    rgb = arr[:, :, :3] * 255.0
    dist = np.abs(rgb - MATTE).sum(axis=2)
    mask = dist > 40
    ys, xs = np.where(mask)
    if len(xs) < 16:
        h, w = arr.shape[:2]
        return 0, 0, w, h
    left = max(0, int(xs.min()) - margin)
    top = max(0, int(ys.min()) - margin)
    right = min(arr.shape[1], int(xs.max()) + 1 + margin)
    bottom = min(arr.shape[0], int(ys.max()) + 1 + margin)
    return left, top, right - left, bottom - top


def crop(t: torch.Tensor, box: tuple[int, int, int, int]) -> torch.Tensor:
    left, top, width, height = box
    return t[:, :, top : top + height, left : left + width].contiguous()


def variant_supersample(t: torch.Tensor, deg: float, device: torch.device) -> torch.Tensor:
    up = F.interpolate(t, scale_factor=2.0, mode="bilinear", align_corners=False)
    rot = affine_rotate(up, deg, mode="bilinear", device=device)
    down = F.interpolate(rot, scale_factor=0.5, mode="bilinear", align_corners=False)
    return down


def variant_mask_nn(t: torch.Tensor, deg: float, device: torch.device) -> torch.Tensor:
    # Nearest RGB for interior text; bilinear alpha for smoother silhouette.
    rgb = t[:, 0:3]
    alpha = t[:, 3:4]
    rgba_nn = torch.cat([rgb, alpha], dim=1)
    rot_nn = affine_rotate(rgba_nn, deg, mode="nearest", device=device)
    rot_bi = affine_rotate(t, deg, mode="bilinear", device=device)
    # Keep NN RGB, use bilinear alpha as soft edge hint then harden.
    out_rgb = rot_nn[:, 0:3]
    out_a = rot_bi[:, 3:4]
    matte = torch.tensor([MATTE[0] / 255.0, MATTE[1] / 255.0, MATTE[2] / 255.0], device=device).view(
        1, 3, 1, 1
    )
    out_rgb = torch.where(out_a < 0.35, matte.expand_as(out_rgb), out_rgb)
    out_a = torch.ones_like(out_a)
    return torch.cat([out_rgb, out_a], dim=1)


def variant_crop_rotate(t: torch.Tensor, deg: float, device: torch.device) -> torch.Tensor:
    box = content_box(t, margin=4)
    cropped = crop(t, box)
    rot = affine_rotate(cropped, deg, mode="bilinear", device=device)
    box2 = content_box(rot, margin=2)
    return crop(rot, box2)


def run_one(name: str, fn, t: torch.Tensor, deg: float, device: torch.device, out: Path) -> dict:
    torch.cuda.synchronize(device)
    t0 = torch.cuda.Event(enable_timing=True)
    t1 = torch.cuda.Event(enable_timing=True)
    t0.record()
    result = fn(t, deg, device)
    t1.record()
    torch.cuda.synchronize(device)
    ms = t0.elapsed_time(t1)
    save_rgba(result, out)
    _, _, h, w = result.shape
    return {"variant": name, "width": w, "height": h, "gpu_ms": round(ms, 1), "out": str(out)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--deg", type=float, required=True, help="sharp-compatible rotate degrees (applied)")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--device", type=int, default=0)
    ap.add_argument(
        "--only",
        choices=["supersample", "mask_nn", "crop_rotate"],
        default=None,
        help="Run a single variant (for correction passes)",
    )
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    device = torch.device(f"cuda:{args.device}")

    t, meta = load_rgba(Path(args.input))
    all_jobs = [
        ("supersample", variant_supersample, outdir / "variant-supersample.png"),
        ("mask_nn", variant_mask_nn, outdir / "variant-mask-nn.png"),
        ("crop_rotate", variant_crop_rotate, outdir / "variant-crop-rotate.png"),
    ]
    jobs = [j for j in all_jobs if args.only is None or j[0] == args.only]

    results = []
    # Parallel on GPU via threads — CUDA ops release GIL.
    with ThreadPoolExecutor(max_workers=3) as pool:
        futs = [
            pool.submit(run_one, name, fn, t.clone(), args.deg, device, path)
            for name, fn, path in jobs
        ]
        for fut in futs:
            results.append(fut.result())

    summary = {
        "input": str(args.input),
        "deg": args.deg,
        "device": torch.cuda.get_device_name(args.device),
        "source": meta,
        "variants": results,
    }
    (outdir / "gpu-variants.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
