const { marketplaceQuery } = require("./_marketplace_db");

const KNOWN_CARDMARKET_SET_CODES = new Map([
  ["Call of Legends", "CL"],
  ["Chaos Rising", "CRI"],
  ["Clash at the Summit", "L3"],
  ["Cosmic Eclipse", "CEC"],
  ["Astral Radiance", "ASR"],
  ["Advent of Arceus", "Pt4"],
  ["CSM1d: Storming Emergence GX Starter Deck", "CSM1DC"],
  ["CS1b: Dynamax Clash - Flame", "CS1bC"],
  ["CSM1c: Storming Emergence - Abundant", "CSM1cC"],
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

function cleanBlueprintId(value) {
  const id = String(value || "").trim();
  return /^\d{1,12}$/.test(id) ? id : "";
}

function slugPart(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/&/g, " and ")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
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

function maybeCardmarketSetCode(row) {
  if (row.cardmarket_set_code) return String(row.cardmarket_set_code).trim();
  const expansionName = row.expansion_name;
  const cardtraderCode = row.expansion_code;
  const known = KNOWN_CARDMARKET_SET_CODES.get(
    String(expansionName || "").trim(),
  );
  if (known) return known;
  return String(cardtraderCode || "")
    .replace(/[^a-z0-9]/gi, "")
    .toUpperCase();
}

function expansionSlug(row) {
  if (row.cardmarket_expansion_slug) {
    return String(row.cardmarket_expansion_slug).trim();
  }
  const expansionName = row.expansion_name;
  const known = KNOWN_CARDMARKET_EXPANSION_SLUGS.get(
    String(expansionName || "").trim(),
  );
  return known || slugPart(expansionName);
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

function likelyNameOnlyCardmarketSlug(row) {
  const expansionName = String(row.expansion_name || "").trim();
  const type = String(row.card_type || "").toLowerCase();
  if (
    /\b(trainer|supporter|item|stadium|tool|special energy|energy)\b/.test(type)
  ) {
    return KNOWN_NAME_ONLY_TRAINER_EXPANSIONS.has(expansionName);
  }
  return false;
}

function cardmarketSearchFallbackUrl(row, locale) {
  const searchString = cardNameSearchString(row.name);
  const targetLocale = /^[a-z]{2}$/.test(locale) ? locale : "en";
  const url = new URL(
    `https://www.cardmarket.com/${targetLocale}/Pokemon/Products/Singles`,
  );
  url.searchParams.set("searchMode", "v2");
  url.searchParams.set("idCategory", "51");
  url.searchParams.set("idExpansion", "0");
  url.searchParams.set("searchString", searchString);
  url.searchParams.set("idRarity", "0");
  url.searchParams.set("perSite", "30");
  return url.toString();
}

function cardNameSearchString(name) {
  return String(name || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\b(mega|ex|gx|vmax|vstar|lv\.?\s*x|break|prime)\b/gi, " ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .split(/\s+/)
    .find((token) => token.length > 1)
    ?.toLowerCase() || cardNameSlug(name).toLowerCase();
}

function canGenerateDirectProductUrl(row) {
  const expansionName = String(row.expansion_name || "").trim();
  if (likelyNameOnlyCardmarketSlug(row)) {
    return Boolean(row.cardmarket_expansion_slug) || KNOWN_CARDMARKET_EXPANSION_SLUGS.has(expansionName);
  }
  if (!row.cardmarket_expansion_slug && !KNOWN_CARDMARKET_EXPANSION_SLUGS.has(expansionName)) {
    return false;
  }
  const setCode = row.cardmarket_set_code || KNOWN_CARDMARKET_SET_CODES.get(expansionName);
  return Boolean(
    setCode && collectorCandidates(row.expansion_number, setCode).length,
  );
}

function candidateUrls(row, locale) {
  if (isMisprintRow(row)) return [];
  const verifiedUrl = VERIFIED_BLUEPRINT_URLS.get(
    String(row.card_id || "").trim(),
  );
  if (verifiedUrl) return [verifiedUrl];
  const setCode = maybeCardmarketSetCode(row);
  const expansion = expansionSlug(row);
  const name = cardNameSlug(row.name);
  const productCodes = collectorCandidates(row.expansion_number, setCode);
  const versionMarkers = cardmarketVersionMarkers(row);
  const nameOnlyCandidate = `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${name}`;
  const candidates = likelyNameOnlyCardmarketSlug(row)
    ? [nameOnlyCandidate]
    : [];
  for (const productCode of productCodes) {
    for (const marker of versionMarkers) {
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

async function rowForBlueprint(id) {
  const baseQuery = `
      with target as (
        select *
        from public.marketplace_card_versions
        where card_id = $1
        limit 1
      ), ranked as (
        select
          versions.card_id,
          versions.name,
          versions.expansion_name,
          versions.expansion_number,
          versions.expansion_number_int,
          versions.product_variant,
          case
            when count(*) over (partition by versions.expansion_name, versions.name) > 1
              then concat(
                'v',
                row_number() over (
                  partition by versions.expansion_name, versions.name
                  order by versions.expansion_number_int nulls last, versions.expansion_number, versions.card_id
                )
              )
            else ''
          end as inferred_product_variant,
          versions.product_type
        from public.marketplace_card_versions versions
        join target
          on target.expansion_name = versions.expansion_name
         and target.name = versions.name
        where versions.product_type = 'card'
      )
      select
        ranked.card_id,
        ranked.name,
        ranked.expansion_name,
        ranked.expansion_number,
        ranked.product_variant,
        ranked.inferred_product_variant,
        ranked.product_type,
        coalesce(expansion_rules.cardmarket_expansion_slug, '') as cardmarket_expansion_slug,
        coalesce(expansion_rules.cardmarket_set_code, '') as cardmarket_set_code,
        coalesce(expansion_rules.cardmarket_context_code, '') as cardmarket_context_code,
        coalesce(expansion_rules.number_format_rule, '') as number_format_rule,
        expansions.code as expansion_code,
        cards.card_type
      from ranked
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = ranked.expansion_name
      left join public.marketplace_cards cards
        on cards.card_id = ranked.card_id
      left join lateral (
        select
          cardmarket_expansion_slug,
          cardmarket_set_code,
          cardmarket_context_code,
          number_format_rule
        from public.marketplace_cm_expansion_rules rules
        where rules.expansion_name = ranked.expansion_name
          and rules.cardmarket_locale = 'en'
          and rules.confidence in ('verified', 'manual')
        order by
          case
            when rules.applies_to_card_type = coalesce(cards.card_type, '') then 0
            when rules.applies_to_card_type = '' then 1
            else 2
          end,
          rules.verified_at desc nulls last,
          rules.updated_at desc
        limit 1
      ) expansion_rules on true
      where ranked.card_id = $1
      limit 1
    `;
  const fallbackQuery = `
      with target as (
        select *
        from public.marketplace_card_versions
        where card_id = $1
        limit 1
      ), ranked as (
        select
          versions.card_id,
          versions.name,
          versions.expansion_name,
          versions.expansion_number,
          versions.expansion_number_int,
          versions.product_variant,
          case
            when count(*) over (partition by versions.expansion_name, versions.name) > 1
              then concat(
                'v',
                row_number() over (
                  partition by versions.expansion_name, versions.name
                  order by versions.expansion_number_int nulls last, versions.expansion_number, versions.card_id
                )
              )
            else ''
          end as inferred_product_variant,
          versions.product_type
        from public.marketplace_card_versions versions
        join target
          on target.expansion_name = versions.expansion_name
         and target.name = versions.name
        where versions.product_type = 'card'
      )
      select
        ranked.card_id,
        ranked.name,
        ranked.expansion_name,
        ranked.expansion_number,
        ranked.product_variant,
        ranked.inferred_product_variant,
        ranked.product_type,
        '' as cardmarket_expansion_slug,
        '' as cardmarket_set_code,
        '' as cardmarket_context_code,
        '' as number_format_rule,
        expansions.code as expansion_code,
        cards.card_type
      from ranked
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = ranked.expansion_name
      left join public.marketplace_cards cards
        on cards.card_id = ranked.card_id
      where ranked.card_id = $1
      limit 1
    `;
  let result;
  try {
    result = await marketplaceQuery(
      baseQuery,
      [id],
    );
  } catch (error) {
    if (error.code !== "42P01") throw error;
    result = await marketplaceQuery(
      fallbackQuery,
      [id],
    );
  }
  return result.rows[0] || null;
}

async function storedUrlForBlueprint(id, locale) {
  try {
    const result = await marketplaceQuery(
      `
        select cardmarket_url, 0 as priority, verified_at, updated_at
        from public.marketplace_cm_verified_links
        where blueprint_id = $1
          and cardmarket_locale = $2
          and confidence in ('verified', 'manual')
        union all
        select cardmarket_url, 1 as priority, verified_at, updated_at
        from public.marketplace_cm_product_parsing
        where blueprint_id = $1
          and cardmarket_locale = $2
          and match_status in ('verified', 'manual')
        order by priority, verified_at desc nulls last, updated_at desc
        limit 1
      `,
      [id, locale],
    );
    return result.rows[0]?.cardmarket_url || "";
  } catch (error) {
    if (error.code === "42P01") {
      const fallback = await marketplaceQuery(
        `
          select cardmarket_url
          from public.marketplace_cm_product_parsing
          where blueprint_id = $1
            and cardmarket_locale = $2
            and match_status in ('verified', 'manual')
          order by verified_at desc nulls last, updated_at desc
          limit 1
        `,
        [id, locale],
      );
      return fallback.rows[0]?.cardmarket_url || "";
    }
    throw error;
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed." });
  }

  try {
    const requestUrl = new URL(
      req.url,
      `https://${req.headers.host || "pokoin.com"}`,
    );
    const id = cleanBlueprintId(requestUrl.searchParams.get("id"));
    if (!id) {
      return res
        .status(400)
        .json({ error: "Missing or invalid blueprint id." });
    }

    const requestedLocale = requestUrl.searchParams.get("locale") || "";
    const locale = /^[a-z]{2}$/.test(requestedLocale) ? requestedLocale : "en";
    const wantsJson = requestUrl.searchParams.get("format") === "json";
    const row = await rowForBlueprint(id);
    if (!row) {
      return res.status(404).json({ error: "Blueprint not found." });
    }
    const storedUrl = await storedUrlForBlueprint(id, locale);
    if (isMisprintRow(row)) {
      res.setHeader("Cache-Control", "no-store");
      return res.status(409).json({
        code: "CARDMARKET_MISPRINT_UNSUPPORTED",
        message:
          "Cardmarket does not have a dedicated Pokémon Misprints singles section. Please search Cardmarket manually or list the misprint directly on Pokoin.",
      });
    }
    let target = storedUrl;
    if (!target) {
      target = canGenerateDirectProductUrl(row)
        ? candidateUrls(row, locale)[0]
        : cardmarketSearchFallbackUrl(row, locale);
    }
    if (!target) {
      return res
        .status(404)
        .json({ error: "No Cardmarket URL candidate found." });
    }

    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("X-Robots-Tag", "noindex, nofollow");
    if (wantsJson) {
      return res.status(200).json({ url: target });
    }
    res.setHeader("Location", target);
    return res.status(302).end();
  } catch (error) {
    console.error("cardmarket-redirect failed", error);
    return res.status(error.statusCode || 500).json({
      error: error.message || "Cardmarket redirect failed.",
    });
  }
};

module.exports.candidateUrls = candidateUrls;
module.exports.cardmarketSearchFallbackUrl = cardmarketSearchFallbackUrl;
module.exports.canGenerateDirectProductUrl = canGenerateDirectProductUrl;

module.exports.candidateUrls = candidateUrls;
module.exports.cleanBlueprintId = cleanBlueprintId;
