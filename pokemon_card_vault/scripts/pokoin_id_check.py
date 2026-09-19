#!/usr/bin/env python3
"""Fast Pokoin catalog id check.

Public identity is card_id only (leftover CardTrader blueprint × 2).
Same idea as Scryfall: never treat arena_id / mtgo_id / tcgplayer_id as the
canonical id. A leftover blueprint number is the CDN image key (`{ct_id}_{slug}`). Desk
addresses stay leftover × 2. `pokoin-id-check` rejects a public-id prefix on
an image URL (Net Ball `245292_net-ball` vs Cyndaquil leftover `245292`).

Examples:
  pokoin-id-check 668126
  pokoin-id-check 334063
  pokoin-id-check /card-images/334063_levincia.jpg
  pokoin-id-check --rebuild-hash4
  pokoin-id-check --audit-urls
  pokoin-id-check --rewrite-urls --apply
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import zlib
from urllib.parse import unquote, urlparse

PREFIX_RE = re.compile(r"(?:^|/)(?:previews/)?(\d+)_([^/?#]+)", re.I)
BARE_ID_RE = re.compile(r"^\d{1,16}$")
SLUG_STRIP_RE = re.compile(r"(_homepage)?\.(?:jpe?g|png|webp)$", re.I)

DEFAULT_CONTAINER = os.environ.get(
    "POKOIN_POSTGRES_CONTAINER", "pokoin-marketplace-postgres-replica"
)
DEFAULT_USER = os.environ.get("POKOIN_POSTGRES_USER", "pokoin_marketplace")
DEFAULT_DB = os.environ.get("POKOIN_POSTGRES_DB", "pokoin_marketplace")


def slugify_name(value: str) -> str:
    text = str(value or "").strip().lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def leftover_image_id(public_id: int | str | None, ct_id: int | str | None = None) -> int | None:
    """CDN object prefix: leftover ct_id. Public id in the filename collides."""
    if ct_id is not None:
        return int(ct_id)
    if public_id is None:
        return None
    value = int(public_id)
    if value <= 0:
        return None
    if value % 2 == 0:
        return value // 2
    return value


def canonical_image_stem(url: str, public_id: int | str | None = None, ct_id: int | str | None = None) -> str:
    """Stable leftover image path the 4-bit hash is computed on. No host, no query."""
    text = unquote(str(url or "").strip())
    if not text:
        return ""
    path = urlparse(text).path if "://" in text else text
    path = path.split("?", 1)[0].split("#", 1)[0]
    if path.startswith("card-images/"):
        path = "/" + path
    elif not path.startswith("/"):
        path = "/card-images/" + path.lstrip("/")
    if not path.startswith("/card-images/"):
        path = "/card-images/" + path.lstrip("/")
    path = re.sub(r"/previews/", "/", path, flags=re.I)
    path = re.sub(r"_homepage(?=\.(?:webp|jpe?g|png)$)", "", path, flags=re.I)
    path = re.sub(r"\.(?:webp|png)$", ".jpg", path, flags=re.I)
    leftover = leftover_image_id(public_id, ct_id)
    if leftover is not None:
        path = re.sub(
            r"(^|/card-images/)(?:previews/)?(\d+)_",
            lambda match: f"{match.group(1)}{leftover}_",
            path,
        )
    return path.lower()


def url_hash4(url: str, public_id: int | str | None = None) -> int:
    """4-bit CRC nibble of the canonical public image URL (0–15)."""
    stem = canonical_image_stem(url, public_id)
    if not stem:
        return 0
    return zlib.crc32(stem.encode("utf-8")) & 0xF


def hash4_matches(stored_hash4, stored_stem: str, url: str, public_id) -> dict:
    stem = canonical_image_stem(url, public_id)
    computed = url_hash4(stem, public_id)
    stored = int(stored_hash4) if stored_hash4 is not None else None
    return {
        "hash4": computed,
        "stored_hash4": stored,
        "url_stem": stem,
        "stored_stem": stored_stem or "",
        "hash4_ok": stored is not None and stored == computed,
        "stem_ok": bool(stored_stem) and stored_stem == stem,
        "matches": bool(stored_stem) and stored_stem == stem and stored == computed,
    }


def parse_token(raw: str) -> dict:
    text = unquote(str(raw or "").strip())
    if not text:
        return {"asked": "", "kind_hint": "empty", "slug": ""}
    match = PREFIX_RE.search(text)
    if match:
        return {
            "asked": match.group(1),
            "kind_hint": "object_key",
            "slug": SLUG_STRIP_RE.sub("", match.group(2)).lower(),
            "source": text,
        }
    path = urlparse(text).path if "://" in text else text
    name = path.rsplit("/", 1)[-1]
    if BARE_ID_RE.match(name):
        return {"asked": name, "kind_hint": "id", "slug": "", "source": text}
    if BARE_ID_RE.match(text):
        return {"asked": text, "kind_hint": "id", "slug": "", "source": text}
    return {"asked": "", "kind_hint": "unknown", "slug": "", "source": text}


def classify_row(asked: int, row: dict | None, slug: str = "", kind_hint: str = "id") -> dict:
    if not row:
        return {
            "asked": asked,
            "kind": "unknown",
            "valid_public": False,
            "matches_card": False,
            "public_id": None,
            "leftover_blueprint": None,
            "name": "",
            "set": "",
            "number": "",
            "use": None,
            "reason": "not in marketplace_search_candidates.card_id or ct_id",
        }
    public_id = int(row["card_id"])
    leftover = int(row["ct_id"]) if row.get("ct_id") is not None else None
    name = str(row.get("name") or "")
    set_name = str(row.get("set_name") or row.get("expansion_name") or "")
    number = str(row.get("card_number") or "")
    name_slug = slugify_name(name)
    slug_ok = True
    if slug:
        slug_ok = slug == name_slug or slug.startswith(name_slug) or name_slug.startswith(slug.split("-")[0])
    leftover_id = leftover if leftover is not None else leftover_image_id(public_id)
    image_key_ok = leftover_id is not None and asked == leftover_id
    if asked == public_id:
        kind = "public"
        valid = True
        reason = "Pokoin card_id"
        if kind_hint == "object_key":
            reason = (
                f"image key uses public_id {public_id}; leftover ct_id is {leftover_id} "
                "(public id collides with other leftover dumps)"
            )
            matches = False
        else:
            matches = bool(slug_ok)
    elif leftover is not None and asked == leftover:
        kind = "leftover_blueprint"
        valid = False
        if kind_hint == "object_key":
            reason = f"leftover image key; desk is public_id {public_id}"
        else:
            reason = f"leftover CardTrader blueprint; use public_id {public_id}"
        matches = bool(slug_ok)
    else:
        kind = "unknown"
        valid = False
        reason = "row did not match asked id"
        matches = False
    return {
        "asked": asked,
        "kind": kind,
        "valid_public": valid,
        "matches_card": matches,
        "image_key_ok": image_key_ok,
        "public_id": public_id,
        "leftover_blueprint": leftover,
        "name": name,
        "set": set_name,
        "number": number,
        "use": public_id,
        "slug_ok": slug_ok,
        "reason": reason if slug_ok or not slug else f"{reason}; slug {slug!r} vs {name_slug!r}",
    }


LOOKUP_SQL = """
SELECT coalesce(json_agg(json_build_object(
  'card_id', card_id,
  'ct_id', ct_id,
  'name', name,
  'set_name', set_name,
  'expansion_name', expansion_name,
  'card_number', card_number,
  'cdn_image_url', cdn_image_url,
  'image_url', image_url,
  'homepage_image_url', homepage_image_url
)), '[]'::json)
FROM public.marketplace_search_candidates
WHERE card_id = {asked} OR ct_id = {asked};
"""

AUDIT_SQL = r"""
SELECT
  count(*) FILTER (
    WHERE cdn_image_url ~ ('(^|/)(previews/)?' || ct_id::text || '_')
       OR image_url ~ ('(^|/)(previews/)?' || ct_id::text || '_')
       OR homepage_image_url ~ ('(^|/)(previews/)?' || ct_id::text || '_')
       OR preview_image_url ~ ('(^|/)(previews/)?' || ct_id::text || '_')
  ) AS leftover_prefix_rows,
  count(*) FILTER (
    WHERE cdn_image_url ~ ('(^|/)(previews/)?' || card_id::text || '_')
       OR image_url ~ ('(^|/)(previews/)?' || card_id::text || '_')
       OR homepage_image_url ~ ('(^|/)(previews/)?' || card_id::text || '_')
  ) AS public_prefix_rows,
  count(*) AS catalog_rows
FROM public.marketplace_search_candidates;
"""

REWRITE_SQL = r"""
SET statement_timeout = 0;
UPDATE public.marketplace_search_candidates AS c
SET
  image_url = CASE
    WHEN c.image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    THEN regexp_replace(c.image_url, '(^|/)(previews/)?' || c.card_id::text || '_', '\1\2' || c.ct_id::text || '_', 'g')
    ELSE c.image_url END,
  cdn_image_url = CASE
    WHEN c.cdn_image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    THEN regexp_replace(c.cdn_image_url, '(^|/)(previews/)?' || c.card_id::text || '_', '\1\2' || c.ct_id::text || '_', 'g')
    ELSE c.cdn_image_url END,
  preview_image_url = CASE
    WHEN c.preview_image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    THEN regexp_replace(c.preview_image_url, '(^|/)(previews/)?' || c.card_id::text || '_', '\1\2' || c.ct_id::text || '_', 'g')
    ELSE c.preview_image_url END,
  homepage_image_url = CASE
    WHEN c.homepage_image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    THEN regexp_replace(c.homepage_image_url, '(^|/)(previews/)?' || c.card_id::text || '_', '\1\2' || c.ct_id::text || '_', 'g')
    ELSE c.homepage_image_url END
WHERE c.ct_id > 0
  AND c.card_id <> c.ct_id
  AND (
    c.image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    OR c.cdn_image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    OR c.preview_image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
    OR c.homepage_image_url ~ ('(^|/)(previews/)?' || c.card_id::text || '_')
  );
"""

HASH4_LOOKUP_SQL = """
SELECT hash4::text, url_stem
FROM public.marketplace_card_url_hash4
WHERE card_id = {card_id}
LIMIT 1;
"""

CATALOG_URL_SQL = r"""
SELECT json_build_object(
  'card_id', card_id,
  'url', coalesce(nullif(cdn_image_url, ''), nullif(image_url, ''), homepage_image_url, '')
)
FROM public.marketplace_search_candidates;
"""


def psql(sql: str, timeout: int = 60, tuples: bool = True) -> str:
    cmd = [
        "docker",
        "exec",
        "-i",
        DEFAULT_CONTAINER,
        "psql",
        "-U",
        DEFAULT_USER,
        "-d",
        DEFAULT_DB,
        "-v",
        "ON_ERROR_STOP=1",
        "-P",
        "pager=off",
    ]
    if tuples:
        cmd.extend(["-At"])
    try:
        raw = subprocess.check_output(cmd, input=sql.encode(), timeout=timeout, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.output.decode() if error.output else str(error))
    except FileNotFoundError:
        raise SystemExit("docker not found; run this on the Pi next to Postgres")
    return raw.decode()


def slug_matches_name(slug: str, name: str) -> bool:
    if not slug:
        return True
    name_slug = slugify_name(name)
    if not name_slug:
        return False
    head = slug.split("-")[0]
    return (
        slug == name_slug
        or slug.startswith(name_slug)
        or name_slug.startswith(head)
        or slug.startswith(name_slug + "-")
    )


def pick_row(rows: list[dict] | None, asked: int, slug: str = "", kind_hint: str = "id") -> dict | None:
    """Public id and leftover ct_id can be the same number. Prefer the row the slug names."""
    if not rows:
        return None
    asked_n = int(asked)
    leftover_hits = [r for r in rows if r.get("ct_id") is not None and int(r["ct_id"]) == asked_n]
    public_hits = [r for r in rows if int(r["card_id"]) == asked_n]
    if kind_hint == "object_key":
        for row in leftover_hits:
            if slug_matches_name(slug, str(row.get("name") or "")):
                return row
        for row in public_hits:
            if slug_matches_name(slug, str(row.get("name") or "")):
                return row
        if leftover_hits:
            return leftover_hits[0]
        if public_hits:
            return public_hits[0]
    if public_hits:
        return public_hits[0]
    if leftover_hits:
        return leftover_hits[0]
    return rows[0]


def lookup(asked: int) -> dict | None:
    rows = lookup_rows(asked)
    return pick_row(rows, asked)


def lookup_rows(asked: int) -> list[dict]:
    sql = LOOKUP_SQL.format(asked=int(asked))
    line = psql(sql).strip().splitlines()
    if not line:
        return []
    try:
        payload = json.loads(line[0])
    except json.JSONDecodeError:
        return []
    return payload if isinstance(payload, list) else [payload]


def check_one(raw: str) -> dict:
    parsed = parse_token(raw)
    if not parsed["asked"]:
        return {
            "asked": raw,
            "kind": "unknown",
            "valid_public": False,
            "matches_card": False,
            "reason": "no numeric Pokoin/CardTrader id in input",
        }
    asked = int(parsed["asked"])
    rows = lookup_rows(asked)
    row = pick_row(rows, asked, parsed.get("slug") or "", parsed.get("kind_hint") or "id")
    result = classify_row(asked, row, parsed.get("slug") or "", parsed.get("kind_hint") or "id")
    result["input"] = raw
    result["kind_hint"] = parsed["kind_hint"]
    if row:
        result["cdn_image_url"] = row.get("cdn_image_url") or ""
        public_id = result.get("use") or result.get("public_id")
        url = result["cdn_image_url"]
        if parsed.get("kind_hint") == "object_key":
            url = parsed.get("source") or url
        stored = lookup_hash4(public_id) if public_id else None
        if stored:
            fingerprint = hash4_matches(stored["hash4"], stored["url_stem"], url, public_id)
            result.update(fingerprint)
        else:
            result["hash4"] = url_hash4(url, public_id) if url else None
            result["hash4_ok"] = None
    return result


def lookup_hash4(card_id) -> dict | None:
    if card_id is None:
        return None
    try:
        line = psql(HASH4_LOOKUP_SQL.format(card_id=int(card_id))).strip().splitlines()
    except SystemExit:
        return None
    if not line or not line[0] or line[0].startswith("ERROR"):
        return None
    parts = line[0].split("|", 1)
    if len(parts) < 2:
        return None
    return {"hash4": int(parts[0]), "url_stem": parts[1]}


def rebuild_hash4() -> dict:
    sql = "SET statement_timeout = 0;\n" + CATALOG_URL_SQL
    lines = [ln for ln in psql(sql, timeout=180).splitlines() if ln.strip().startswith("{")]
    rows = []
    for line in lines:
        row = json.loads(line)
        card_id = int(row["card_id"])
        stem = canonical_image_stem(row.get("url") or "", card_id)
        if not stem:
            continue
        rows.append((card_id, url_hash4(stem, card_id), stem))
    psql("TRUNCATE public.marketplace_card_url_hash4;", tuples=False)
    for offset in range(0, len(rows), 800):
        chunk = rows[offset : offset + 800]
        values = ",".join(
            f"({card_id},{hash4},'{stem.replace(chr(39), chr(39)+chr(39))}')"
            for card_id, hash4, stem in chunk
        )
        psql(
            "INSERT INTO public.marketplace_card_url_hash4 (card_id, hash4, url_stem) "
            f"VALUES {values};",
            timeout=60,
            tuples=False,
        )
    return {"rows": len(rows), "hash_bits": 4}


def audit_urls() -> dict:
    line = psql(AUDIT_SQL).strip().splitlines()[-1]
    leftover, public, total = (int(x) for x in line.split("|"))
    return {
        "catalog_rows": total,
        "leftover_prefix_rows": leftover,
        "public_prefix_rows": public,
        "ok": public == 0,
    }


def rewrite_urls(apply: bool) -> dict:
    before = audit_urls()
    if not apply:
        return {"dry_run": True, **before}
    psql(REWRITE_SQL, timeout=180, tuples=False)
    after = audit_urls()
    return {"dry_run": False, "before": before, "after": after}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tokens", nargs="*", help="public id, leftover blueprint, URL, or filename")
    parser.add_argument("--audit-urls", action="store_true", help="count leftover vs public image prefixes")
    parser.add_argument("--rewrite-urls", action="store_true", help="rewrite public-id image prefixes to leftover ct_id in Postgres")
    parser.add_argument("--apply", action="store_true", help="with --rewrite-urls, write the UPDATE")
    parser.add_argument("--rebuild-hash4", action="store_true", help="rebuild pokoin_id + 4-bit URL hash table")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    reports: list[dict] = []
    if args.rebuild_hash4:
        reports.append({"hash4": rebuild_hash4()})
    if args.audit_urls:
        reports.append({"audit": audit_urls()})
    if args.rewrite_urls:
        reports.append({"rewrite": rewrite_urls(apply=args.apply)})
    for token in args.tokens:
        reports.append(check_one(token))

    if not reports:
        parser.print_help()
        return 2

    if args.json:
        json.dump(reports if len(reports) > 1 else reports[0], sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    for item in reports:
        if "audit" in item:
            a = item["audit"]
            print(
                f"catalog={a['catalog_rows']} public_prefix={a['public_prefix_rows']} "
                f"leftover_prefix={a['leftover_prefix_rows']} ok={a['ok']}"
            )
            continue
        if "rewrite" in item:
            print(json.dumps(item["rewrite"], indent=2))
            continue
        if "hash4" in item and "asked" not in item:
            print(json.dumps(item["hash4"], indent=2))
            continue
        mark = "OK" if item.get("valid_public") else "NO"
        if item.get("kind_hint") == "object_key":
            mark = "OK" if item.get("image_key_ok") else "NO"
        extra = ""
        if item.get("hash4") is not None:
            extra = f" hash4={item.get('hash4')}/16 stored={item.get('stored_hash4')}"
        print(
            f"{mark} asked={item.get('asked')} kind={item.get('kind')} "
            f"use={item.get('use')} {item.get('name') or ''} "
            f"({item.get('set') or ''} {item.get('number') or ''}){extra} — {item.get('reason')}"
        )
    leftover_fail = any(
        item.get("kind") == "unknown"
        or (item.get("kind") == "leftover_blueprint" and item.get("kind_hint") != "object_key")
        or (item.get("kind_hint") == "object_key" and item.get("image_key_ok") is False)
        for item in reports
        if "asked" in item
    )
    audit_fail = any(item.get("audit", {}).get("ok") is False for item in reports)
    return 1 if leftover_fail or audit_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
