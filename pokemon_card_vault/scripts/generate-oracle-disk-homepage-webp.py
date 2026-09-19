#!/usr/bin/env python3
"""Create 240px _homepage.webp siblings next to catalog JPEGs on the Oracle CDN disk.

Catalog masters are already sanitized JPEGs. Homepage tiles are a lossy 240px
WebP derivative (same recipe as generate-oracle-homepage-card-images.js).
"""
from __future__ import annotations

import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

from PIL import Image

ROOT = os.environ.get("POKOIN_CDN_ROOT", "/home/ubuntu/pokoin-cdn")
REF = int(os.environ.get("HOMEPAGE_IMAGE_REFERENCE_WIDTH", "240"))
QUALITY = int(os.environ.get("HOMEPAGE_IMAGE_QUALITY", "82"))
WORKERS = int(os.environ.get("HOMEPAGE_WORKERS", "4"))
LOG = os.environ.get("HOMEPAGE_LOG", "/tmp/homepage-generated.txt")
SKIP_DIRS = {"originals", "manifests"}


def sibling_path(jpg_path: str) -> str:
    base, ext = os.path.splitext(jpg_path)
    return f"{base}_homepage.webp"


def convert_one(jpg_path: str) -> tuple[str, str, int]:
    dest = sibling_path(jpg_path)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return ("exists", dest, 0)
    try:
        with Image.open(jpg_path) as im:
            im = im.convert("RGB")
            width, height = im.size
            if width > REF:
                height = max(1, round(height * REF / width))
                im = im.resize((REF, height), Image.LANCZOS)
            im.save(dest, "WEBP", quality=QUALITY, method=6)
        return ("created", dest, os.path.getsize(dest))
    except Exception as exc:  # noqa: BLE001
        return ("error", f"{jpg_path}: {exc}", 0)


def iter_missing() -> list[str]:
    missing: list[str] = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel = os.path.relpath(dirpath, ROOT)
        top = rel.split(os.sep, 1)[0]
        if top in SKIP_DIRS:
            dirnames[:] = []
            continue
        names = set(filenames)
        for name in filenames:
            lower = name.lower()
            if not lower.endswith((".jpg", ".jpeg")):
                continue
            if sibling_path(name) in names or os.path.splitext(name)[0] + "_homepage.webp" in names:
                continue
            missing.append(os.path.join(dirpath, name))
    return missing


def main() -> int:
    started = time.time()
    jobs = iter_missing()
    print(f"missing={len(jobs)} root={ROOT} workers={WORKERS} ref={REF}q={QUALITY}", flush=True)
    created = exists = errors = 0
    with open(LOG, "a", encoding="utf-8") as log:
        if not jobs:
            print("nothing to do", flush=True)
            return 0
        with ProcessPoolExecutor(max_workers=WORKERS) as pool:
            done = 0
            chunk_size = max(32, WORKERS * 16)
            for start in range(0, len(jobs), chunk_size):
                chunk = jobs[start:start + chunk_size]
                futures = [pool.submit(convert_one, path) for path in chunk]
                for fut in as_completed(futures):
                    action, detail, size = fut.result()
                    done += 1
                    if action == "created":
                        created += 1
                        rel = os.path.relpath(detail, ROOT)
                        log.write(rel + "\n")
                        if created % 200 == 0:
                            log.flush()
                    elif action == "exists":
                        exists += 1
                    else:
                        errors += 1
                        print(detail, file=sys.stderr, flush=True)
                    if done % 500 == 0:
                        print(
                            f"progress {done}/{len(jobs)} created={created} exists={exists} errors={errors}",
                            flush=True,
                        )
    print(
        {
            "created": created,
            "exists": exists,
            "errors": errors,
            "seconds": round(time.time() - started, 1),
            "log": LOG,
        },
        flush=True,
    )
    return 0 if errors == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
