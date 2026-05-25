# Cardmarket Scrape Observation Workflow

Use this workflow when the Chrome extension is on a Cardmarket product page and
has scraped page context from the browser DOM.

For extension-agent implementation details, including how to reuse the current
Pokoin Firebase bearer token, see
`workflows/pokemon-card-extension-auth-and-cardmarket-api-handoff.md`.

## Purpose

Pokoin should not rely on server-side blind crawling of Cardmarket. The
`pokemon-card-extension` already runs in the user's browser and can read the
Cardmarket product page the user opened. Send that browser-observed data to
Pokoin as an observation.

The API endpoint is:

```text
POST /api/cardmarket-scrape-observation
```

Observations are stored in:

```sql
public.marketplace_cm_scrape_observations
```

The full canonical Cardmarket URL is always stored in
`marketplace_cm_scrape_observations.cardmarket_url`.

When the extension/user has enough confidence to confirm the matched blueprint,
the same request can also promote that full URL into:

```sql
public.marketplace_cm_verified_links
```

## Extension Data Shape

The extension's Cardmarket navigation/parser reads:

- `.page-title-container h1` as the primary title.
- The muted/span text inside the `h1` as expansion context when present.
- Breadcrumb links and the Cardmarket URL expansion slug as fallback expansion
  context.
- Titles like `Piplup (MEP 042)` into structured fields:
  `name`, `collectorNumber`, `collectorNumberPrefix`, `numericCollectorNumber`,
  and `expansion`.

Send the observation after the page scrape/search resolves:

```json
{
  "url": "https://www.cardmarket.com/en/Pokemon/Products/Singles/Dragon-Majesty/Hydreigon-DRM33",
  "title": "Hydreigon (DRM 33)",
  "structuredCard": {
    "rawTitle": "Hydreigon (DRM 33)",
    "name": "Hydreigon",
    "collectorNumber": "DRM 33",
    "collectorNumberPrefix": "DRM",
    "numericCollectorNumber": "33",
    "expansion": "Dragon Majesty"
  },
  "cardmarketContext": {
    "expansion": "Dragon Majesty"
  },
  "match": {
    "cardId": "114322",
    "relevanceScore": 0.98,
    "name": "Hydreigon"
  },
  "promoteVerifiedLink": true,
  "extensionVersion": "1.0.0",
  "source": "pokemon-card-extension"
}
```

The API derives and stores:

- Cardmarket locale.
- Cardmarket expansion slug.
- Cardmarket product slug.
- Scraped name, expansion, collector prefix/number.
- Full structured payload and page context as JSON.
- Optional matched Pokoin/CardTrader blueprint id and score.

If `promoteVerifiedLink` is true and a matched blueprint id is present, the API
also upserts the URL into `marketplace_cm_verified_links` and marks the
observation `verified`. Use this only when the extension/user is submitting a
confirmed exact match, not a generic same-name candidate.

## Promotion

An observation is not automatically a verified link unless a human or very strong
matching rule confirms it. Use this review query:

```sql
select
  id,
  cardmarket_url,
  scraped_name,
  scraped_expansion,
  collector_number,
  matched_blueprint_id,
  match_confidence,
  status,
  observed_at
from public.marketplace_cm_scrape_observations
where status in ('observed', 'matched')
order by observed_at desc
limit 100;
```

Promote a confirmed observation into the fast path:

```sql
insert into public.marketplace_cm_verified_links (
  blueprint_id,
  cardmarket_locale,
  cardmarket_url,
  cardmarket_product_slug,
  card_name,
  expansion_name,
  collector_number,
  source,
  confidence,
  notes,
  verified_at
)
select
  matched_blueprint_id,
  cardmarket_locale,
  cardmarket_url,
  cardmarket_product_slug,
  scraped_name,
  scraped_expansion,
  collector_number,
  'cardmarket-scrape-observation',
  'verified',
  concat('Promoted from scrape observation ', id),
  now()
from public.marketplace_cm_scrape_observations
where id = '<observation-id>'
  and matched_blueprint_id is not null
on conflict (blueprint_id, cardmarket_locale)
do update set
  cardmarket_url = excluded.cardmarket_url,
  cardmarket_product_slug = excluded.cardmarket_product_slug,
  card_name = excluded.card_name,
  expansion_name = excluded.expansion_name,
  collector_number = excluded.collector_number,
  source = excluded.source,
  confidence = excluded.confidence,
  notes = excluded.notes,
  verified_at = excluded.verified_at,
  updated_at = now();
```

Then mark the observation:

```sql
update public.marketplace_cm_scrape_observations
set status = 'verified',
    notes = concat_ws(E'\n', nullif(notes, ''), 'Promoted to marketplace_cm_verified_links.'),
    updated_at = now()
where id = '<observation-id>';
```

## Rules

- Store only canonical `/Pokemon/Products/Singles/...` Cardmarket product URLs.
- Do not store Cardmarket search URLs as observations.
- Do not mark observations verified just because the extension found a generic
  same-name match; require exact name, collector number, and expansion agreement.
- Keep raw structured payloads because they show how the extension parsed the
  page at collection time.
