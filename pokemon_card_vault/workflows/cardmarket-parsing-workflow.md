# Cardmarket Parsing Workflow

Use this workflow when mapping Pokoin/CardTrader blueprint IDs to Cardmarket
product URLs.

Cardmarket URLs are not reliably derivable from CardTrader metadata alone. The
sampler can propose candidates, but verified case-by-case corrections must be
stored in Oracle so future candidate generation learns from them.

## Source Of Truth

Oracle stores the durable parsing layer:

```sql
public.marketplace_cm_expansion_rules
public.marketplace_cm_verified_links
public.marketplace_cm_scrape_observations
public.marketplace_cm_expansion_parsing
public.marketplace_cm_product_parsing
```

`marketplace_cm_verified_links` is the redirect fast path. It stores exact
verified/manual mappings from Pokoin/CardTrader `blueprint_id` to canonical
Cardmarket singles URL. `/api/cardmarket-redirect` must check this table first.

`marketplace_cm_expansion_rules` stores reusable expansion-level Cardmarket
rules used when a card does not have an exact verified link:

- CardTrader/Pokoin expansion name and code.
- Cardmarket locale and expansion slug.
- Cardmarket set code.
- Cardmarket context code for special products such as World Championship decks.
- Number format rule.
- Card type scope, such as `pokemon` or `trainer`.
- Confidence and notes.

`marketplace_cm_expansion_parsing` and `marketplace_cm_product_parsing` remain
the detailed parser/compatibility tables. They store richer metadata and history,
but new runtime lookups should prefer `marketplace_cm_verified_links` and
`marketplace_cm_expansion_rules`.

`marketplace_cm_scrape_observations` stores browser-collected Cardmarket product
page observations from `pokemon-card-extension`. These observations are evidence,
not automatically verified links. Promote confirmed rows into
`marketplace_cm_verified_links`.

`marketplace_cm_product_parsing` stores per-blueprint parsing metadata:

- `blueprint_id`.
- Cardmarket locale.
- Cardmarket display name.
- Cardmarket expansion slug.
- Collector number and normalized collector number.
- Set code, context code, and variant marker.
- Product slug and full URL.
- Match status, confidence, verification method/source, notes, and timestamp.

## What We Learned

Canonical public Cardmarket single URL shape:

```text
https://www.cardmarket.com/<locale>/Pokemon/Products/Singles/<ExpansionSlug>/<ProductSlug>
```

The locale matters. We have seen valid `it`, `en`, and `es` URLs. Default new
candidate generation to `en` unless the verified mapping or user request uses a
different locale.

Cardmarket expansion slugs are Cardmarket-specific. They often differ from
CardTrader/Pokoin expansion names:

- `Skyridge` keeps the expansion slug but maps CardTrader code `skg` to
  Cardmarket product code `SK`.
- `Start Deck 100` keeps the expansion slug but maps CardTrader code `sl` to
  Cardmarket product code `sI100`.
- `CSM1c: Storming Emergence - Abundant` maps to
  `Storming-Emergence-Abundant`.
- `World Championship Decks 2018` maps to `WCD-2018`.
- `XY Trainer Kit: Pikachu Libre & Suicune (Suicune)` maps to
  `XY-Trainer-Kit-Pikachu-Libre-Suicune`.
- Simple title-case hyphenation works for some English sets, but not enough to
  trust blindly.

Product slug rules differ by card kind:

- Pokémon cards often use `Name-SetCodeNumber`.
- Trainer-like cards can use only `Name`, but this is expansion-specific.
  Do not apply it globally; Aquapolis Trainer examples still use set code and
  collector number, e.g. `Forest-Guardian-AQ123`.
- Some products include a variant marker such as `V1`.
- Cardmarket can add a `Vn` marker when the same card name appears multiple
  times in one expansion; infer the marker by collector-number order when local
  metadata does not already provide one.
- Do not use `card_market_ids` / `idProduct` as the public URL. Those IDs can
  help identify a Cardmarket record internally, but user-facing links must use
  the canonical `/Products/Singles/<ExpansionSlug>/<ProductSlug>` path.
- World Championship decks can use a context/player code instead of the local
  expansion code.

Verified examples:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Unbroken-Bonds/Togekiss-UNB138
https://www.cardmarket.com/en/Pokemon/Products/Singles/Rising-Fist/Training-Center
https://www.cardmarket.com/it/Pokemon/Products/Singles/Night-Unison/Surprise-Box
https://www.cardmarket.com/en/Pokemon/Products/Singles/MEGA-Dream-ex/Hops-Zacian-ex-m2a123
https://www.cardmarket.com/es/Pokemon/Products/Singles/Storming-Emergence-Abundant/Pokemon-Fan-Club-V1-CSM1cC143
https://www.cardmarket.com/en/Pokemon/Products/Singles/WCD-2018/Buzzwole-GX-WCD18CIN-057
https://www.cardmarket.com/en/Pokemon/Products/Singles/XY-Trainer-Kit-Pikachu-Libre-Suicune/Tierno-TK9S-29
https://www.cardmarket.com/en/Pokemon/Products/Singles/Phantom-Forces/Dedenne-PHF70
https://www.cardmarket.com/it/Pokemon/Products/Singles/Phantasmal-Flames/Ambipom-V2-PFL107
https://www.cardmarket.com/en/Pokemon/Products/Singles/Skyridge/Lapras-SK71
https://www.cardmarket.com/en/Pokemon/Products/Singles/Skyridge/Steelix-V2-SK31
https://www.cardmarket.com/en/Pokemon/Products/Singles/Aquapolis/Forest-Guardian-AQ123
https://www.cardmarket.com/en/Pokemon/Products/Singles/Start-Deck-100/Aroma-Lady-sI100387
https://www.cardmarket.com/en/Pokemon/Products/Singles/Storming-Emergence-Abundant/Cynthia-V2-CSM1cC186
https://www.cardmarket.com/en/Pokemon/Products/Singles/WCD-2007/Double-Rainbow-Energy-WCD07CG-088
https://www.cardmarket.com/en/Pokemon/Products/Singles/Neo-Discovery/Kabutops-NDI25
https://www.cardmarket.com/en/Pokemon/Products/Singles/Sword-Shield-Simplified-Chinese-Promos/Friends-in-Alola-S-PCS081
https://www.cardmarket.com/en/Pokemon/Products/Singles/SWSH-Black-Star-Promos/Rapidash-SWSH270
https://www.cardmarket.com/en/Pokemon/Products/Singles/Clash-at-the-Summit/Lickitung-L3061
https://www.cardmarket.com/en/Pokemon/Products/Singles/Dynamax-Clash-Flame/Lum-Berry-CS1bC130
https://www.cardmarket.com/en/Pokemon/Products/Singles/SM-Black-Star-Promos/Detective-Pikachu-V2-OSSM194
https://www.cardmarket.com/en/Pokemon/Products/Singles/MEGA-Start-Deck-100-Battle-Collection/Arvens-Mabosstiff-ex-mC484
https://www.cardmarket.com/en/Pokemon/Products/Singles/Mega-Brave/Mega-Venusaur-ex-V2-m1L076
https://www.cardmarket.com/en/Pokemon/Products/Singles/Perfect-Order/Mega-Zygarde-ex-V2-POR104
https://www.cardmarket.com/en/Pokemon/Products/Singles/Astral-Radiance/Sweet-Honey-ASR153
https://www.cardmarket.com/en/Pokemon/Products/Singles/Perfect-Order/Decidueye-ex-V1-POR012
https://www.cardmarket.com/en/Pokemon/Products/Singles/WCD-2006/Girafarig-V1-WCD06LM-016
https://www.cardmarket.com/en/Pokemon/Products/Singles/Paldean-Fates/Mew-ex-V2-PAF232
https://www.cardmarket.com/en/Pokemon/Products/Singles/Dragon-Majesty/Hydreigon-DRM33
https://www.cardmarket.com/en/Pokemon/Products/Singles/XY-Black-Star-Promos/Jirachi-V2-XYPRXY67a
https://www.cardmarket.com/en/Pokemon/Products/Singles/White-Flare-Additionals/Durant-V2-xWHT070
https://www.cardmarket.com/en/Pokemon/Products/Singles/Magma-Deck-Kit/Team-Magmas-Rhyhorn-advF007
https://www.cardmarket.com/en/Pokemon/Products/Singles/Scarlet-Violet-Simplified-Chinese-Promos/Toedscool-SV-PCS005
https://www.cardmarket.com/en/Pokemon/Products/Singles/XY-Black-Star-Promos/Rayquaza-XYPRXY141
https://www.cardmarket.com/en/Pokemon/Products/Singles/Advent-of-Arceus/Pokemon-Rescue-Pt4080
https://www.cardmarket.com/en/Pokemon/Products/Singles/EX-Holon-Phantoms/Mew-ex-HP100
```

Observed transformations:

- Apostrophes may be removed, not replaced with hyphen:
  `Hop's Zacian ex` -> `Hops-Zacian-ex`.
- Accents are normalized out:
  `Pokémon Fan Club` -> `Pokemon-Fan-Club`.
- Cardmarket set-code casing can matter:
  `m2a123`, `m1L076`, `mC484`, `CSM1cC143`, `ASR153`, `UNB138`.
- Cardmarket set code can differ from CardTrader code:
  Skyridge is `SK` on Cardmarket while Oracle/CardTrader stores `skg`;
  Start Deck 100 is `sI100` while Oracle/CardTrader stores `sl`.
- Main-set collector numbers can preserve leading zeroes:
  `079/094` -> `PFL079`.
- Cardmarket context code can be distinct:
  `WCD18CIN-057` and `WCD07CG-088` for World Championship deck cards,
  `WCD06LM-016` for WCD 2006, and `TK9S-29` for a Trainer Kit card.
- Some Japanese and Chinese products live under Cardmarket-specific expansion
  slugs:
  `S-P: Sword & Shield Promos` -> `Sword-Shield-Simplified-Chinese-Promos`,
  `CS1b: Dynamax Clash - Flame` -> `Dynamax-Clash-Flame`.
- Promo product codes can differ from CardTrader expansion codes:
  `SWSH Black Star Promos` uses `SWSH`, `SM Black Star Promos` can use `OSSM`,
  and Simplified Chinese promos can use `PCS`.
- `MEGA Start Deck 100 Battle Collection` can use mixed-case `mC` product
  codes, e.g. `Arvens-Mabosstiff-ex-mC484`.
- `Mega Brave` can require both a variant marker and a mixed-case product code,
  e.g. `Mega-Venusaur-ex-V2-m1L076`.
- `Perfect Order` can use `POR` product codes and require a variant marker,
  e.g. `Decidueye-ex-V1-POR012` and `Mega-Zygarde-ex-V2-POR104`.
- `Paldean Fates` is a curated direct-product expansion with `PAF` codes.
  Do not send known numbered Paldean Fates cards to search fallback when the
  slug, set code, and collector number are present; regression example:
  `Mew-ex-V2-PAF232`.
- `Astral Radiance` Trainer/Item products can be code-suffixed rather than
  name-only, e.g. `Sweet-Honey-ASR153`.
- `World Championship Decks 2006` can require player/deck context codes and
  variants, e.g. `Girafarig-V1-WCD06LM-016`. Do not derive the `LM` segment from
  CardTrader expansion code alone; it is deck/player context.
- Duplicate-name variants can use `Vn`:
  Ambipom `079/094` is `Ambipom-V1-PFL079`, while Ambipom `107/094` is
  `Ambipom-V2-PFL107`.
- Local product variants such as `EX` are not Cardmarket version markers. Keep
  inferred duplicate-name `V1`/`V2` markers available separately from local
  `product_variant`, and include both marker and no-marker candidates when the
  marker is uncertain.
- Manual/refinement URLs are exact product slugs. Do not reconstruct them from
  parts and accidentally drop `V1`/`V2`; persist the full slug exactly as pasted
  or user-verified.
- XY Black Star Promos can use `XYPR` plus the printed XY promo number, e.g.
  `XYPRXY141` and `XYPRXY67a`; some rows still require `Vn`.
- Reverse-holo/additional Japanese sets can map to Cardmarket "Additionals"
  expansions, e.g. White Flare Poké Ball Reverse Holo -> `White-Flare-Additionals`
  with `xWHT` codes.
- Simplified Chinese Scarlet/Violet promos use
  `Scarlet-Violet-Simplified-Chinese-Promos` and `SV-PCS` product codes.
- Local names may differ from Cardmarket names; preserve the Cardmarket slug
  when verified, e.g. local `Rescue` -> `Pokemon-Rescue-Pt4080`.
- `EX Holon Phantoms` uses Cardmarket slug `EX-Holon-Phantoms` and product code
  `HP`, e.g. blueprint `116587` -> `Mew-ex-HP100`.
- Storming Emergence Abundant can also require variant markers on Trainer rows:
  Cynthia `186/151` is `Cynthia-V2-CSM1cC186`, while Pokemon Fan Club `143/151`
  is `Pokemon-Fan-Club-V1-CSM1cC143`.
- Trainer products can be name-only:
  `Training-Center`, `Surprise-Box`.
- Trainer products can also be code-suffixed in other expansions:
  `Forest-Guardian-AQ123`.
- Cards in the `Pokemon Misprints` category must not be auto-linked to
  Cardmarket. Cardmarket exposes a generic `Pokemon-Misprints/Blank-Filler-Card`
  page, but no reliable per-blueprint singles section exists. Pokoin should show
  an explanatory popup instead.

## Candidate Generation

Runtime order for `/api/cardmarket-redirect`:

1. Read `marketplace_cm_verified_links` for the exact `blueprint_id` and locale.
2. Fall back to `marketplace_cm_product_parsing` verified/manual rows for
   compatibility with older seeded data.
3. Build candidates from `marketplace_cm_expansion_rules`.
4. Fall back to code-level maps only when the DB has no rule.
5. Use narrowed Cardmarket search fallback only when a direct product URL is not
   safe enough.

The debug refinement queue uses the same verified-link fast path for
`verified_audit` rows, so already-valid links can be rechecked by a human.

Run a random Oracle-backed candidate sample:

```bash
node scripts/cardmarket-association-sampler.js --limit=100 --verify=0
```

Run a small verification smoke test:

```bash
node scripts/cardmarket-association-sampler.js --limit=10 --verify=1
```

Inspect one or more exact blueprint IDs instead of random rows:

```bash
node scripts/cardmarket-association-sampler.js --blueprint-id=370392 --verify=0
node scripts/cardmarket-association-sampler.js --blueprint-ids=370392,370349 --verify=0
```

The blueprint-specific report includes:

- Stored verified Cardmarket URL when available, across locales.
- Candidate slug URLs generated from Oracle metadata.
- `card_market_ids` as metadata only, not as public URLs.
- A web-search query you can paste into search when Cardmarket blocks automated
  requests.
- A narrowed Cardmarket search URL can be used as a fallback when the card name
  is known but the exact product slug is not yet verified.

The sampler uses Oracle through `MARKETPLACE_DATABASE_URL` or the sibling
workflow env file:

```text
/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env
```

Do not print the database URL or values from that env file.

Reports are written to:

```text
workflows/reports/cardmarket-association-sample-*.md
```

## Verification Rules

Do not treat Cardmarket `HEAD 403` as proof that a candidate is wrong.
Cardmarket can block automated checks. Mark these as `blocked` or `unverified`.

Use these signals instead:

- User-provided Cardmarket URL.
- Manual browser check.
- Web search result showing a Cardmarket `/Products/Singles/...` URL for the
  exact card name, collector number, set code, and expansion.
- A Cardmarket-friendly data feed/API if one becomes available.
- Very small cautious `GET` checks only if needed, not large automated batches.

Do not persist generated candidates as verified. Persist only confirmed mappings
in `marketplace_cm_verified_links` and `marketplace_cm_product_parsing`.

## Product URL Readiness

Before returning a direct Cardmarket product URL, decide whether the parser has
enough information to build one safely. A direct product URL requires all of
these to be known, not merely guessed:

- Correct Cardmarket expansion slug.
- Correct Cardmarket set code or a verified name-only/context-code rule.
- Correct collector-number formatting for that expansion, when the product slug
  is code-suffixed.
- Correct Cardmarket variant marker such as `V1`/`V2`, or verified evidence that
  no variant marker is needed.
- Correct Cardmarket card-name slug when Cardmarket differs from CardTrader
  punctuation/local naming.

If any required element is missing, ambiguous, or inferred only from a weak API
bridge such as `TCGdex set id -> maybe Cardmarket code`, do not present the
guessed product URL as the main result. Use a narrowed Cardmarket search fallback
instead and mark the generated product slug as `candidate` only.

Examples of incomplete product URL state:

- We know the card name and collector number, but not the Cardmarket expansion
  slug.
- We know the TCGdex set id (`sm12`, `xy8`, `swsh3`), but not its Cardmarket set
  code (`CEC`, `BKT`, `DAA`).
- The expansion often uses Cardmarket-only variant markers and this blueprint has
  no verified marker.
- The parser would otherwise return a name-only URL for a Pokémon card from an
  expansion that usually uses code-suffixed products.

## Search Fallback URLs

When the exact Cardmarket product URL is incomplete or unverified, but the card
name is known, use Cardmarket's singles search page as a user-facing fallback.
This is useful for cases like `Reshiram GX` from `High Class Pack GX Ultra
Shiny`, where the parser can identify the card but not the canonical product
slug.

Fallback shape:

```text
https://www.cardmarket.com/en/Pokemon/Products/Singles?searchMode=v2&idCategory=51&idExpansion=0&searchString=<encoded card name>&idRarity=0&perSite=30
```

Example:

```text
https://www.cardmarket.com/en/Pokemon/Products/Singles?searchMode=v2&idCategory=51&idExpansion=0&searchString=reshiram&idRarity=0&perSite=30
```

Rules:

- Use the shortest useful card-name search string, usually the Pokémon/card root
  such as `reshiram`, not the full noisy rarity text.
- Keep `idExpansion=0` unless a verified Cardmarket expansion ID is known.
- This URL is a fallback/search URL, not a product URL. Do not store it in
  `marketplace_cm_product_parsing.cardmarket_url` as `verified`.
- If the fallback search leads to a correct product page, store that resulting
  `/Products/Singles/<ExpansionSlug>/<ProductSlug>` URL as the verified mapping.

## Adding A User-Verified Mapping

When the user provides a correct URL:

1. Identify the blueprint ID from the Pokoin/CardTrader row.
2. If the user only gives a blueprint ID, run the sampler with `--blueprint-id`
   and use the generated web-search query to find a canonical Cardmarket result.
3. Parse the Cardmarket URL:
   - locale
   - expansion slug
   - product slug
   - variant marker if present
   - set code or context code if present
4. Upsert `marketplace_cm_expansion_parsing`.
5. Upsert `marketplace_cm_product_parsing`.
6. Add notes explaining what was learned.
7. Update `workflows/cardmarket-product-association-report.md` if the case
   changes the rules.

Example product upsert shape:

```sql
insert into public.marketplace_cm_product_parsing (
  blueprint_id,
  cardmarket_locale,
  card_name,
  cardmarket_name,
  expansion_name,
  cardmarket_expansion_slug,
  collector_number,
  normalized_collector_number,
  cardmarket_set_code,
  cardmarket_context_code,
  cardmarket_variant_marker,
  cardmarket_product_slug,
  cardmarket_url,
  match_status,
  confidence,
  verification_method,
  verification_source,
  notes,
  verified_at
) values (
  $blueprint_id,
  $locale,
  $card_name,
  $cardmarket_name,
  $expansion_name,
  $cardmarket_expansion_slug,
  $collector_number,
  $normalized_collector_number,
  $cardmarket_set_code,
  $cardmarket_context_code,
  $variant_marker,
  $product_slug,
  $url,
  'verified',
  'verified',
  'user',
  'chat',
  $notes,
  now()
)
on conflict (blueprint_id, cardmarket_locale)
do update set
  cardmarket_name = excluded.cardmarket_name,
  cardmarket_expansion_slug = excluded.cardmarket_expansion_slug,
  cardmarket_set_code = excluded.cardmarket_set_code,
  cardmarket_context_code = excluded.cardmarket_context_code,
  cardmarket_variant_marker = excluded.cardmarket_variant_marker,
  cardmarket_product_slug = excluded.cardmarket_product_slug,
  cardmarket_url = excluded.cardmarket_url,
  match_status = excluded.match_status,
  confidence = excluded.confidence,
  verification_method = excluded.verification_method,
  verification_source = excluded.verification_source,
  notes = excluded.notes,
  verified_at = excluded.verified_at,
  updated_at = now();
```

## Applying Schema

Schema files:

```text
oracle-postgres/schema/001_marketplace_core.sql
oracle-postgres/schema/007_cardmarket_parsing_seeds.sql
```

Apply schema through the Oracle workflow:

```bash
node scripts/oracle-marketplace-migrate.js schema
```

If `MARKETPLACE_DATABASE_URL` is not exported locally, derive it from the
Pokoin peer env workflow without printing values.

## Current Seeded Verified Rows

Expansion parsing rows seeded: `13`.

Product parsing rows seeded: `410`.

Seeded blueprints:

- `130677`: `Togekiss-UNB138`.
- `141860`: `Training-Center`.
- `320561`: `Buzzwole-GX-WCD18CIN-057`.
- `359203`: `Hops-Zacian-ex-m2a123`.
- `370349`: `Pokemon-Fan-Club-V1-CSM1cC143`.
- `370392`: `Cynthia-V2-CSM1cC186`.
- `132565`: `Tierno-TK9S-29`.
- `124608`: `Dedenne-PHF70`.
- `356893`: `Ambipom-V2-PFL107`.

## Refinement Backlog

- Verify more expansion-level code overrides before adding them to the parser.
  Suspect sets from the same legacy area include `Expedition Base Set` and
  EX-era expansions. `Aquapolis` examples show `AQ`, matching Oracle `aq`, so
  it does not currently need an override.
- Make the sampler consult `marketplace_cm_expansion_parsing` before heuristics.
- Make the sampler consult `marketplace_cm_product_parsing` and emit verified
  URL first when present.
- Add a safe operator command for inserting a new verified URL from a blueprint
  ID and Cardmarket URL.
- Record `blocked` verification status separately from `rejected`.
- Expand Cardmarket locale handling without assuming slug equality across
  languages.
- Build confidence scoring from verified expansion/product parsing rows.
