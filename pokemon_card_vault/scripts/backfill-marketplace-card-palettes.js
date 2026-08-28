#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

const POKEMON_TO_PALETTE = {
  bug: 'grass',
  dark: 'darkness',
  dragon: 'dragon',
  electric: 'lightning',
  fairy: 'fairy',
  fighting: 'fighting',
  fire: 'fire',
  flying: 'colorless',
  ghost: 'psychic',
  grass: 'grass',
  ground: 'fighting',
  ice: 'water',
  normal: 'colorless',
  poison: 'psychic',
  psychic: 'psychic',
  rock: 'fighting',
  steel: 'metal',
  water: 'water',
};

const TYPE_PRIORITY = [
  'fire',
  'water',
  'lightning',
  'grass',
  'fighting',
  'darkness',
  'metal',
  'psychic',
  'fairy',
  'dragon',
  'colorless',
];

function addType(index, key, pokemonType) {
  if (!key) return;
  const existing = index.get(key) || [];
  if (!existing.includes(pokemonType)) existing.push(pokemonType);
  index.set(key, existing);
}

const TRAINER_RULES = [
  ['energy', /\b(energy|energie|energia)\b/i],
  ['stadium', /\b(stadium|gym|tower|city|court|arena|lab|laboratory|factory|festival|dojo|mine|cave|forest|mountain|beach|park|ruins|shrine|temple|lake|valley|spring|plaza|school|house|castle|center)\b/i],
  ['supporter', /\b(professor|prof\.|boss|judge|worker|research|researcher|lady|lass|boy|girl|man|woman|mom|dad|fan club|breeder|collector|fisherman|hiker|ranger|scientist|engineer|nurse|teammates|friends|clerk|student|biker|karate|black belt|beauty|gentleman|idol|artist|camper|picnicker|sisters|siblings|mentor|guidance|adventurer|explorer|merchant|backpacker|ace trainer|team|rocket|galactic|plasma|flare|skull|yell|aqua|magma|cipher|rocket's admin|giovanni|misty|brock|erika|sabrina|koga|blaine|lance|cynthia|iris|n|lillie|marnie|hop|iono|nemona|arven|penny|clavell|jacq|iono|diantha|colress|guzma|lusamine|gladion|hau|acerola|mallow|lana|kiawe|gordie|melony|raihan|leon|cheren|irida|skyla|carmine|kieran|klara|roxanne|gardenia|steven|tv reporter)\b/i],
  ['item', /\b(ball|switch|candy|potion|rod|catcher|search|seeker|stretcher|vacuum|treasure|medal|gain|pad|receiver|communicator|communication|mail|ticket|map|pokedex|pokédex|gear|tool|belt|band|stone|fossil|incense|rope|flute|lantern|capsule|patch|shoes|bike|bicycle|gloves|helmet|vest|cape|charm|amulet|scoop|net|recycler|blower|compressor|machine|device|transceiver|computer|phone|tablet|camera|spray|powder|herb|berry|candy|elixir|crystal|vessel|container|badge|pass|letter|coin|whistle|doll|bomb|hammer|shovel|pickaxe|mirror|scope|radar|scanner|rescue|revive|max potion|full heal|rare candy|ultra ball|great ball|pok[eé] ball)\b/i],
];

const PRODUCT_LIKE = /\b(collector chest|trainer kit|deck|box|bundle|collection|booster|pack|sleeve|binder|playmat|tin|case|display|portfolio|album|poster|figure|pin|coin|dice|mat|merchandise|product)\b/i;

const VARIANT_WORDS = new Set([
  'alolan',
  'ancient',
  'armored',
  'ash',
  'baby',
  'black',
  'break',
  'brilliant',
  'crystal',
  'dark',
  'delta',
  'ex',
  'full',
  'galarian',
  'gold',
  'golden',
  'great',
  'hisuian',
  'light',
  'lost',
  'm',
  'mega',
  'paldean',
  'primal',
  'radiant',
  'rainbow',
  'rapid',
  'rocket',
  'shining',
  'shiny',
  'single',
  'star',
  'team',
  'tera',
  'white',
]);

const FORM_SUFFIXES = [
  'ash',
  'baile',
  'black',
  'blade',
  'complete',
  'amped',
  'confined',
  'curly',
  'dawn wings',
  'disguised',
  'dusk mane',
  'droopy',
  'east',
  'eternamax',
  'female',
  'fifty',
  'full belly',
  'galar standard',
  'hero',
  'incarnate',
  'land',
  'low key',
  'male',
  'midday',
  'midnight',
  'ordinary',
  'normal',
  'origin',
  'pau',
  'pom pom',
  'red striped',
  'resolute',
  'school',
  'sensu',
  'shield',
  'sky',
  'small',
  'solo',
  'standard',
  'step',
  'super',
  'therian',
  'three segment',
  'unbound',
  'west',
  'white',
];

const MANUAL_NAME_TYPES = new Map([
  ['Air Balloon', 'item'],
  ['Aqua Patch', 'item'],
  ['Ball Guy', 'supporter'],
  ['Battle Compressor', 'item'],
  ['Battle Compressor Team Flare Gear', 'item'],
  ['Battle VIP Pass', 'item'],
  ["Bebe's Search", 'supporter'],
  ['Buddy-Buddy Poffin', 'item'],
  ['Copycat', 'supporter'],
  ['Cynthia', 'lightning'],
  ['Exp. Share', 'item'],
  ['No. 1 Trainer', 'supporter'],
  ['Piers', 'supporter'],
  ['PlusPower', 'item'],
  ['Pokemon Communication', 'item'],
  ['Pokémon Communication', 'item'],
  ['Shauna', 'supporter'],
  ['Tropical Tidal Wave', 'stadium'],
  ['Tropical Wind', 'stadium'],
  ['Volkner', 'supporter'],
  ['Welder', 'supporter'],
  ['Warp Point', 'item'],
]);

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const [key, inlineValue] = token.slice(2).split('=', 2);
    if (inlineValue !== undefined) {
      args.set(key, inlineValue);
    } else if (argv[index + 1] && !argv[index + 1].startsWith('--')) {
      args.set(key, argv[index + 1]);
      index += 1;
    } else {
      args.set(key, true);
    }
  }
  return args;
}

function readEnv(filePath) {
  const values = {};
  if (!filePath || !fs.existsSync(filePath)) return values;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return values;
}

function createPool(env) {
  if (env.MARKETPLACE_DATABASE_URL) {
    return new Pool({
      connectionString: env.MARKETPLACE_DATABASE_URL,
      ssl: { rejectUnauthorized: false },
      max: 2,
    });
  }
  for (const key of [
    'MARKETPLACE_DB_PUBLIC_HOST',
    'MARKETPLACE_DB_USER',
    'MARKETPLACE_DB_PASSWORD',
    'MARKETPLACE_DB_NAME',
  ]) {
    if (!env[key]) throw new Error(`Missing ${key}`);
  }
  return new Pool({
    host: env.MARKETPLACE_DB_PUBLIC_HOST,
    port: Number(env.MARKETPLACE_DB_PORT || 5432),
    database: env.MARKETPLACE_DB_NAME,
    user: env.MARKETPLACE_DB_USER,
    password: env.MARKETPLACE_DB_PASSWORD,
    ssl: { rejectUnauthorized: false },
    max: 2,
  });
}

function normalizeText(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, '')
    .toLowerCase()
    .replace(/♀/g, ' female ')
    .replace(/♂/g, ' male ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function pokemonNameCandidates(name) {
  const normalized = normalizeText(name)
    .replace(/\b(delta species|owner s pokemon|pokemon)\b/g, ' ')
    .replace(/\b(ex|gx|vmax|vstar|lv x|prime|break|star)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const tokens = normalized.split(' ').filter(Boolean);
  const candidates = new Set([normalized]);
  for (let start = 0; start < tokens.length; start += 1) {
    for (let end = tokens.length; end > start; end -= 1) {
      const slice = tokens.slice(start, end);
      while (slice.length > 1 && VARIANT_WORDS.has(slice[0])) {
        slice.shift();
      }
      if (slice.length > 0) candidates.add(slice.join(' '));
    }
  }
  return [...candidates].sort((a, b) => b.length - a.length);
}

function paletteFromPokemonTypes(types) {
  const palettes = types.map((type) => POKEMON_TO_PALETTE[type]).filter(Boolean);
  if (palettes.length === 0) return '';
  return palettes.sort(
    (a, b) => TYPE_PRIORITY.indexOf(a) - TYPE_PRIORITY.indexOf(b),
  )[0];
}

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${url} failed ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function fetchOptionalJson(url) {
  const response = await fetch(url);
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`${url} failed ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

function regionalAlias(key) {
  const match = key.match(/^(.+) (alola|galar|hisui|paldea)$/);
  if (!match) return '';
  const adjective = {
    alola: 'alolan',
    galar: 'galarian',
    hisui: 'hisuian',
    paldea: 'paldean',
  }[match[2]];
  return `${adjective} ${match[1]}`;
}

function baseFormAlias(key) {
  for (const suffix of FORM_SUFFIXES) {
    if (key.endsWith(` ${suffix}`)) {
      return key.slice(0, -suffix.length).trim();
    }
  }
  if (key.endsWith(' 50')) return key.slice(0, -3).trim();
  if (key.endsWith(' 10')) return key.slice(0, -3).trim();
  return '';
}

async function loadPokemonPaletteIndex() {
  const exact = new Map();
  const aliases = new Map();
  for (const pokemonType of Object.keys(POKEMON_TO_PALETTE)) {
    const data = await fetchJson(`https://pokeapi.co/api/v2/type/${pokemonType}`);
    for (const entry of data.pokemon || []) {
      const rawName = entry.pokemon?.name;
      if (!rawName) continue;
      const key = normalizeText(rawName);
      addType(exact, key, pokemonType);
      const alias = regionalAlias(key);
      if (alias) addType(aliases, alias, pokemonType);
      const baseAlias = baseFormAlias(key);
      if (baseAlias && !exact.has(baseAlias)) addType(aliases, baseAlias, pokemonType);
      if (key === 'nidoran m') addType(aliases, 'nidoran male', pokemonType);
      if (key === 'nidoran f') addType(aliases, 'nidoran female', pokemonType);
    }
  }
  const exactPalettes = new Map(
    [...exact.entries()].map(([name, types]) => [
      name,
      paletteFromPokemonTypes(types),
    ]),
  );
  const aliasPalettes = new Map(
    [...aliases.entries()].map(([name, types]) => [
      name,
      paletteFromPokemonTypes(types),
    ]),
  );
  return { exact: exactPalettes, aliases: aliasPalettes };
}

function classifyTrainer(name) {
  const manualType = MANUAL_NAME_TYPES.get(name);
  if (manualType) return { typeKey: manualType, source: 'palette-backfill-manual' };
  if (PRODUCT_LIKE.test(name)) return null;
  for (const [typeKey, pattern] of TRAINER_RULES) {
    if (pattern.test(name)) return { typeKey, source: 'palette-backfill-trainer' };
  }
  return null;
}

function classifyPokemon(name, pokemonIndex) {
  for (const candidate of pokemonNameCandidates(name)) {
    const typeKey = pokemonIndex.exact.get(candidate);
    if (typeKey) {
      return { typeKey, source: 'palette-backfill-pokeapi', matchedName: candidate };
    }
  }
  for (const candidate of pokemonNameCandidates(name)) {
    const typeKey = pokemonIndex.aliases.get(candidate);
    if (typeKey) {
      return { typeKey, source: 'palette-backfill-pokeapi', matchedName: candidate };
    }
  }
  return null;
}

async function classifyPokemonFromApi(name) {
  for (const candidate of pokemonNameCandidates(name)) {
    if (!/[a-z]/.test(candidate) || /^\d+$/.test(candidate)) continue;
    const slug = candidate.replace(/\s+/g, '-');
    const data = await fetchOptionalJson(`https://pokeapi.co/api/v2/pokemon/${encodeURIComponent(slug)}`);
    if (!data) continue;
    const types = (data.types || [])
      .map((entry) => entry.type?.name)
      .filter(Boolean);
    const typeKey = paletteFromPokemonTypes(types);
    if (typeKey) {
      return {
        typeKey,
        source: 'palette-backfill-pokeapi-direct',
        matchedName: candidate,
      };
    }
  }
  return null;
}

async function loadFallbackNames(pool, limit) {
  const result = await pool.query(
    `
      select c.name, count(*)::int as rows, min(c.card_id)::text as example_id
      from public.marketplace_search_candidates c
      left join public.cards_name_type cnt on cnt.name = c.name
      where c.item_kind = 'single'
        and c.product_type = 'card'
        and coalesce(c.card_palette->>'key', '') in ('', 'fallback')
        and cnt.name is null
      group by c.name
      order by rows desc, c.name
      limit $1
    `,
    [limit],
  );
  return result.rows;
}

async function upsertMappings(pool, rows) {
  if (rows.length === 0) return 0;
  const values = [];
  const placeholders = [];
  let parameter = 1;
  for (const row of rows) {
    placeholders.push(
      `($${parameter++}, $${parameter++}, $${parameter++}, $${parameter++}, now())`,
    );
    values.push(row.name, row.typeKey, row.priority, row.source);
  }
  const result = await pool.query(
    `
      insert into public.cards_name_type (name, type_key, priority, source, updated_at)
      values ${placeholders.join(', ')}
      on conflict (name, type_key) do update set
        priority = least(public.cards_name_type.priority, excluded.priority),
        source = excluded.source,
        updated_at = now()
    `,
    values,
  );
  return result.rowCount;
}

async function ensureIndexes(pool) {
  await pool.query(`
    create index if not exists cards_name_type_lower_name_idx
      on public.cards_name_type (lower(name), priority)
  `);
}

async function seedSchemaMappings(pool) {
  const result = await pool.query('select public.marketplace_seed_cards_name_type() as seeded');
  return result.rows[0]?.seeded ?? 0;
}

async function refreshBlueprintEmojis(pool) {
  const result = await pool.query('select public.refresh_marketplace_blueprint_emojis() as refreshed');
  return result.rows[0]?.refreshed ?? 0;
}

async function refreshFullProjections(pool) {
  await pool.query('set statement_timeout = 0');
  const result = await pool.query(
    'select public.refresh_marketplace_oracle_projections() as result',
  );
  return result.rows[0]?.result || {};
}

async function refreshPaletteProjections(pool) {
  await pool.query('set statement_timeout = 0');
  await pool.query('begin');
  try {
    const blueprints = await pool.query(`
      with mapped_names as (
        select distinct name
        from public.cards_name_type
        where source like 'palette-backfill%'
           or source = 'seed-rule'
        union
        select distinct name
        from public.marketplace_card_emoji_rules
      )
      update public.cardtrader_pokemon_blueprints b
      set
        card_palette = public.marketplace_card_palette(
          coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
          concat_ws(' ', coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'), b.version)
        ),
        emoji = coalesce((
          select e.emoji
          from public.marketplace_blueprint_emojis e
          where e.blueprint_id = b.id
        ), b.emoji, '')
      from mapped_names
      where mapped_names.name = b.name
    `);
    const cards = await pool.query(`
      update public.marketplace_cards c
      set
        card_palette = b.card_palette,
        emoji = coalesce(e.emoji, ''),
        projected_at = now()
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_blueprint_emojis e
        on e.blueprint_id = c.card_id
      where b.id = c.card_id
        and b.name in (
          select distinct name
          from public.cards_name_type
          where source like 'palette-backfill%'
             or source = 'seed-rule'
          union
          select distinct name
          from public.marketplace_card_emoji_rules
        )
    `);
    const candidates = await pool.query(`
      update public.marketplace_search_candidates s
      set
        card_palette = c.card_palette,
        emoji = c.emoji,
        projected_at = now()
      from public.marketplace_cards c
      where c.card_id = s.card_id
        and c.name in (
          select distinct name
          from public.cards_name_type
          where source like 'palette-backfill%'
             or source = 'seed-rule'
          union
          select distinct name
          from public.marketplace_card_emoji_rules
        )
    `);
    const versions = await pool.query(`
      update public.marketplace_card_versions v
      set
        card_palette = c.card_palette,
        emoji = c.emoji,
        projected_at = now()
      from public.marketplace_cards c
      where c.card_id = v.card_id
        and c.name in (
          select distinct name
          from public.cards_name_type
          where source like 'palette-backfill%'
             or source = 'seed-rule'
          union
          select distinct name
          from public.marketplace_card_emoji_rules
        )
    `);
    await pool.query('commit');
    return {
      cardtraderPokemonBlueprints: blueprints.rowCount,
      marketplaceCards: cards.rowCount,
      searchCandidates: candidates.rowCount,
      marketplaceCardVersions: versions.rowCount,
    };
  } catch (error) {
    await pool.query('rollback');
    throw error;
  }
}

async function paletteCounts(pool) {
  const result = await pool.query(`
    select coalesce(card_palette->>'key', '') as key, count(*)::int as count
    from public.marketplace_search_candidates
    where item_kind = 'single' and product_type = 'card'
    group by 1
    order by count desc, key
  `);
  return result.rows;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const envPath = args.get('oracle-env') || process.env.MARKETPLACE_ORACLE_ENV_PATH || DEFAULT_ORACLE_ENV;
  const env = {
    ...readEnv(envPath),
    ...process.env,
  };
  const apply = args.has('apply');
  const refresh = args.has('refresh');
  const fullRefresh = args.has('full-refresh');
  const limit = Number(args.get('limit') || 100_000);
  const pool = createPool(env);
  try {
    await ensureIndexes(pool);
    console.log(`Mode: ${apply ? 'apply' : 'dry-run'}${refresh ? ' + refresh' : ''}`);
    console.log('Before palette counts');
    console.table(await paletteCounts(pool));

    const fallbackNames = await loadFallbackNames(pool, limit);
    console.log(`Unmapped fallback names: ${fallbackNames.length}`);
    const pokemonIndex = await loadPokemonPaletteIndex();
    const classified = [];
    const skipped = [];
    for (const row of fallbackNames) {
      const trainer = classifyTrainer(row.name);
      const pokemon = trainer
        ? null
        : classifyPokemon(row.name, pokemonIndex) ||
          await classifyPokemonFromApi(row.name);
      const classification = trainer || pokemon;
      if (!classification) {
        skipped.push(row);
        continue;
      }
      classified.push({
        name: row.name,
        rows: row.rows,
        exampleId: row.example_id,
        typeKey: classification.typeKey,
        source: classification.source,
        priority: classification.source.endsWith('trainer') ? 35 : 20,
        matchedName: classification.matchedName || '',
      });
    }

    console.log(`Classified names: ${classified.length}`);
    console.log(`Skipped names: ${skipped.length}`);
    console.table(classified.slice(0, 30));
    if (skipped.length > 0) {
      console.log('Skipped examples');
      console.table(skipped.slice(0, 30));
    }

    if (apply) {
      const seeded = await seedSchemaMappings(pool);
      console.log(`Seeded schema mappings: ${seeded}`);
      const inserted = await upsertMappings(pool, classified);
      console.log(`Upserted mappings: ${inserted}`);
      const refreshedEmojis = await refreshBlueprintEmojis(pool);
      console.log(`Refreshed blueprint emoji source rows: ${refreshedEmojis}`);
      if (refresh) {
        console.log(fullRefresh ? 'Refreshing all projections' : 'Refreshing palette projections');
        console.log(JSON.stringify(
          fullRefresh
            ? await refreshFullProjections(pool)
            : await refreshPaletteProjections(pool),
          null,
          2,
        ));
        console.log('After palette counts');
        console.table(await paletteCounts(pool));
      }
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
