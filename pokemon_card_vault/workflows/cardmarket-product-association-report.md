# Cardmarket Product Association Report

This report is the working reference for associating Pokoin/CardTrader blueprint
IDs with Cardmarket product URLs.

Pokoin cards are keyed by CardTrader blueprint IDs. Cardmarket does not expose
that blueprint ID in the public product URL, so the association must be inferred
from card metadata and then verified before it is stored.

## Database-Backed Association

Verified mappings now live in PostgreSQL, not primarily in code:

```sql
public.marketplace_cm_verified_links
public.marketplace_cm_expansion_rules
```

`marketplace_cm_verified_links` is the fast path for exact product links:

- `blueprint_id`
- `cardmarket_locale`
- canonical `cardmarket_url`
- product slug, card name, expansion, collector number
- source, confidence, notes, verification timestamps

`marketplace_cm_expansion_rules` stores reusable expansion parsing knowledge:

- Pokoin/CardTrader expansion name and code
- Cardmarket expansion slug
- Cardmarket set or context code
- number format rule
- card-type scope
- confidence and notes

Runtime redirect order:

1. Exact verified link from `marketplace_cm_verified_links`.
2. Compatibility lookup in `marketplace_cm_product_parsing`.
3. Candidate generation from `marketplace_cm_expansion_rules`.
4. Code fallback maps only when the database has no rule.
5. Search fallback only when a direct product URL is not safe.

## Canonical URL Form

Known Cardmarket single-card URL shape:

```text
https://www.cardmarket.com/<locale>/Pokemon/Products/Singles/<ExpansionSlug>/<ProductSlug>
```

Example supplied by the user:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Chaos-Rising/Mega-Greninja-ex-V1-CRI022
```

Confirmed Pokoin/CardTrader example:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Call-of-Legends/Dialga-CLSL02
```

## URL Parameters

`scheme`:
Always `https`.

`host`:
Always `www.cardmarket.com` for public product pages.

`locale`:
The first path segment after the host. Examples seen: `it`, `en`.

Default candidate generation should use `en`. The locale changes the public URL,
and verified mappings can use other locales such as `it` or `es`, but new random
samples should not default to `it`.

`game`:
Always `Pokemon` for Pokémon TCG products.

`section`:
Observed as `Products`.

`product_type`:
Observed as `Singles` for card singles.

Possible future product types to investigate:

- `Boosters`
- `Booster-Boxes`
- `Theme-Decks`
- `Boxes`
- `Accessories`

Only `Singles` is covered by the current sampler.

`ExpansionSlug`:
Cardmarket's slug for the expansion, for example:

- `Call-of-Legends`
- `Chaos-Rising`
- `Single-Strike-Master`

This often looks like simple title-case hyphenation, but it must be treated as a
Cardmarket field because Japanese sets, decks, promos, and special products can
have names that differ from CardTrader/Pokoin expansion names.

`ProductSlug`:
The final path segment. This is the important part for mapping.

Observed pattern:

```text
<CardNameSlug>[-<VariantMarker>]-<CardmarketSetCode><CollectorCode>
```

Important ordering nuance:
Pokémon card URLs often include the product code. Confirmed by user:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Unbroken-Bonds/Togekiss-UNB138
```

Trainer card URLs can omit the product code entirely and use only the product
name slug. Confirmed by user:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Night-Unison/Surprise-Box
https://www.cardmarket.com/en/Pokemon/Products/Singles/Rising-Fist/Training-Center
```

This means candidate generation must include both forms. For Pokémon cards,
code-suffixed candidates should be tried first. For Oracle rows whose
`card_type` is trainer/supporter/item/stadium/tool/energy, name-only candidates
should be tried first.

## Product Slug Parameters

`CardNameSlug`:
The card name slug as Cardmarket displays it.

Observed transformations:

- Spaces become hyphens.
- Apostrophes are usually removed or treated as separators.
- Accents should be normalized away for candidate generation.
- Some descriptive rarity words from Pokoin/CardTrader should not be included.

Examples:

- `Dialga Shiny Rare` should become `Dialga`, not `Dialga-Shiny-Rare`.
- `Mega Greninja ex` becomes `Mega-Greninja-ex`.
- `Professor Cozmo's Discovery` candidate becomes
  `Professor-Cozmo-s-Discovery`.

Known risk:
Cardmarket may use a slightly different official name than CardTrader, especially
for Japanese products, owner Pokémon, delta species, LV.X, ex/EX, and localized
names.

`VariantMarker`:
An optional token between the card name and product code.

Confirmed from the user example:

```text
Mega-Greninja-ex-V1-CRI022
```

Here `V1` is a version/variant marker.

Rules not fully known:

- When `V1`, `V2`, etc. are required.
- Whether Cardmarket uses other variant markers.
- Whether variants correspond to CardTrader `product_variant`, card image
  variants, artwork variants, language, or another Cardmarket-only concept.
- Do not replace this path with a raw `idProduct` query. `card_market_ids` can
  identify the same product internally, but user-facing links should use the
  canonical slug path.

Candidate generation should try both:

- With the variant marker, when known.
- Without the variant marker.

`CardmarketSetCode`:
The set abbreviation used by Cardmarket in the product code.

Examples:

- `CL` for `Call of Legends`.
- `CRI` for `Chaos Rising`.

This is not always the same as CardTrader's expansion code. For example,
CardTrader local expansion metadata has `clo` for Call of Legends, but
Cardmarket uses `CL`.

This must become a curated mapping table.

`CollectorCode`:
The collector number portion after the Cardmarket set code.

Observed cases:

- Normal numeric: `44` can remain `44`, as in `Flareon-CL44`.
- Modern padded numeric: `22` can become `022`, as in `CRI022`.
- Special prefixed: `SL2` becomes `SL02`, as in `CLSL02`.

## Known Cases

Normal numeric without three-digit padding:

```text
https://www.cardmarket.com/en/Pokemon/Products/Singles/Call-of-Legends/Flareon-CL44
```

Parameters:

- Expansion: `Call of Legends`
- Cardmarket set code: `CL`
- Collector number: `44`
- Product code: `CL44`

Special prefixed number with two-digit padding:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Call-of-Legends/Dialga-CLSL02
```

Parameters:

- Pokoin/CardTrader blueprint ID: `112492`
- Card: `Dialga`
- Expansion: `Call of Legends`
- Collector number: `SL2`
- Cardmarket set code: `CL`
- Cardmarket collector code: `SL02`
- Product code: `CLSL02`

Versioned/variant marker:

```text
https://www.cardmarket.com/it/Pokemon/Products/Singles/Chaos-Rising/Mega-Greninja-ex-V1-CRI022
```

Parameters:

- Expansion: `Chaos Rising`
- Card: `Mega Greninja ex`
- Variant marker: `V1`
- Cardmarket set code: `CRI`
- Collector number: `022`
- Product code: `CRI022`

Storming Emergence Abundant trainer variant:

```text
https://www.cardmarket.com/en/Pokemon/Products/Singles/Storming-Emergence-Abundant/Cynthia-V2-CSM1cC186
```

Parameters:

- Pokoin/CardTrader blueprint ID: `370392`
- Expansion: `CSM1c: Storming Emergence - Abundant`
- Cardmarket expansion slug: `Storming-Emergence-Abundant`
- Card: `Cynthia`
- Variant marker: `V2`
- Cardmarket set code: `CSM1cC`
- Collector number: `186/151`
- Product code: `CSM1cC186`

User-corrected sample exceptions:

```text
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

Rules learned:

- WCD products can require a deck/player context code, such as `WCD07CG-088`.
- WCD 2006 can require player/deck context codes such as `WCD06LM-016`, plus
  variant markers.
- `Neo Discovery` uses Cardmarket code `NDI`; do not infer a variant marker just
  because multiple local rows have the same card name.
- `S-P: Sword & Shield Promos` can map to
  `Sword-Shield-Simplified-Chinese-Promos` and `S-PCS081` style product codes.
- Promo expansions need curated Cardmarket codes: `SWSH` for SWSH Black Star
  Promos and `OSSM` for some SM Black Star Promos.
- Chinese set slugs often drop the CardTrader prefix:
  `CS1b: Dynamax Clash - Flame` -> `Dynamax-Clash-Flame`.
- `MEGA Start Deck 100 Battle Collection` can use mixed-case `mC` product
  codes, e.g. `Arvens-Mabosstiff-ex-mC484`.
- `Mega Brave` can require both a variant marker and a mixed-case product code,
  e.g. `Mega-Venusaur-ex-V2-m1L076`.
- `Perfect Order` can use `POR` product codes and require a variant marker,
  e.g. `Decidueye-ex-V1-POR012` and `Mega-Zygarde-ex-V2-POR104`.
- `Paldean Fates` uses `PAF` product codes; known numbered rows such as
  `Mew-ex-V2-PAF232` should remain direct product URLs, not search fallbacks.
- Local variants such as `EX` are not Cardmarket `Vn` markers. Preserve the
  inferred duplicate-name marker separately so `V1`/`V2` is not dropped.
- Manual/refinement URLs must be persisted as exact slugs; never rebuild a
  user-verified URL from parts if that would drop a marker like `V2`.
- XY Black Star Promos can use `XYPR` plus the printed XY promo number
  (`XYPRXY141`, `XYPRXY67a`) and may require `Vn`.
- Additionals/reverse-holo products can live under Cardmarket-specific
  additionals slugs, e.g. `White-Flare-Additionals` with `xWHT`.
- Local names may differ from Cardmarket product names; preserve the verified
  product slug, e.g. local `Rescue` -> `Pokemon-Rescue-Pt4080`.
- `EX Holon Phantoms` maps to Cardmarket slug `EX-Holon-Phantoms` and `HP`
  product codes, e.g. blueprint `116587` -> `Mew-ex-HP100`.
- `Astral Radiance` Trainer/Item rows can be code-suffixed; do not make this
  expansion name-only just because the card is a Trainer, e.g. `Sweet-Honey-ASR153`.
- `Pokemon Misprints` is not a reliable per-card Cardmarket singles section;
  Pokoin should show an explanatory popup instead of redirecting.

## Collector Number Cases

Plain integer:

```text
44
```

Candidates:

- `<SetCode>44`
- `<SetCode>044`
- `<SetCode>0044` only if later evidence requires it.

Three-digit collector:

```text
022/182
```

Candidate collector number:

```text
022
```

Candidates:

- `<SetCode>022`
- `<SetCode>22`
- `<SetCode>02`

Special prefix:

```text
SL2
```

Candidate collector code:

```text
SL02
```

Candidates:

- `<SetCode>SL02`
- `<SetCode>SL2`
- `<SetCode>SL002`

Noisy collector string:

```text
Holo Rare | 012/020
```

Normalize to:

```text
012/020
```

Noisy special string:

```text
Shiny Rare | SL2
```

Normalize to:

```text
SL2
```

Unnumbered cards:

```text
Unnumbered
```

Current sampler generates a candidate like:

```text
<SetCode>UNNUMBERED
```

This is probably not sufficient. Unnumbered cards need manual Cardmarket lookup
or a stronger imported ID source.

Stamp-number cards:

```text
Stamp Number 23
```

Current sampler normalizes to:

```text
23
```

This may be wrong for decks/promos where Cardmarket uses deck-specific product
codes.

## Card Type Cases

Pokémon:
Usually `CardNameSlug` plus product code.

Trainer/Supporter/Item/Stadium:
Usually same structure, but punctuation and apostrophes need careful slugging.

Energy:
Basic energy can be unnumbered or repeated across products. Do not persist a
Cardmarket URL unless verified.

Special rarity cards:
Rarity words from Pokoin/CardTrader such as `Holo Rare`, `Ultra Rare`,
`Full-Art`, `Rainbow Secret Rare`, `Gold Secret Rare`, and `Shiny Rare` may
appear in noisy number/name fields. They are not automatically part of the
Cardmarket product slug.

Owner Pokémon:
Names like `Cynthia's Garchomp ex` need apostrophe handling and may vary by
localization.

Delta Species:
CardTrader names can contain `δ Delta Species`. Cardmarket may use `delta`,
`Delta-Species`, omit one part, or encode the symbol differently. Candidate URLs
for these should be treated as low confidence until verified.

LV.X:
Names like `Dialga G LV.X` can become `Dialga-G-LV-X`, but Cardmarket casing and
punctuation should be verified.

Japanese sets and constructed decks:
CardTrader expansion codes like `s5l`, `pt1`, or deck-specific codes are often
not Cardmarket set codes. Candidates are useful for research but low confidence.

## Direct URL Readiness

The generator should know when it does not have enough information for a safe
Cardmarket product URL. A direct product URL is ready only when these pieces are
known or verified:

- Cardmarket expansion slug.
- Cardmarket set code, context code, or verified name-only rule.
- Collector number formatting for that expansion.
- Variant marker requirement (`V1`, `V2`, etc.) or verified absence of one.
- Cardmarket card-name slug.

If any piece is missing or only weakly inferred, the product URL should remain a
candidate and the UI/report should prefer a fallback search URL. This is
especially important for Japanese, Chinese, promo, deck, WCD, and duplicate-name
variant cases.

Weak API bridges are not enough on their own. For example, TCGdex ids such as
`sm12`, `xy8`, and `swsh3` helped identify the set family, but Cardmarket used
`CEC`, `BKT`, and `DAA` in product slugs. Without a curated bridge table, those
API ids should not be emitted as direct Cardmarket product codes.

## Fallback Search URLs

When a blueprint has no verified Cardmarket product URL and generated candidates
are incomplete, use a narrowed Cardmarket singles search URL as a fallback. This
keeps users on Cardmarket results instead of sending them to a guessed product
slug.

Template:

```text
https://www.cardmarket.com/en/Pokemon/Products/Singles?searchMode=v2&idCategory=51&idExpansion=0&searchString=<encoded card name>&idRarity=0&perSite=30
```

Example for an unresolved `Reshiram GX`:

```text
https://www.cardmarket.com/en/Pokemon/Products/Singles?searchMode=v2&idCategory=51&idExpansion=0&searchString=reshiram&idRarity=0&perSite=30
```

Do not treat this as a verified product URL. It is a temporary search fallback
until the exact `/Products/Singles/<ExpansionSlug>/<ProductSlug>` path is found.

## Data Needed for Reliable Automation

Do not assume Cardmarket URLs can be generated from CardTrader blueprint IDs
alone. A reliable association table should store:

- `blueprint_id`: CardTrader/Pokoin card ID.
- `card_name`: Pokoin/CardTrader name used during matching.
- `cardmarket_name`: Cardmarket product name if different.
- `expansion_name`: Pokoin/CardTrader expansion.
- `cardmarket_expansion_slug`: Cardmarket expansion path segment.
- `collector_number`: Original Pokoin/CardTrader collector number.
- `normalized_collector_number`: Cleaned number used for matching.
- `cardmarket_set_code`: Curated Cardmarket set code.
- `cardmarket_collector_code`: Collector code after padding/prefix rules.
- `cardmarket_variant_marker`: `V1`, `V2`, etc. when required.
- `cardmarket_product_slug`: Final path segment.
- `cardmarket_locale`: `it`, `en`, etc.
- `cardmarket_url`: Full verified URL.
- `match_status`: `candidate`, `verified`, `rejected`, or `manual`.
- `confidence`: Numeric confidence score or label.
- `verified_at`: Timestamp of verification.
- `verification_method`: `manual`, `http`, imported feed, etc.
- `verification_source`: URL, operator, or script run.
- `notes`: Human notes for exceptions.

Suggested Oracle table:

```sql
public.marketplace_cm_product_parsing
```

Suggested uniqueness:

```sql
unique (blueprint_id, cardmarket_locale)
```

Optional supporting table:

```sql
public.marketplace_cm_expansion_parsing
```

Suggested fields:

- `expansion_name`
- `cardtrader_expansion_code`
- `cardmarket_expansion_slug`
- `cardmarket_set_code`
- `locale`
- `verified_at`
- `notes`

Implemented table names:

- `public.marketplace_cm_expansion_parsing`: Cardmarket expansion slug, set code,
  context code, and number-format rules.
- `public.marketplace_cm_product_parsing`: per-blueprint Cardmarket product slug,
  URL, variant marker, context code, status, confidence, and verification notes.

User-verified cases should be inserted into these tables instead of only tuning
heuristics. The generator can still propose candidates, but these parsing tables
are the durable source of truth for known Cardmarket differences.

## Candidate Generation Algorithm

1. Resolve card metadata from `marketplace_card_versions` or a card API.
2. Normalize card name into candidate `CardNameSlug`.
3. Normalize expansion name into candidate `ExpansionSlug`.
4. Look up curated `CardmarketSetCode`.
5. Normalize collector number.
6. Generate collector-code candidates:
   - Numeric original.
   - Numeric padded to 2 digits.
   - Numeric padded to 3 digits.
   - Special prefix with numeric padded to 2 digits.
   - Special prefix with raw numeric.
   - Special prefix with numeric padded to 3 digits.
7. Generate product slug candidates:
   - Name-only slug.
   - Without variant marker.
   - With known variant marker, if present.
8. Verify candidates.
9. Store only verified mappings as active.

## Verification Workflow

1. Start from a Pokoin card URL and extract the blueprint ID from the first
   numeric segment.
2. Resolve metadata from `marketplace_card_versions` or the existing card API.
3. Look up the expansion's Cardmarket set code from a curated mapping table.
4. Generate candidate product slugs.
5. Verify candidates against Cardmarket before storing them.
6. Store confirmed URLs in `marketplace_cardmarket_products`.
7. Keep rejected candidates for debugging if useful.

Do not run large automated verification batches repeatedly against Cardmarket.
Automated `HEAD` checks may be blocked or rate-limited, and unconfirmed rows
must be treated as candidates only.

## 100-Blueprint Sampling Workflow

Sampler:

```bash
node scripts/cardmarket-association-sampler.js --limit=100 --verify=0
```

Verification smoke test:

```bash
node scripts/cardmarket-association-sampler.js --limit=10 --verify=1
```

What it does:

- Samples 100 real card rows from Oracle when `MARKETPLACE_DATABASE_URL` is set
  or the sibling `pokoinpos/deploy/env/peer4-postgres.env` workflow file is
  available.
- Falls back to live Pokoin marketplace expansion APIs when Oracle is not
  reachable.
- Enriches sampled rows with local CardTrader expansion codes from
  `data/cardtrader/pokemon-expansions.json`.
- Normalizes collector numbers from noisy strings.
- Generates candidate Cardmarket URLs.
- Writes reports to `workflows/reports/cardmarket-association-sample-*.md`.

Latest sample report:

```text
workflows/reports/cardmarket-association-sample-2026-05-19T12-05-28-170Z.md
```

The latest 100-row run used the Oracle marketplace database through the
`pokoinpos/deploy/env/peer4-postgres.env` workflow file. It sampled 100 random
database blueprints across 88 expansions, produced candidate URLs for all 100
rows, and used `--verify=0`, so it did not mark any candidate as confirmed.

Observed from the Oracle sample:

- `missingSetCode`: `0/100`.
- Rows whose number fell back to a blueprint ID: `1/100`.
- Constructed deck / world championship / starter-deck style rows: `14/100`.
- The candidate formatter handled noisy rarity prefixes such as
  `Secret Rare | 168/156`, `Holo Promo | SM28`, and `Yu Nagaba Art`.
- Several samples still look low-confidence because Cardmarket set slugs/codes
  for Japanese, constructed deck, prize pack, and special reverse-holo products
  are unlikely to match simple CardTrader expansion slugs.

Latest verification smoke test:

```text
workflows/reports/cardmarket-association-sample-2026-05-19T12-02-19-434Z.md
```

The 10-row verification smoke test also fell back to the live API. All generated
Cardmarket `HEAD` checks returned `403`, so `HEAD` is not a reliable verification
method by itself. This does not prove the candidate URLs are wrong; it shows that
verification needs a different approach, such as cautious `GET` checks, a
Cardmarket-friendly import/feed, or manual review.

Refinement still needed before relying on this workflow:

- Store both raw `expansion_code` and normalized Cardmarket set code in reports;
  current reports show raw lower-case/local codes such as `xy4`, while generated
  URLs use upper-case normalized codes like `XY4`.
- Improve constructed deck, world championship, prize-pack, and special
  reverse-holo handling. These rows should be marked low-confidence/manual unless
  backed by a curated Cardmarket expansion mapping.
- Treat purely textual collector fields, such as energy abbreviations without a
  number, as no-candidate/manual rows instead of generating product codes that
  contain punctuation.
- Change `fetchLiveApiRows` to sample across the flattened card pool, or take a
  small randomized quota per expansion, so fallback samples are representative.
- Avoid treating `HEAD 403` as a candidate rejection; record it as `blocked` or
  `unverified`.

## Known Confirmed Mappings

| Blueprint ID | Card | Expansion | Collector | Cardmarket URL |
| --- | --- | --- | --- | --- |
| `112492` | `Dialga` | `Call of Legends` | `SL2` | `https://www.cardmarket.com/it/Pokemon/Products/Singles/Call-of-Legends/Dialga-CLSL02` |

## Known Unknowns

- Exact Cardmarket set code for every CardTrader expansion.
- Whether normal numeric padding is expansion-specific, era-specific, or
  product-type-specific.
- When variant markers like `V1` are required.
- Whether product slugs differ across locales.
- How Cardmarket encodes Japanese deck cards, unnumbered cards, stamp-numbered
  cards, promos, and energy cards.
- Whether Cardmarket has an importable product ID feed or API that can replace
  heuristic URL generation.
