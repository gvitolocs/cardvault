#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { Pool } = require("pg");

const ROOT_DIR = path.resolve(__dirname, "..");
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || "/Users/giuseppe/pokoinpos";
const DEFAULT_SAMPLE_SIZE = 100;
const DEFAULT_LOCALE = "en";

const KNOWN_CARDMARKET_SET_CODES = new Map([
  ["Call of Legends", "CL"],
  ["Chaos Rising", "CRI"],
  ["Clash at the Summit", "L3"],
  ["Cosmic Eclipse", "CEC"],
  ["Astral Radiance", "ASR"],
  ["Advent of Arceus", "Pt4"],
  ["CSM1c: Storming Emergence - Abundant", "CSM1cC"],
  ["CSM1d: Storming Emergence GX Starter Deck", "CSM1DC"],
  ["CS1b: Dynamax Clash - Flame", "CS1bC"],
  ["CSVH4pC: Reward Pack", "CSVH4Cp"],
  ["Darkness that Consumes Light", ""],
  ["Dragon Majesty", "DRM"],
  ["EX Holon Phantoms", "HP"],
  ["High Class Pack GX Ultra Shiny", "sm8b"],
  ["Magma Deck Kit", "advF"],
  ["MEGA Start Deck 100 Battle Collection", "mC"],
  ["Mega Brave", "m1L"],
  ["Neo Discovery", "NDI"],
  ["Paldean Fates", "PAF"],
  ["Perfect Order", "POR"],
  ["Rocket Gang Strikes Back", "PCG3"],
  ["Skyridge", "SK"],
  ["SM Black Star Promos", "OSSM"],
  ["Start Deck 100", "sI100"],
  ["SWSH Black Star Promos", "SWSH"],
  ["Scarlet & Violet Simplified Chinese Promos", "SV-PCS"],
  ["White Flare - Poké Ball Reverse Holo", "xWHT"],
  ["XY Black Star Promos", "XYPR"],
]);

const KNOWN_CARDMARKET_EXPANSION_SLUGS = new Map([
  ["Advent of Arceus", "Advent-of-Arceus"],
  ["Astral Radiance", "Astral-Radiance"],
  ["CS1b: Dynamax Clash - Flame", "Dynamax-Clash-Flame"],
  ["CSM1c: Storming Emergence - Abundant", "Storming-Emergence-Abundant"],
  [
    "CSM1d: Storming Emergence GX Starter Deck",
    "Storming-Emergence-GX-Starter-Deck",
  ],
  ["CSVH4pC: Reward Pack", "Happy-Set-Decidueye-Melmetal-Koraidon-Miraidon"],
  ["Darkness that Consumes Light", "Darkness-that-Consumes-Light"],
  ["Dragon Majesty", "Dragon-Majesty"],
  ["EX Holon Phantoms", "EX-Holon-Phantoms"],
  ["High Class Pack GX Ultra Shiny", "GX-Ultra-Shiny"],
  ["Magma Deck Kit", "Magma-Deck-Kit"],
  ["MEGA Start Deck 100 Battle Collection", "MEGA-Start-Deck-100-Battle-Collection"],
  ["Mega Brave", "Mega-Brave"],
  ["Paldean Fates", "Paldean-Fates"],
  ["Perfect Order", "Perfect-Order"],
  ["S-P: Sword & Shield Promos", "Sword-Shield-Simplified-Chinese-Promos"],
  ["Scarlet & Violet Simplified Chinese Promos", "Scarlet-Violet-Simplified-Chinese-Promos"],
  ["White Flare - Poké Ball Reverse Holo", "White-Flare-Additionals"],
  ["World Championship Decks 2006", "WCD-2006"],
  ["World Championship Decks 2007", "WCD-2007"],
  ["XY Black Star Promos", "XY-Black-Star-Promos"],
]);

const VERIFIED_BLUEPRINT_URLS = new Map([
  [
    "228478",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/SM-Black-Star-Promos/Detective-Pikachu-V2-OSSM194",
  ],
  [
    "236544",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/SWSH-Black-Star-Promos/Rapidash-SWSH270",
  ],
  [
    "315033",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/WCD-2007/Double-Rainbow-Energy-WCD07CG-088",
  ],
  [
    "123536",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Neo-Discovery/Kabutops-NDI25",
  ],
  [
    "388130",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Sword-Shield-Simplified-Chinese-Promos/Friends-in-Alola-S-PCS081",
  ],
  [
    "136333",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Clash-at-the-Summit/Lickitung-L3061",
  ],
  [
    "369312",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Dynamax-Clash-Flame/Lum-Berry-CS1bC130",
  ],
  [
    "142010",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Rocket-Gang-Strikes-Back/Dark-Steelix-PCG3072",
  ],
  [
    "113087",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Cosmic-Eclipse/Throh-CEC118",
  ],
  [
    "383285",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Storming-Emergence-GX-Starter-Deck/Energy-Retrieval-CSM1DC230",
  ],
  [
    "110803",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/BREAKthrough/Ralts-BKT100",
  ],
  [
    "137077",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Darkness-that-Consumes-Light/Pikachu",
  ],
  [
    "138766",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/GX-Ultra-Shiny/Reshiram-GX-V2-sm8b211",
  ],
  [
    "364150",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/MEGA-Start-Deck-100-Battle-Collection/Arvens-Mabosstiff-ex-mC484",
  ],
  [
    "344716",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Mega-Brave/Mega-Venusaur-ex-V2-m1L076",
  ],
  [
    "378949",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Perfect-Order/Mega-Zygarde-ex-V2-POR104",
  ],
  [
    "212782",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Astral-Radiance/Sweet-Honey-ASR153",
  ],
  [
    "378857",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Perfect-Order/Decidueye-ex-V1-POR012",
  ],
  [
    "314822",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/WCD-2006/Girafarig-V1-WCD06LM-016",
  ],
  [
    "274416",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Paldean-Fates/Mew-ex-V2-PAF232",
  ],
  [
    "114322",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Dragon-Majesty/Hydreigon-DRM33",
  ],
  [
    "132124",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/XY-Black-Star-Promos/Jirachi-V2-XYPRXY67a",
  ],
  [
    "343260",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/White-Flare-Additionals/Durant-V2-xWHT070",
  ],
  [
    "315302",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Magma-Deck-Kit/Team-Magmas-Rhyhorn-advF007",
  ],
  [
    "331658",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Scarlet-Violet-Simplified-Chinese-Promos/Toedscool-SV-PCS005",
  ],
  [
    "132211",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/XY-Black-Star-Promos/Rayquaza-XYPRXY141",
  ],
  [
    "135242",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/Advent-of-Arceus/Pokemon-Rescue-Pt4080",
  ],
  [
    "116587",
    "https://www.cardmarket.com/en/Pokemon/Products/Singles/EX-Holon-Phantoms/Mew-ex-HP100",
  ],
]);

const KNOWN_NAME_ONLY_TRAINER_EXPANSIONS = new Set([
  "Night Unison",
  "Rising Fist",
]);

function localExpansionCodeByName() {
  const filePath = path.join(
    ROOT_DIR,
    "data",
    "cardtrader",
    "pokemon-expansions.json",
  );
  if (!fs.existsSync(filePath)) return new Map();
  const rows = JSON.parse(fs.readFileSync(filePath, "utf8"));
  return new Map(
    rows.map((row) => [
      String(row.name || "")
        .trim()
        .toLowerCase(),
      String(row.code || "").trim(),
    ]),
  );
}

const LOCAL_EXPANSION_CODES = localExpansionCodeByName();

function readEnv(filePath) {
  const env = {};
  if (!fs.existsSync(filePath)) return env;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const index = trimmed.indexOf("=");
    const key = trimmed
      .slice(0, index)
      .trim()
      .replace(/^export\s+/, "");
    const value = trimmed
      .slice(index + 1)
      .trim()
      .replace(/^['"]|['"]$/g, "");
    env[key] = value;
  }
  return env;
}

function databaseUrl(env) {
  return (
    env.MARKETPLACE_DATABASE_URL ||
    env.SUPABASE_DB_URL ||
    env.DATABASE_URL ||
    env.POSTGRES_URL ||
    ""
  );
}

function oraclePeerEnvCandidates(args) {
  return unique([
    args.get("oracle-env"),
    process.env.MARKETPLACE_ORACLE_ENV_PATH,
    process.env.ORACLE_ENV_FILE,
    path.join(POKOINPOS_ROOT, "deploy/env/peer4-postgres.env"),
    path.resolve(
      ROOT_DIR,
      "..",
      "pokoinpos",
      "deploy",
      "env",
      "peer4-postgres.env",
    ),
    path.resolve(
      ROOT_DIR,
      "..",
      "..",
      "pokoinpos",
      "deploy",
      "env",
      "peer4-postgres.env",
    ),
  ]);
}

function oracleDatabaseUrlFromPeerEnv(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return "";
  const values = readEnv(filePath);
  const host = values.MARKETPLACE_DB_PUBLIC_HOST;
  const user = values.MARKETPLACE_DB_USER;
  const password = values.MARKETPLACE_DB_PASSWORD;
  const database = values.MARKETPLACE_DB_NAME;
  if (!host || !user || !password || !database) return "";
  const port = values.MARKETPLACE_DB_PORT || "5432";
  return `postgresql://${encodeURIComponent(user)}:${encodeURIComponent(password)}@${host}:${port}/${encodeURIComponent(database)}`;
}

function resolveDatabaseUrl(env, args) {
  for (const filePath of oraclePeerEnvCandidates(args)) {
    const url = oracleDatabaseUrlFromPeerEnv(filePath);
    if (url) return url;
  }
  return databaseUrl(env);
}

function cleanLimit(value, fallback = DEFAULT_SAMPLE_SIZE) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function cleanBlueprintIds(value) {
  return unique(
    String(value || "")
      .split(",")
      .map((entry) => entry.trim())
      .filter((entry) => /^\d+$/.test(entry)),
  );
}

function slugPart(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/&/g, " and ")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function expansionSlug(expansionName) {
  const known = KNOWN_CARDMARKET_EXPANSION_SLUGS.get(
    String(expansionName || "").trim(),
  );
  return known || slugPart(expansionName);
}

function cardNameSlug(name) {
  return slugPart(
    String(name || "")
      .replace(/\bShiny Rare\b/gi, "")
      .replace(/\bRare Holo\b/gi, "")
      .replace(/\bHolo\b/gi, "")
      .replace(/\s+/g, " ")
      .trim(),
  );
}

function maybeCardmarketSetCode(expansionName, cardtraderCode) {
  const known = KNOWN_CARDMARKET_SET_CODES.get(
    String(expansionName || "").trim(),
  );
  if (known) return known;
  const raw =
    String(cardtraderCode || "").trim() ||
    LOCAL_EXPANSION_CODES.get(
      String(expansionName || "")
        .trim()
        .toLowerCase(),
    ) ||
    "";
  if (!raw) return "";
  return raw.replace(/[^a-z0-9]/gi, "").toUpperCase();
}

async function fetchLiveApiRows(limit) {
  const expansionsResponse = await fetch(
    "https://pokoin.com/api/marketplace-expansions?limit=2000",
  );
  if (!expansionsResponse.ok) {
    throw new Error(`Live expansions API failed: ${expansionsResponse.status}`);
  }
  const expansionPayload = await expansionsResponse.json();
  const expansions = Array.isArray(expansionPayload)
    ? expansionPayload
    : Array.isArray(expansionPayload.expansions)
      ? expansionPayload.expansions
      : [];
  const shuffled = [...expansions].sort(() => Math.random() - 0.5);
  const rows = [];
  for (const expansion of shuffled) {
    if (rows.length >= limit) break;
    const slug = expansion.slug;
    if (!slug) continue;
    const snapshotUrl = `https://pokoin.com/api/marketplace-expansions?slug=${encodeURIComponent(slug)}&includeCards=1&limit=80`;
    const response = await fetch(snapshotUrl);
    if (!response.ok) continue;
    const snapshot = await response.json();
    const cards = Array.isArray(snapshot.cards) ? snapshot.cards : [];
    for (const card of cards.sort(() => Math.random() - 0.5)) {
      if (rows.length >= limit) break;
      rows.push({
        card_id: card.card_id || card.id,
        name: card.name,
        expansion_name: card.expansion_name || expansion.name,
        expansion_number: normalizedCollectorNumber(
          card.expansion_number || card.card_number,
        ),
        product_variant: card.product_variant || "",
        product_type: card.product_type || "card",
        card_type: card.card_type || card.type || "",
        expansion_code:
          LOCAL_EXPANSION_CODES.get(
            String(card.expansion_name || expansion.name || "")
              .trim()
              .toLowerCase(),
          ) || "",
      });
    }
  }
  return rows;
}

function collectorCandidates(collectorNumber, setCode) {
  const raw = normalizedCollectorNumber(collectorNumber);
  if (!raw || !setCode) return [];
  const clean = raw.replace(/\s+/g, "").replace(/\/.*$/, "").toUpperCase();
  if (!/\d/.test(clean)) return [];
  const special = /^([A-Z]+)(\d+)$/.exec(clean);
  if (special) {
    const [, prefix, numeric] = special;
    const value = Number(numeric);
    const padded2 = Number.isFinite(value)
      ? String(value).padStart(2, "0")
      : numeric;
    const padded3 = Number.isFinite(value)
      ? String(value).padStart(3, "0")
      : numeric;
    return unique([
      `${setCode}${prefix}${padded2}`,
      `${setCode}${prefix}${numeric}`,
      `${setCode}${prefix}${padded3}`,
    ]);
  }
  const numeric = /^0*(\d+)[A-Z]?$/.exec(clean);
  if (numeric) {
    const value = Number(numeric[1]);
    const suffix = clean.replace(/^\d+/, "");
    const unpadded = `${setCode}${value}${suffix}`;
    const padded3 = `${setCode}${String(value).padStart(3, "0")}${suffix}`;
    const padded2 = `${setCode}${String(value).padStart(2, "0")}${suffix}`;
    return clean.startsWith("0")
      ? unique([padded3, unpadded, padded2])
      : unique([unpadded, padded3, padded2]);
  }
  return [`${setCode}${clean}`];
}

function normalizedCollectorNumber(value) {
  const text = String(value || "")
    .replace(/\|\|/g, "|")
    .trim();
  const slashNumber = /([A-Z]*\d+[A-Z]?\s*\/\s*\d+)/i.exec(text);
  if (slashNumber) return slashNumber[1].replace(/\s+/g, "");
  const specialNumber = /\b([A-Z]{1,4}\s*\d+)\b/i.exec(text);
  if (specialNumber) return specialNumber[1].replace(/\s+/g, "");
  const stampNumber = /\bStamp Number\s+(\d+)\b/i.exec(text);
  if (stampNumber) return stampNumber[1];
  const plainNumber = /\b(?:No\.)?0*(\d{1,4})\b/i.exec(text);
  return plainNumber ? plainNumber[1] : text;
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function candidateUrls(row, locale) {
  if (isMisprintRow(row)) return [];
  const verifiedUrl = VERIFIED_BLUEPRINT_URLS.get(
    String(row.card_id || "").trim(),
  );
  if (verifiedUrl) return [verifiedUrl];
  const setCode = maybeCardmarketSetCode(
    row.expansion_name,
    row.expansion_code,
  );
  const expansion = expansionSlug(row.expansion_name);
  const name = cardNameSlug(row.name);
  const productCodes = collectorCandidates(row.expansion_number, setCode);
  const versionMarkers = cardmarketVersionMarkers(row);
  const inferredVersionMarkers = [
    ...new Set([
      ...versionMarkers,
      ...inferredVariantMarkers(row),
      "",
    ]),
  ];
  const nameOnlyCandidate = `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${name}`;
  const candidates = likelyNameOnlyCardmarketSlug(row)
    ? [nameOnlyCandidate]
    : [];
  for (const productCode of productCodes) {
    for (const marker of inferredVersionMarkers) {
      const productSlug = [name, marker, productCode].filter(Boolean).join("-");
      candidates.push(
        `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${productSlug}`,
      );
    }
  }
  candidates.push(nameOnlyCandidate);
  return unique(candidates);
}

function cardmarketVersionMarkers(row) {
  const version = String(row.product_variant || "").trim();
  const inferred = String(row.inferred_product_variant || "").trim();
  const markers = [];
  if (/^v\d+$/i.test(version)) {
    markers.push(version.toUpperCase());
  }
  if (/^v\d+$/i.test(inferred)) {
    markers.push(inferred.toUpperCase());
  }
  markers.push("");
  return [...new Set(markers)];
}

function isMisprintRow(row) {
  return (
    String(row.expansion_name || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .trim()
      .toLowerCase() === "pokemon misprints"
  );
}

function webSearchQuery(row) {
  return [
    "site:cardmarket.com/en/Pokemon/Products/Singles",
    row.name,
    normalizedCollectorNumber(row.expansion_number),
    row.expansion_name,
    maybeCardmarketSetCode(row.expansion_name, row.expansion_code),
  ]
    .filter(Boolean)
    .join(" ");
}

function inferredVariantMarkers(row) {
  const expansionName = String(row.expansion_name || "").trim();
  const collectorNumber = normalizedCollectorNumber(row.expansion_number);
  if (
    expansionName === "CSM1c: Storming Emergence - Abundant" &&
    collectorNumber === "186/151"
  ) {
    return ["V2"];
  }
  return [];
}

function likelyNameOnlyCardmarketSlug(row) {
  const type = String(row.card_type || "").toLowerCase();
  if (
    /\b(trainer|supporter|item|stadium|tool|special energy|energy)\b/.test(type)
  ) {
    return KNOWN_NAME_ONLY_TRAINER_EXPANSIONS.has(
      String(row.expansion_name || "").trim(),
    );
  }
  return (
    !type &&
    KNOWN_NAME_ONLY_TRAINER_EXPANSIONS.has(
      String(row.expansion_name || "").trim(),
    ) &&
    likelyTrainerName(row.name)
  );
}

function cardmarketSearchFallbackUrl(row, locale) {
  const targetLocale = /^[a-z]{2}$/.test(locale) ? locale : DEFAULT_LOCALE;
  const url = new URL(
    `https://www.cardmarket.com/${targetLocale}/Pokemon/Products/Singles`,
  );
  url.searchParams.set("searchMode", "v2");
  url.searchParams.set("idCategory", "51");
  url.searchParams.set("idExpansion", "0");
  url.searchParams.set("searchString", cardNameSearchString(row.name));
  url.searchParams.set("idRarity", "0");
  url.searchParams.set("perSite", "30");
  return url.toString();
}

function cardNameSearchString(name) {
  return (
    String(name || "")
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/\b(mega|ex|gx|vmax|vstar|lv\.?\s*x|break|prime)\b/gi, " ")
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .trim()
      .split(/\s+/)
      .find((token) => token.length > 1)
      ?.toLowerCase() || cardNameSlug(name).toLowerCase()
  );
}

function likelyTrainerName(name) {
  return /\b(box|center|stadium|machine|energy|switch|catcher|research|professor|potion|ball|rod|belt|badge|map|mail|ticket|search|gear|scrapper|blower|rope|hammer|patch|candy|vitality|schoolboy|youngster|shauna|janine|serena|copycat|switch|surprise)\b/i.test(
    String(name || ""),
  );
}

async function verifyUrl(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(url, {
      method: "HEAD",
      redirect: "manual",
      signal: controller.signal,
      headers: {
        "user-agent":
          "Mozilla/5.0 (compatible; PokoinCardmarketAssociation/1.0; +https://pokoin.com)",
      },
    });
    return {
      status: response.status,
      ok: response.status >= 200 && response.status < 400,
      location: response.headers.get("location") || "",
    };
  } catch (error) {
    return { status: 0, ok: false, error: error.message };
  } finally {
    clearTimeout(timeout);
  }
}

async function sampleBlueprints(pool, limit) {
  const result = await pool.query(
    `
      select
        versions.card_id,
        versions.name,
        versions.expansion_name,
        versions.expansion_number,
        versions.product_variant,
        versions.inferred_product_variant,
        versions.product_type,
        blueprints.card_market_ids,
        expansions.code as expansion_code,
        cards.card_type
      from (
        select *
        from (
          select
            card_id,
            name,
            expansion_name,
            expansion_number,
            product_variant,
            case
              when count(*) over (partition by expansion_name, name) > 1
                then concat(
                  'v',
                  row_number() over (
                    partition by expansion_name, name
                    order by expansion_number_int nulls last, expansion_number, card_id
                  )
                )
              else ''
            end as inferred_product_variant,
            product_type
          from public.marketplace_card_versions
          where product_type = 'card'
            and expansion_name is not null
            and expansion_number is not null
            and name is not null
        ) ranked_versions
        order by random()
        limit $1
      ) versions
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = versions.expansion_name
      left join public.marketplace_cards cards
        on cards.card_id = versions.card_id
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = versions.card_id
    `,
    [limit],
  );
  return result.rows;
}

async function blueprintsById(pool, blueprintIds) {
  if (!blueprintIds.length) return [];
  const result = await pool.query(
    `
      select
        versions.card_id,
        versions.name,
        versions.expansion_name,
        versions.expansion_number,
        versions.product_variant,
        versions.inferred_product_variant,
        versions.product_type,
        blueprints.card_market_ids,
        expansions.code as expansion_code,
        cards.card_type
      from (
        select
          card_id,
          name,
          expansion_name,
          expansion_number,
          product_variant,
          case
            when count(*) over (partition by expansion_name, name) > 1
              then concat(
                'v',
                row_number() over (
                  partition by expansion_name, name
                  order by expansion_number_int nulls last, expansion_number, card_id
                )
              )
            else ''
          end as inferred_product_variant,
          product_type
        from public.marketplace_card_versions
        where product_type = 'card'
          and card_id = any($1::bigint[])
      ) versions
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = versions.expansion_name
      left join public.marketplace_cards cards
        on cards.card_id = versions.card_id
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = versions.card_id
      order by array_position($1::bigint[], versions.card_id)
    `,
    [blueprintIds],
  );
  return result.rows;
}

async function verifiedProductParsingByBlueprint(pool, rows, locale) {
  const blueprintIds = unique(
    rows.map((row) => String(row.card_id || "").trim()),
  );
  if (!blueprintIds.length) return new Map();

  const result = await pool.query(
    `
      select
        blueprint_id,
        cardmarket_locale,
        cardmarket_url,
        match_status
      from public.marketplace_cm_product_parsing
      where blueprint_id = any($1::bigint[])
        and match_status in ('verified', 'manual')
      order by
        case when cardmarket_locale = $2 then 0 else 1 end,
        verified_at desc nulls last,
        updated_at desc
    `,
    [blueprintIds, locale],
  );

  const byBlueprint = new Map();
  for (const row of result.rows) {
    const key = String(row.blueprint_id);
    if (!byBlueprint.has(key)) {
      byBlueprint.set(key, row);
    }
  }
  return byBlueprint;
}

function writeReport(rows, outputPath) {
  const confirmed = rows.filter((row) => row.verifiedUrl);
  const lines = [
    "# Cardmarket Association Sample Report",
    "",
    `Generated: ${new Date().toISOString()}`,
    `Sample size: ${rows.length}`,
    `Confirmed candidates: ${confirmed.length}`,
    "",
    "## Summary",
    "",
    "- Candidate URLs are generated from Oracle marketplace metadata.",
    "- Confirmation uses HTTP HEAD and may fail if Cardmarket blocks automated checks.",
    "- Unconfirmed rows should be manually checked before persisting mappings.",
    "",
    "## Rows",
    "",
    "| Blueprint ID | Card | Expansion | Number | Cardmarket IDs | Search fallback | Verified URL | First candidate | Status |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  ];
  for (const row of rows) {
    lines.push(
      [
        row.card_id,
        escapeCell(row.name),
        escapeCell(row.expansion_name),
        escapeCell(row.expansion_number),
        escapeCell(cardmarketIdsLabel(row.card_market_ids)),
        row.searchFallbackUrl ? `[search](${row.searchFallbackUrl})` : "",
        row.verifiedUrl ? `[open](${row.verifiedUrl})` : "",
        row.candidates[0] ? `[candidate](${row.candidates[0]})` : "",
        row.verificationStatus,
      ]
        .join(" | ")
        .replace(/^/, "| ")
        .replace(/$/, " |"),
    );
  }
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${lines.join("\n")}\n`);
}

function escapeCell(value) {
  return String(value || "").replace(/\|/g, "\\|");
}

function cardmarketIdsLabel(value) {
  if (!value) return "";
  if (Array.isArray(value)) return value.join(", ");
  if (typeof value === "string") return value.replace(/[{}"]/g, "");
  return String(value);
}

async function main() {
  const args = new Map();
  for (let index = 2; index < process.argv.length; index += 1) {
    const [key, value = "1"] = process.argv[index].split("=", 2);
    args.set(key.replace(/^--/, ""), value);
  }
  const env = { ...readEnv(path.join(ROOT_DIR, ".env.local")), ...process.env };
  const limit = cleanLimit(args.get("limit"));
  const blueprintIds = cleanBlueprintIds(
    args.get("blueprint-id") || args.get("blueprint-ids"),
  );
  const connectionString = resolveDatabaseUrl(env, args);
  const locale = args.get("locale") || DEFAULT_LOCALE;
  const verify = args.get("verify") !== "0";
  const output =
    args.get("output") ||
    path.join(
      ROOT_DIR,
      "workflows",
      "reports",
      `cardmarket-association-sample-${new Date().toISOString().replace(/[:.]/g, "-")}.md`,
    );

  let pool = null;
  try {
    let rows = [];
    if (blueprintIds.length && !connectionString) {
      throw new Error("--blueprint-id requires Oracle database access.");
    }
    if (args.get("source") === "api" || !connectionString) {
      rows = await fetchLiveApiRows(limit);
    } else {
      pool = new Pool({
        connectionString,
        max: 2,
        idleTimeoutMillis: 10_000,
        connectionTimeoutMillis: 10_000,
        ssl: { rejectUnauthorized: false },
      });
      try {
        rows = blueprintIds.length
          ? await blueprintsById(pool, blueprintIds)
          : await sampleBlueprints(pool, limit);
      } catch (error) {
        if (blueprintIds.length) {
          throw error;
        }
        console.warn(
          `Database sampling failed (${error.message}); falling back to live API.`,
        );
        rows = await fetchLiveApiRows(limit);
      }
    }
    const verifiedMappings =
      pool && rows.length
        ? await verifiedProductParsingByBlueprint(pool, rows, locale)
        : new Map();
    const enriched = [];
    for (const row of rows) {
      const storedMapping = verifiedMappings.get(String(row.card_id));
      const manualOverride = VERIFIED_BLUEPRINT_URLS.get(
        String(row.card_id || "").trim(),
      );
      const candidates = unique([
        storedMapping?.cardmarket_url,
        manualOverride,
        ...candidateUrls(row, locale),
      ]);
      let verifiedUrl = storedMapping?.cardmarket_url || manualOverride || "";
      let verificationStatus = "not verified";
      if (storedMapping) {
        verificationStatus = `stored ${storedMapping.match_status} (${storedMapping.cardmarket_locale})`;
      } else if (manualOverride) {
        verificationStatus = "manual override";
      }
      if (verify && !storedMapping && !manualOverride) {
        verificationStatus = "no candidate";
        for (const candidate of candidates.slice(0, 6)) {
          const result = await verifyUrl(candidate);
          verificationStatus = String(
            result.status || result.error || "failed",
          );
          if (result.ok) {
            verifiedUrl = candidate;
            break;
          }
        }
      }
      enriched.push({
        ...row,
        candidates,
        verifiedUrl,
        verificationStatus,
        searchQuery: webSearchQuery(row),
        searchFallbackUrl: storedMapping
          ? ""
          : cardmarketSearchFallbackUrl(row, locale),
      });
    }
    writeReport(enriched, output);
    console.log(`Wrote ${path.relative(ROOT_DIR, output)}`);
    console.log(
      `Confirmed ${enriched.filter((row) => row.verifiedUrl).length}/${enriched.length}`,
    );
  } finally {
    if (pool) {
      await pool.end();
    }
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}

module.exports = {
  cardNameSlug,
  normalizedCollectorNumber,
  collectorCandidates,
  candidateUrls,
  maybeCardmarketSetCode,
};
