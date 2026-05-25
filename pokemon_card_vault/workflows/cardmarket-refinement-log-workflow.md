# Cardmarket Refinement Log Workflow

Use this workflow when the debug refinement page has collected human-corrected
Cardmarket URLs.

The refinement queue intentionally includes both:

- `candidate_review` rows, where the parser generated an unverified candidate.
- `verified_audit` rows, where Pokoin already has a stored verified/manual URL
  and a human is spot-checking whether it is still correct on Cardmarket.

## Capture

1. Open `/marketplace/debug/refinement` with a debug-enabled account.
2. Click the row's Cardmarket button to inspect the generated candidate.
3. If the candidate is wrong, paste the correct Cardmarket singles URL into the
   textbox under the card image. The UI autosaves valid Cardmarket singles URLs.
4. Use `Save now` only when you want to force a save before the autosave fires.

Each saved row is written to `public.marketplace_cm_refinement_log` with:

- `blueprint_id`
- pasted Cardmarket URL
- generated candidate URL
- card name, expansion, collector number
- Cardmarket product IDs from CardTrader metadata, when present
- debug user identity
- `pending` status

The save path also upserts the pasted URL into
`public.marketplace_cm_verified_links` as a manual fast-track link. The log stays
as the review/audit trail; the verified-link table is what redirects should read
first.

## Review Pending Rows

Read the pending log entries:

```sql
select
  id,
  blueprint_id,
  card_name,
  expansion_name,
  collector_number,
  candidate_cardmarket_url,
  pasted_cardmarket_url,
  cardmarket_ids,
  created_at
from public.marketplace_cm_refinement_log
where status = 'pending'
order by created_at asc;
```

## Promote To Parser

For each pending row:

1. Validate that `pasted_cardmarket_url` is a canonical Cardmarket
   `/Pokemon/Products/Singles/<ExpansionSlug>/<ProductSlug>` URL.
2. Extract:
   - Cardmarket expansion slug.
   - Cardmarket card-name slug.
   - Variant marker such as `V1` or `V2`, if present.
   - Cardmarket set/context code and collector-number formatting.
3. Add or update SQL seeds in
   `oracle-postgres/schema/007_cardmarket_parsing_seeds.sql`:
   - `marketplace_cm_verified_links` for the exact `blueprint_id` ->
     `cardmarket_url` fast path.
   - `marketplace_cm_product_parsing` for the exact blueprint.
   - `marketplace_cm_expansion_rules` when the row proves a reusable
     expansion-level rule.
   - `marketplace_cm_expansion_parsing` for compatibility/history.
4. Add code fallbacks only when needed for local/offline tooling. The runtime
   source of truth is the database.
5. Update `workflows/cardmarket-parsing-workflow.md` and
   `workflows/cardmarket-product-association-report.md` with any reusable rule.
   Examples of reusable rules from refinement logs:
   - Astral Radiance Trainer/Item cards can still be code-suffixed
     (`Sweet-Honey-ASR153`), so do not globally make Trainer rows name-only.
   - Perfect Order uses `POR` product codes and ultra/full-art duplicates can
     need `V1`/`V2`.
   - World Championship Decks 2006 uses deck/player context codes such as
     `WCD06LM`; this cannot be derived from CardTrader expansion code alone.
6. Apply schema/seeds to the live database before deploying runtime changes:

```bash
node scripts/oracle-marketplace-migrate.js --schema-only
```

If that helper is not appropriate for the current environment, apply
`oracle-postgres/schema/001_marketplace_core.sql` and
`oracle-postgres/schema/007_cardmarket_parsing_seeds.sql` with the same
production `MARKETPLACE_DATABASE_URL`.

7. Run focused validation:

```bash
node --check api/cardmarket-redirect.js
node --check scripts/cardmarket-association-sampler.js
node scripts/cardmarket-association-sampler.js --blueprint-id=<id> --verify=0
```

## Mark Processed

After the verified-link table, parser/seeds, and docs are updated, mark the log
row as implemented:

```sql
update public.marketplace_cm_refinement_log
set status = 'implemented',
    implemented_at = now(),
    notes = concat_ws(E'\n', nullif(notes, ''), 'Implemented in parser/seeds.')
where id = <log_id>;
```

If the pasted URL turns out not to be a specific product page, mark it rejected:

```sql
update public.marketplace_cm_refinement_log
set status = 'rejected',
    notes = concat_ws(E'\n', nullif(notes, ''), 'Rejected: not a canonical product URL.')
where id = <log_id>;
```

Do not copy fallback/search URLs into `marketplace_cm_verified_links` or
`marketplace_cm_product_parsing`. Only persist confirmed product URLs there.
