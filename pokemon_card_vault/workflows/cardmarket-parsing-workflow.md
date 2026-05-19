# Cardmarket Parsing Workflow

Use this workflow when mapping Pokoin/CardTrader blueprint IDs to Cardmarket
product URLs.

Cardmarket URLs are not reliably derivable from CardTrader metadata alone. The
sampler can propose candidates, but verified case-by-case corrections must be
stored in Oracle so future candidate generation learns from them.

## Source Of Truth

Oracle stores the durable parsing layer:

```sql
public.marketplace_cm_expansion_parsing
public.marketplace_cm_product_parsing
```

`marketplace_cm_expansion_parsing` stores expansion-level Cardmarket rules:

- CardTrader/Pokoin expansion name and code.
- Cardmarket locale and expansion slug.
- Cardmarket set code.
- Cardmarket context code for special products such as World Championship decks.
- Number format rule.
- Card type scope, such as `pokemon` or `trainer`.
- Confidence and notes.

`marketplace_cm_product_parsing` stores per-blueprint verified mappings:

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
```

Observed transformations:

- Apostrophes may be removed, not replaced with hyphen:
  `Hop's Zacian ex` -> `Hops-Zacian-ex`.
- Accents are normalized out:
  `Pokémon Fan Club` -> `Pokemon-Fan-Club`.
- Cardmarket set-code casing can matter:
  `m2a123`, `CSM1cC143`, `UNB138`.
- Cardmarket set code can differ from CardTrader code:
  Skyridge is `SK` on Cardmarket while Oracle/CardTrader stores `skg`;
  Start Deck 100 is `sI100` while Oracle/CardTrader stores `sl`.
- Main-set collector numbers can preserve leading zeroes:
  `079/094` -> `PFL079`.
- Cardmarket context code can be distinct:
  `WCD18CIN-057` for a World Championship deck card, `TK9S-29` for a Trainer Kit
  card.
- Duplicate-name variants can use `Vn`:
  Ambipom `079/094` is `Ambipom-V1-PFL079`, while Ambipom `107/094` is
  `Ambipom-V2-PFL107`.
- Trainer products can be name-only:
  `Training-Center`, `Surprise-Box`.
- Trainer products can also be code-suffixed in other expansions:
  `Forest-Guardian-AQ123`.

## Candidate Generation

Run a random Oracle-backed candidate sample:

```bash
node scripts/cardmarket-association-sampler.js --limit=100 --verify=0
```

Run a small verification smoke test:

```bash
node scripts/cardmarket-association-sampler.js --limit=10 --verify=1
```

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
- A Cardmarket-friendly data feed/API if one becomes available.
- Very small cautious `GET` checks only if needed, not large automated batches.

Do not persist generated candidates as verified. Persist only confirmed mappings.

## Adding A User-Verified Mapping

When the user provides a correct URL:

1. Identify the blueprint ID from the Pokoin/CardTrader row.
2. Parse the Cardmarket URL:
   - locale
   - expansion slug
   - product slug
   - variant marker if present
   - set code or context code if present
3. Upsert `marketplace_cm_expansion_parsing`.
4. Upsert `marketplace_cm_product_parsing`.
5. Add notes explaining what was learned.
6. Update `workflows/cardmarket-product-association-report.md` if the case
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

Expansion parsing rows seeded: `7`.

Product parsing rows seeded: `8`.

Seeded blueprints:

- `130677`: `Togekiss-UNB138`.
- `141860`: `Training-Center`.
- `320561`: `Buzzwole-GX-WCD18CIN-057`.
- `359203`: `Hops-Zacian-ex-m2a123`.
- `370349`: `Pokemon-Fan-Club-V1-CSM1cC143`.
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
