# Rebuild marketplace search

The normal Rebuild entry point now searches the real catalog through
`GET /api/marketplace-search-page`. The explicit `showDiscovery: false`
diagnostic view retains its existing offline demo behavior.

## Responsibilities

- `model/marketplace_search.dart`: request, typed page and immutable UI state.
- `provider/marketplace_search_provider.dart`: absolute native API URL, JSON
  decoding, canonical identity validation and timeout/cancellation.
- `service/marketplace_search_service.dart`: query normalization and pagination
  validation, short-lived page reuse and artist intersection; no presentation
  or Flutter imports.
- `provider/marketplace_artist_provider.dart`: existing artist-cards endpoint,
  complete-catalog validation and off-UI response preparation.
- `cache/marketplace_search_cache.dart`: 30-second successful pages (up to 16)
  and artist catalogs (up to two). Repeating a fresh query restores results
  immediately; explicit submit/retry still requests a refresh.
- `controller/marketplace_search_controller.dart`: 300 ms debounce, stale
  response protection, filters, retry and pagination.
- `presentation/marketplace/component/marketplace_search.dart`: input and lazy
  result rows; `search_filters.dart` supplies collapsed controls and
  `atomics/search_card_tile.dart` presents previews through shared thumbnails.
- `MarketplaceController` owns the focused search controller; the app root
  supports injected search services for tests and owns controller disposal.

Each query/filter change aborts outstanding HTTP work and resets pagination.
Result IDs remain canonical Pokoin IDs, with no multiplication. Pages use 24
rows and server offsets, retaining server order while deduplicating IDs. A
nullable total stays unknown rather than becoming the number of loaded rows.
Errors remain distinct from a valid empty result; failed additional pages
retain previous cards and retry the same offset. Opening a result requests
real card details through the existing CardDetailsController.

Search previews preserve two image URLs: the small `imageUrl` for result
tiles and `fullImageUrl` for artwork in the details page. Details use the full
URL immediately when supplied by the search/home response, avoiding a first
load of the homepage WebP followed by a second load of the full JPG after
metadata arrives. Home snapshots preserve this optional field; older snapshots
and responses without a full URL continue to fall back to the thumbnail.
Detail image widgets retain their displayed frame during source updates and
are keyed by canonical card ID. A theme/palette rebuild with the same provider
does not recreate the image state or require another download.

Search tiles also reuse `CardPaletteSnapshot`, as the home carousel already
does. On selection it samples only the painted thumbnail and passes the color
through the presentation callback to `CardDetails.initialColor`. Details keep
that palette when metadata arrives and skip sampling the full photo. If no
thumbnail is loaded, selection immediately supplies no color and the existing
detail sampling fallback remains available. No extra image request is made
for palette extraction. Tiles are keyed by canonical ID so an asynchronous
snapshot cannot open another card after its result element is replaced.

The home discovery widgets remain mounted while search is active, preserving
carousel state. Search has no startup request, polling or disk snapshot.
Print filters use backend buckets: all, western, japanese (also Korean),
chinese. Product filters use card, booster_pack and booster_box.

## Local dictionary suggestions

As requested, the pure Dart package is located at
`lib/rebuild/packages/pokoin_suggest/`, now a path dependency of the app.
Its PKD1 decoder and core name ranking pass reference tests, along with all
171 query cases for expansion/collector parsing, set/artist ranking, intent
and API recall. Era data is generated from the pinned upstream source.

`provider/suggestion_dictionary_provider.dart` reads the bundled asset;
`service/marketplace_suggestion_service.dart` owns one long-lived worker.
Preparation and ranking run off the UI isolate, with one active query and
only the latest waiting query. Focus warms the engine; typing shows local
choices at three meaningful characters. Clearing, blur, submit and disposal
invalidate pending presentation updates. Missing/corrupt assets fall back to
the existing API result search without blocking it.

`presentation/marketplace/component/marketplace_suggestions.dart` is the
separate widget requested by the user. It receives typed state and callbacks,
shows up to six name/set/artist choices and submits a selected query with its
parsed filters preserved. It also shows up to six specific catalog versions
from the current search page, in server order, using the same query and print/
product filters as the grid. It owns no service or file access. The app root
supports an injected suggestion service alongside injected API search.

`atomics/suggestion_card_tile.dart` shows the API thumbnail, name, collector
number and expansion. Its shared `MarketplaceThumbnail` handles CDN resolution,
memory/disk caching, bounded decode size and an icon for missing/failed artwork.
The list builds visible rows with no offscreen cache. Selection opens the
existing details flow with the canonical ID and full artwork URL, preserving
the painted thumbnail palette when available. A version remains selectable
without artwork. No catalog image is bundled in the dictionary.

Versions reuse the original paginated API request after the 300 ms typing
debounce; no parallel popup API request or polling is added. Query/filter changes
clear old versions immediately, and late pages cannot reopen a dismissed popup.
An API failure leaves local choices usable; a dictionary failure leaves server
versions usable. Local choices can appear before the remote versions arrive.

This is an incremental server-backed version preview. The web's 20-row local
printing scorer/resolver, exact order/paint/filter parity and dedicated
progressive hydration remain pending, as do persisted dictionary refresh and
device performance gates. Production dictionary endpoints belong in Rust.

`Pikachu Komi` now separates a name from a known artist prefix through
`ArtistQueryResolver` in the worker. Its early answer routes to the artist API
before fuzzy suggestion ranking finishes, and selected choices carry the
resolved artist context. The service intersects the artist's complete catalog
with remaining terms and print/product filters. The current artist endpoint
downloads a catalog rather than a filtered page; its first load can be slower.
Responses beyond its 5,000-row cap are rejected as incomplete. See
`rebuild-search-phone-diagnostics-20261015.md` for the physical-phone baseline
and the separate host verification of the correction.

## Verification

`flutter analyze --no-pub lib/rebuild test/rebuild` checks the main checkout.
`dart test` and `dart analyze` run within the suggestion package.
Windows root `flutter test` currently fails in the existing win32 native build
hook because no C compiler is configured. Rebuild tests run against a copied
source tree in `Cardvault/rebuild-popup-images-check-20261015/`, with the feature's
minimal dependencies and assets, avoiding that unrelated native hook.
All 367 package tests and 113 Rebuild harness tests pass, including the
actual asset/worker/widget path, shared debounce, stale pages, independent local/
remote fallback, version selection, loaded/missing artwork, palette handoff and
keyboard layout at enlarged text. The actual prototype was also rendered and
visually checked using a public search-page response and its six real thumbnails.
