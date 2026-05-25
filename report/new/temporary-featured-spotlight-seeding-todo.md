# TODO: Replace Temporary Featured And Spotlight Seeding

## Current Temporary Behavior

`api/marketplace-home.js` currently replaces the home snapshot's `bestSellerIds`
and `featuredIds` with deterministic pseudo-random cards from
`public.marketplace_cards`.

The seed is intentionally temporary:

```text
hash(generated timestamp + section name + placement + old card name)
  % total marketplace blueprint/card projection count
```

The selected index is used as an offset into `marketplace_cards`, ordered by
`card_id`. This gives `Featured` and the `Card spotlight` source fresher-looking
cards while the real recommendation/curation system is unfinished.

## Real Implementation Needed

- Create proper featured and spotlight selection logic instead of random seeded
  offsets.
- Keep `Featured` distinct from `Card spotlight` so the same small set of cards
  does not dominate both sections.
- Use marketplace signals when available:
  - recent views
  - clicks
  - cart adds
  - completed sales
  - seller inventory availability
  - freshness/import recency
- Add manual curation or admin override support for launch campaigns.
- Avoid showing rows without usable card imagery.
- Add a smoke test for `/api/marketplace-home` verifying non-empty, distinct
  section IDs and card payloads.

## Files To Revisit

- `api/marketplace-home.js`
- `lib/screens/home_screen.dart`
- `supabase/migrations/*marketplace*_snapshot*.sql` or a new marketplace home
  recommendation migration
- `workflows/card-market-page-workflow.md`
