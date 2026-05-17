# Card Market Page Workflow

Use this workflow when future agents need to build or revise the card detail
marketplace page at `/card/:id`.

## Goal

The card page should feel like a collectible asset terminal:

- CardTrader-style card identity, best deal, condition/language selectors,
  filters, seller rows, quantity, and custody/trust badges.
- CoinMarketCap/DEX-style quote panel, chart, market statistics, spread,
  liquidity, volume, and trade/offer controls.
- Pokoin-native pricing in PKN, with fiat shown only as supporting context.

## Reference Inputs

When the user provides a CardTrader page or screenshots, extract:

- Card name, set, rarity, collector number, language, and condition model.
- Best deal and market price placement.
- Listings table columns: seller, product badges, price, quantity, Zero/custody,
  cart action.
- Filters: price, condition, language, signed/altered/graded/Zero.

When the user references CoinMarketCap or DEX pages, extract:

- Prominent current price/floor quote.
- Compact stat cards: volume, market cap, listings, liquidity, spread.
- Chart area with time-series feel.
- Market/order-book tabs and trade panel semantics.

## Current Implementation

Primary files:

- `lib/screens/card_detail_screen.dart`
  - Owns the `/card/:id` UI.
  - Uses `cardProvider` for local cards.
  - Uses deterministic local mock data via `_CardMarketData` and `_Listing`.
  - Handles loading and not-found states for deep links.
- `lib/screens/home_screen.dart`
  - `_MarketCard` and `_FeaturedCard` navigate to `/card/${card.id}`.
- `lib/main.dart`
  - Already defines the `/card/:id` route.

The first production-looking version is intentionally UI-first. Do not create
Supabase order-book tables unless the user explicitly asks for real inventory.

## Safe Change Steps

1. Inspect the current route and screen:
   ```bash
   rg "path: '/card/:id'|CardDetailScreen" lib/main.dart lib/screens
   ```

2. Update `lib/screens/card_detail_screen.dart`:
   - Keep the dark marketplace style used by `HomeScreen`.
   - Preserve loading and not-found states.
   - Keep market/listing mock data deterministic from `card.id` until real APIs
     are requested.
   - Prefer private widgets/classes in the same file while the feature is still
     evolving.

3. Update card entry points in `lib/screens/home_screen.dart`:
   - Make card surfaces clickable with `context.go('/card/${card.id}')`.
   - Keep favorite/cart icon actions from accidentally swallowing or breaking
     card navigation.

4. Verify:
   ```bash
   dart format lib/screens/card_detail_screen.dart lib/screens/home_screen.dart
   flutter analyze lib/screens/card_detail_screen.dart lib/screens/home_screen.dart
   flutter build web --debug
   ```

5. Manually check:
   - `/card/1` renders the terminal page.
   - `/card/unknown` shows a clean not-found state.
   - Marketplace and featured cards open `/card/:id`.

## Future Real Data Upgrade

When moving from mock listings to real order book data, add an API layer instead
of wiring Supabase directly into widgets. Suggested direction:

- `api/card-market.js` or equivalent serverless endpoint.
- Supabase tables for listings, sellers, inventory quantity, condition,
  language, custody status, and price in PKN.
- Flutter service/provider that returns a `CardMarket` model.
- Keep `_CardMarketData` shape or migrate it into a public model to minimize UI
  churn.

Do not overwrite existing CardTrader blueprint import data. The blueprint table
is catalog metadata; seller listings/order book should be separate.
