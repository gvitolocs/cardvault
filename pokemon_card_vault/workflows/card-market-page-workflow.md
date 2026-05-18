# Card Market Modification Workflow

Use this workflow for every future change to the Pokoin Card Reserve market,
especially `/marketplace`, `/card/:id`, seller listings, cart, and checkout.

## Product Direction

- The card page must not regress to a static mockup.
- Card identity and images come from the Supabase CardTrader blueprint catalog.
- Seller listings, cart entries, and pending orders live in Firebase/Firestore.
- The UI should stay dark and Pokoin-branded, not white shop-template styling.
- Pricing is Pokoin-first. Show PKN clearly; fiat can be secondary context.
- Do not show CardTrader-specific labels such as `CT Min Price` or
  `CT Market Price` in the graph panel.

## Current Data Flow

- `lib/services/card_service.dart`
  - Loads lightweight marketplace projections before the heavy blueprint table.
  - Uses `marketplace_cards` for homepage/catalog/search preview card rows.
  - Uses `/api/marketplace-home` for dynamic carousel sections. That endpoint
    returns both section IDs and a card payload; merge `snapshot.cards` into
    `CardState.cards` before resolving carousel IDs, otherwise Best sellers and
    Featured can render empty when their IDs are not in the capped catalog load.
  - Uses `marketplace_card_versions` for expansion-scoped navigation and full
    search result rows.
  - Fetches a single `cardtrader_pokemon_blueprints` row only when `/card/:id`
    needs full card detail not already loaded.
  - Falls back to Hive cache and then local sample cards only when remote data is
    unavailable.
- `lib/providers/card_listing_provider.dart`
  - Streams active `card_listings` from Firestore by `cardId`.
- `lib/models/card_listing.dart`
  - Defines seller listing fields: condition, language, reverse holo, signed,
    graded, grading company, grade, shipping, NFT, seller snapshot, card
    snapshot, price, and quantity.
- `lib/providers/cart_provider.dart`
  - Stores listing-aware cart entries keyed by listing id.
- `lib/screens/card_detail_screen.dart`
  - Owns `/card/:id`, sell dialog, real listing table, no-seller state, and
    chart/market panels.
  - Loads the ordered version list for the current expansion once through
    `CardService.getExpansionVersionCards(...)`; previous/next is computed
    locally from that cached list.

## Supabase Projection Tables

- `public.marketplace_cards`
  - Lightweight marketplace card rows for home, search preview, and catalog
    surfaces.
  - Refreshed by `public.refresh_marketplace_cards_from_blueprints()`.
- `public.marketplace_card_events`
  - Analytics input for dynamic home sections and rolling 24h marketplace
    signals.
- `public.marketplace_card_versions`
  - Minimal ordered version/navigation rows:
    `card_id`, `name`, `expansion_name`, `expansion_number`,
    `expansion_number_int`, `blueprint_id`, and image URLs.
  - Refreshed by `public.refresh_marketplace_card_versions()`.
  - Use this table for `/card/:id` previous/next and version search. Do not
    parse the heavy blueprint JSON in the client for navigation.

## Required Checks Before Editing

1. Search for the current implementation points:
   ```bash
   rg "CardDetailScreen|cardListingsProvider|CardListing|_CardMarketData|Sell this card" lib
   ```
2. Confirm the requested change affects one of these surfaces:
   - catalog card data
   - seller listing form
   - listing table actions
   - market chart/stats
   - cart/checkout listing behavior
   - no-seller state

## Implementation Rules

- Do not reintroduce deterministic fake sellers as the main data source.
- If a card has no seller listing, render a CardTrader-like empty state:
  `No items found`, wishlist action, and `Sell this card`.
- Every actionable listing row must refer to a real Firestore listing id.
- Cart buttons must add the exact selected listing, not just the generic card.
- Seller-created listings must persist to Firestore and appear realtime.
- Graded listings must capture both grading company and grade.
- Reverse holo should be a first-class listing option because it is common.
- Keep old catalog blueprints intact. They are metadata, not mutable inventory.
- The marketplace home/catalog can be capped for performance. Do not assume
  `CardState.cards` contains every card.
- The marketplace home carousel sections must not depend only on the capped
  catalog. Use the `MarketplaceHomeSnapshot.cards` payload to hydrate section
  IDs, then fall back per section if some IDs are unavailable.
- Full search and "View all versions" style results must call Supabase projection
  data directly, not just filter the loaded home catalog.
- Previous/next must stay within the exact same expansion name. Load the whole
  expansion list once and calculate next/previous locally; do not call an
  adjacent-card RPC for every arrow click.

## Card Page Checklist

When changing `lib/screens/card_detail_screen.dart`, verify:

- `/card/:id` loads the real card image from Supabase/CDN when available.
- Previous/next arrows appear when the current expansion has neighboring rows in
  `marketplace_card_versions`.
- Pressing previous/next after the first page load does not create a new
  adjacency database request for every arrow press.
- The graph panel does not show `CT Min Price` or `CT Market Price`.
- The seller table uses `CardListing`, not a local `_Listing` mock.
- The no-listing state works for cards with zero Firestore listings.
- The sell dialog can create a listing for the current user.
- Cart, NFT, and shipping actions stay aligned in the action column.

## Cart And Checkout Checklist

When changing cart or checkout, verify:

- Cart rows display seller, condition, language, reverse, graded, NFT, and
  shipping metadata when available.
- Quantity clamps to the listing's `quantityAvailable`.
- Checkout creates a pending `orders` document with listing snapshots.
- Anonymous users can still use local cart fallback where supported.

## Verification Commands

Run from `pokemon_card_vault`:

```bash
dart format lib/screens/card_detail_screen.dart lib/screens/cart_screen.dart lib/screens/checkout_screen.dart
flutter analyze
flutter test
flutter build web --release --pwa-strategy=none
```

Passing local checks is not the same as updating production. If the user expects
the change on `pokoin.com`, deploy after the checks:

```bash
./deploy-pokoin-web.sh
```

For version/navigation changes, also verify the projection data with the anon
key or SQL editor:

```sql
select public.refresh_marketplace_card_versions();

select card_id, name, expansion_name, expansion_number
from public.marketplace_card_versions
where expansion_name = 'Unified Minds'
order by expansion_number_int nulls last, expansion_number, blueprint_id
limit 20;
```

If Firestore rules changed:

```bash
firebase deploy --only firestore:rules --project "$FIREBASE_CLI_PROJECT_ID"
```

For production deployment, use:

```bash
./deploy-pokoin-web.sh
```

After deploy, verify `https://pokoin.com` rather than assuming a pushed commit
or local build is live.

For homepage/carousel changes, also inspect the production home API:

```bash
python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('https://pokoin.com/api/marketplace-home', timeout=20) as res:
    data = json.loads(res.read().decode())
print('cards', len(data.get('cards') or []))
for key, value in (data.get('sections') or {}).items():
    print(key, len(value or []), (value or [])[:10])
PY
```

Expected: non-zero `cards`, `bestSellerIds`, and `featuredIds`. If the API is
healthy but Flutter carousels are empty, check the provider merge path before
changing Supabase data.
