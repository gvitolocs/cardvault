#!/usr/bin/env python3
"""One-shot patches for Pi rails + public ids. Run on nezopt then copy API to Pi."""
from pathlib import Path

CARDVAULT = Path("/home/nez/Projects/cardvault/pokemon_card_vault")
WEB = Path("/home/nez/Projects/pokoin-web")


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text and old not in text:
        print(f"skip {label}: already patched")
        return
    if old not in text:
        raise SystemExit(f"missing patch site: {label} in {path}")
    path.write_text(text.replace(old, new, 1))
    print(f"patched {label}")


def patch_manifest():
    path = CARDVAULT / "server/api-route-manifest.js"
    needle = """  {
    path: '/api/marketplace-home-page',
    file: 'marketplace-home-page.js',"""
    insert = """  {
    path: '/api/marketplace-rails',
    file: 'marketplace-rails.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Pi browse rails (replaces Supabase marketplace_rails). Public card_id only.',
    auth: 'Public.',
    params: { query: '`id` rail id (`new_cards`, `set:destined-rivals`) or `ids` for tiles.' },
    dependencies: { env: ['MARKETPLACE_DATABASE_URL'], services: ['Pi Postgres'] },
  },
  {
    path: '/api/marketplace-card-tiles',
    file: 'marketplace-card-tiles.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Pi card tiles by public id. Replaces Supabase marketplace_card_tiles.',
    auth: 'Public.',
    params: { query: '`ids` comma-separated public card ids.' },
    dependencies: { env: ['MARKETPLACE_DATABASE_URL'], services: ['Pi Postgres'] },
  },
  {
    path: '/api/marketplace-home-page',
    file: 'marketplace-home-page.js',"""
    replace_once(path, needle, insert, "api-route-manifest")


def patch_home_page():
    path = CARDVAULT / "api/marketplace-home-page.js"
    old = """async function defaultLoadHomeSnapshot({ limit = 36 } = {}) {
  const cacheKey = valkeyKey(SNAPSHOT_KEY);
  const cached = await valkey.getJson(cacheKey);
  if (cached?.cards?.length) {
    return cached;
  }"""
    new = """async function defaultLoadHomeSnapshot({ limit = 36 } = {}) {
  const cacheKey = valkeyKey(SNAPSHOT_KEY);
  const cached = await valkey.getJson(cacheKey);
  if (cached?.cards?.length) {
    return cached;
  }
  try {
    const { readRails, assembleHomeVector, HOME_RAILS } = require('./_marketplace_rails');
    const rows = await readRails(HOME_RAILS.map((row) => row[0]));
    if (rows.length) {
      const fromRails = assembleHomeVector(rows);
      if ((fromRails.cards || []).length) {
        await valkey.setJson(cacheKey, fromRails, isPokemonGame() ? SNAPSHOT_TTL_SEC : 60);
        return fromRails;
      }
    }
  } catch (_) {
    /* newest/hot SQL fallback */
  }"""
    replace_once(path, old, new, "marketplace-home-page rails")


def patch_lists():
    path = WEB / "market/src/lists.js"
    old = """export function listsConfigured() {
  return Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
}"""
    new = """export function listsConfigured() {
  return true;
}"""
    replace_once(path, old, new, "listsConfigured")

    old = """  if (payload.source === 'supabase') {
    return true;
  }"""
    new = """  if (payload.source === 'pi' || payload.source === 'supabase') {
    return true;
  }"""
    replace_once(path, old, new, "isPublicRailsVector")

    old = """export async function fetchRail(id) {
  if (!listsConfigured() || !id) {
    return null;
  }
  const rows = await rest(
    `marketplace_rails?id=eq.${encodeURIComponent(id)}&select=id,cards,meta,updated_at`,
  );
  const row = rows?.[0];
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    cards: asCards(row.cards),
    meta: row.meta && typeof row.meta === 'object' ? row.meta : {},
    updatedAt: row.updated_at || '',
  };
}"""
    new = """export async function fetchRail(id) {
  if (!id) {
    return null;
  }
  const response = await fetch(`/api/marketplace-rails?id=${encodeURIComponent(id)}`, {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    return null;
  }
  const row = await response.json();
  if (!row?.id) {
    return null;
  }
  return {
    id: row.id,
    cards: asCards(row.cards),
    meta: row.meta && typeof row.meta === 'object' ? row.meta : {},
    updatedAt: row.updated_at || '',
  };
}"""
    replace_once(path, old, new, "fetchRail")


def patch_worker():
    path = WEB / "workers/marketplace-home.js"
    text = path.read_text()
    text = text.replace("source: 'supabase'", "source: 'pi'")
    old = """async function supabaseGet(env, path) {
  const base = String(env.SUPABASE_URL || 'https://ruvtchmbtxvjqmquobij.supabase.co').replace(/\\/$/, '');
  const key = String(env.SUPABASE_ANON_KEY || '');
  if (!key) {
    throw new Error('missing supabase anon key');
  }
  const response = await fetch(`${base}/rest/v1/${path}`, {
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      Accept: 'application/json',
    },
  });
  if (!response.ok) {
    throw new Error(`supabase ${response.status}`);
  }
  return response.json();
}

async function buildHome(env) {
  const ids = HOME_RAILS.map((row) => row[0]).join(',');
  const rows = await supabaseGet(
    env,
    `marketplace_rails?id=in.(${ids})&select=id,cards,meta,updated_at`,
  );
  const vector = assembleHomeVector(rows);
  if (!vector.cards.length) {
    throw new Error('empty home vector');
  }
  return vector;
}

async function buildTiles(env, ids) {
  if (!ids.length) {
    return { cards: [] };
  }
  const rows = await supabaseGet(
    env,
    `marketplace_card_tiles?card_id=in.(${ids.join(',')})&select=card_id,payload`,
  );
  const cards = (rows || [])
    .map((row) => applyTilePrice(row?.payload || {}))
    .filter((card) => cardId(card));
  return { source: 'supabase', cards };
}"""
    new = """const PI_API = 'https://api.pokoin.com';

async function piGet(path) {
  const response = await fetch(`${PI_API}${path}`, {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`pi ${response.status}`);
  }
  return response.json();
}

async function buildHome(env) {
  const body = await piGet('/api/marketplace-home-page?limit=48');
  if (!body?.cards?.length) {
    throw new Error('empty home vector');
  }
  return { ...body, source: 'pi', cacheTtl: HOME_CACHE_TTL_SEC };
}

async function buildTiles(env, ids) {
  if (!ids.length) {
    return { cards: [] };
  }
  const body = await piGet(`/api/marketplace-card-tiles?ids=${ids.join(',')}`);
  return { source: 'pi', cards: Array.isArray(body?.cards) ? body.cards : [] };
}"""
    if "const PI_API" in text:
        print("skip worker supabase: already pi")
    elif old not in text:
        # source already replaced may have broken the old needle
        text2 = path.read_text().replace("source: 'supabase'", "source: 'pi'")
        if old.replace("source: 'supabase'", "source: 'pi'") in text2:
            path.write_text(text2.replace(old.replace("source: 'supabase'", "source: 'pi'"), new, 1))
            print("patched worker (after source rename)")
            return
        raise SystemExit("missing worker supabaseGet block")
    else:
        path.write_text(text.replace(old, new, 1))
        print("patched worker")
        return
    path.write_text(text)

    old_ver = """async function railsVersion(env) {
  const ids = HOME_RAILS.map((row) => row[0]).join(',');
  const rows = await supabaseGet(
    env,
    `marketplace_rails?select=updated_at&id=in.(${ids})&order=updated_at.desc&limit=1`,
  );
  return String(rows?.[0]?.updated_at || '0');
}"""
    new_ver = """async function railsVersion(env) {
  const body = await piGet('/api/marketplace-home-page?limit=1');
  return String(body?.updatedAt || body?.generatedAt || '0');
}"""
    if "async function railsVersion" in path.read_text() and "supabaseGet" in path.read_text():
        replace_once(path, old_ver, new_ver, "railsVersion")
    elif "piGet('/api/marketplace-home-page?limit=1')" in path.read_text():
        print("skip railsVersion")
    else:
        # try after source rename
        if old_ver in path.read_text():
            replace_once(path, old_ver, new_ver, "railsVersion")


def patch_worker_test():
    path = WEB / "workers/marketplace-home.test.mjs"
    text = path.read_text().replace("vector.source, 'supabase'", "vector.source, 'pi'")
    text = text.replace("from Supabase rails", "from Pi rails")
    path.write_text(text)
    print("patched worker test")


if __name__ == "__main__":
    patch_manifest()
    patch_home_page()
    patch_lists()
    patch_worker()
    patch_worker_test()
    print("nezopt patches done")
