# Cardex and Portfolio image language (2026-10-21)

## User behavior

Cardex and Portfolio expose a flag menu immediately to the left of the cart in
the shared toolbar. The initial preference is Italian; a supported selection
is saved locally using SharedPreferences and restored before localized sleeves
render. This is a device-wide **image preference**, not a marketplace search,
listing-language or inventory filter. It does not hide cards, change canonical
IDs, quantities, ownership evidence, listing filters or upload data.

CardDetails initially prefers the chosen language if owned, otherwise an owned
language. Its existing menu still enables only owned languages and greys out
unowned ones. Selecting a detail scan is now route-local: it changes neither
the global image preference nor collection per-card overrides. Detail-only
background preparation of other owned languages remains enabled.

## Loading and fallback

The public expansion response checked on 2026-10-21 did not include langScans
for the first two Obsidian Flames cards. Owner previews can likewise contain
an English catalogue scan despite Italian stock. Rather than guessing URLs or
changing printing IDs, CollectionArtworkController resolves public card
metadata through CollectionArtworkService -> the shared CardService ->
CardProvider, retaining only explicitly advertised language/path mappings.

Only mounted artwork builders acquire metadata: the existing Cardex outer-
viewport gate still defers below-fold scans, and Portfolio retains its lazy
sliver grid. At most two metadata requests run at once; identical card IDs
share work, queued sleeves are removed when their last consumer disappears,
and disposal ignores late completions. A bounded public metadata map is reused
across Cardex/Portfolio and language changes. English uses catalogue previews
directly, without a new translation metadata request. No whole-collection
image precache or new listing request is introduced.

While metadata resolves, a placeholder is shown instead of briefly showing
English as though it were the selected language. The chosen scan then uses the
existing image cache and capped decoding path. Missing mappings, metadata
failure or failed translated images retain the catalogue image with a small
explicit “Catalogo” indication. Failures are cached for this controller lifetime
to prevent repeated automatic requests; there is no automatic retry loop.
Ready translated previews are passed into details without changing their ID.

## Files

- provider/artwork_preferences_provider.dart: preference storage only.
- service/collection_artwork_service.dart: metadata/preferences coordination.
- controller/collection_artwork_controller.dart: preference race handling,
  serialized writes, visible-consumer queue and public metadata state.
- controller/cardex_controller.dart: composition and owned detail defaults.
- presentation/shared/component/collection_language_button.dart,
  collection_artwork_scope.dart and collection_card_artwork.dart: toolbar and
  localized sleeves, without direct service/storage access.
- presentation/cardex/atomics/album_card.dart: unchanged crop/full-scan layouts
  now consume the localized image builder inside existing lazy rendering.
- presentation/marketplace/marketplace_screen.dart: selector and dependency
  wiring; existing responsive title avoids overflow on narrow screens.
- model/marketplace_home.dart: explicit local imageLanguage preview hint.
- presentation/card_details/card_details.dart: route-local language selection.
- test/rebuild/collection_artwork_test.dart and card_ownership_test.dart:
  persistence/races, two-request limit, deduplication, cancelled queue, failed
  mappings, disposal, no English metadata flash, fallback, independent details
  and a compact 320px toolbar.

## Verification

All **299 Rebuild tests** pass, including eight feature tests and existing
toolbar/drawer checks at 320px with 200% text. All 235 Dart source/test hashes
match the isolated harness. The ARM64 profile APK was built and ABI/hash
verified: SHA256 `50601C79C0C4D1B2E0832798015A6259B8AD0B64DBEF8709FCFB23B5FF82C9F1`.
The user requested the APK only: no phone install, production deploy or
account/collection mutation is performed.
