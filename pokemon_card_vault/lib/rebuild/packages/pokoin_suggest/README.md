# pokoin_suggest

Pure Dart package for the Rebuild local typeahead. It lives inside
`lib/rebuild/packages/`, following the user's requested structure.

## Dictionary source and generator

- Repository: https://github.com/gvitolocs/pokoin (the `pokoin-web` checkout in the handoff).
- Pinned revision: `d6c3ce2cb633d73c2474394ae3f12db50529014a`.
- Generator: `docs/handoff/flutter-suggest-dictionary/measure-dictionary.mjs`.
- Reference encoder/decoder: `docs/handoff/flutter-suggest-dictionary/pkd1.mjs`.
- Search engine and data: `market/src/` and `market/src/data/suggest-*.js`.
- Golden exporter: `docs/handoff/flutter-suggest-dictionary/export-golden.mjs`.

The upstream checkout is read-only. The local build wrapper verifies its
revision and clean search inputs, then generates the asset, reference rows,
fixtures and provenance together. Run from `pokemon_card_vault/`:

```powershell
node scripts/generate-suggest-dictionary.mjs <path-to-pinned-pokoin-checkout>
```

Generation uses Node only as a local build tool. No production endpoint is
introduced. Regeneration must use the Node/ICU/Unicode versions recorded in
`assets/suggest/manifest.json` to reproduce collation and normalization.

## Implemented and verified

- Bundled `assets/suggest/dictionary.pkd1`: 345,880 bytes, with 10,009 names,
  838 sets and 444 artists; included in the app asset declaration.
- Catalog version: `45fad7bea59ac13721bf002c6b3d378f`.
- PKD1 v1 structural decoder with the reference section count/order,
  column lengths, aligned bounds, overlap checks, valid UTF-8, compact
  exception indexes, nationality indexes and expected header version.
- Typed columns, lazy display/slug access, UTF-16 compact pools and stable
  sorted name indexes. Collator-equivalent displays may share a rank,
  as required by the real reference encoder.
- Full-row parity tests against independent upstream source values and
  reference collation ranks for all 11,291 rows, plus malformed-file tests.
  Their reference data is stored compressed in `test/reference/catalog.json.gz`.
  It is a test oracle, not a second runtime dictionary; tests read the single
  app asset directly. Only `assets/suggest/dictionary.pkd1` is bundled.
- Golden fixtures regenerated from the same pinned source: 171 queries,
  620 compact cases, 18 distance cases and 90 popup cases.
- Core name ranker: Unicode compaction, keyboard-weighted prefix edit distance,
  transpositions, cutoff/exhaustive fallback, typed mechanics, XY Mega aliases,
  popularity/suffix scoring, shipped collation ranks and 32-entry query memo.
  Every query's compact, distance cap, mechanics and top five names/scores
  match the web fixtures; full 48-result rankings match the exhaustive path.
- Ranking scans the dictionary's UTF-16 pool directly. Row mechanics and
  popularity are prepared once in typed arrays; score/distance buffers and
  DP rows are reused. Only selected rows become result objects.
- `unorm_dart` is pinned to 0.3.3. Its Unicode tables differ from the source
  Node runtime, so all 620 normalization fixtures remain a parity gate.
  Free-text scoring and printing paint parity are still pending.
- Generated era/alias data from the same pinned source, artist surname aliases,
  set/artist ranking, expansion-prefix and fuzzy multi-word parsing, protected
  mechanics, collector/art/rarity tokens, catalog intent and API recall/query
  conversion. All 171 query cases match these additional fixture fields.
- A long-lived `SuggestionWorker` loads/prepares the engine off the UI isolate,
  processes local catalog suggestions and coalesces waiting work to the latest
  query. It sends only selected display/query/kind values to Flutter.

The header hash identifies canonical tuple JSON. Per the supplied spec,
the device checks it against the expected catalog version; it does not
re-serialize the catalog to recalculate SHA-256. Structural validation and
version equality do not constitute a cryptographic checksum of every byte.
The build manifest also records the full file SHA-256 for artifact provenance.

Run from this package:

```powershell
dart test
dart analyze
```

`benchmark/rank_bench.dart` measures dictionary decode, ranker setup and query
latency. Compile it with `dart compile exe` and run from this package root.
Desktop AOT numbers do not replace the physical-device performance gates.
The current Windows run is recorded in `benchmark/results/windows-aot.json`:
855 samples, p50 5.829 ms, p95 40.417 ms, p99 60.155 ms. Decode took 8.153 ms
and ranker preparation 53.570 ms. These are core-only numbers, not UI latency;
long-query fallback and preparation still need off-UI execution/measurement
before production rollout. Rebuild now runs preparation and all queries in
the background worker. No mobile frame-budget pass is claimed.

`.dart_tool/` contains generated development caches, not catalog data. Test
snapshots and incremental kernels can be removed and will be recreated by
the next test run. Keep the reference data and golden fixtures: they check
decoder behavior now and will check the ranker in the next stage.

## Agreed integration and next stages

- Package: decoding, normalization, matching and ranking only.
- `rebuild/provider/`: asset/file access and API downloads.
- `rebuild/cache/`: version policy, validation before replacement and fallback.
- `rebuild/service/`: loading coordination, local search and printing hydration.
- `rebuild/controller/`: query state, cancellation and result notifications.
- A separate `MarketplaceSuggestions` widget at
  `rebuild/presentation/marketplace/component/marketplace_suggestions.dart`,
  receives result/loading state and callbacks from `MarketplaceSearch`.
  Search logic remains in the service/controller.

The normal Rebuild entry now warms the bundled dictionary on search focus.
At three meaningful compact characters the popup shows up to six local name,
set or artist choices; selection preserves parsed filters and submits the
existing paginated API search. It closes on submit, blur and clear. Late results
are ignored, and a local loading failure leaves API search available. The list
height adapts to the viewport/text scale so the action stays above the keyboard.
Injected API search services also own optional suggestion-service wiring.

The popup also shows up to six specific versions with thumbnails by reusing
the current debounced search-page response. Images and canonical IDs come from
the API; the dictionary does not store artwork. Version selection opens the
existing detail page and retains the full artwork URL and thumbnail palette.
Local/remote failures are independent, and stale responses cannot reopen a
dismissed popup. This does not add a second search request.

The web's 20-row local printing scorer is still a later stage.
`ArtistQueryResolver` adds a focused name-plus-artist prefix interpretation
(for example `Pikachu Komi` or `Komi Pikachu`) without altering the existing
golden parser/ranker contracts. A shared `SuggestionTask` exposes artist routing
before the full ranking completes; local choices retain their artist context.
The app uses the existing artist-cards API and a short-lived prepared-catalog
cache for the actual intersection. This is not the full web entity resolver.
Next: free-text scoring, resolver and exact printing order/paint parity;
progressive printing hydration and print/product tabs; persisted dictionary
copy/refresh and physical-device benchmarks. The existing result-grid API
still runs while typing, so reduced network traffic is not claimed yet.

Verified: 367 package tests and all 113 Rebuild tests in the isolated Windows harness,
including the bundled asset, shared API response, version opening and images.
Root Flutter
tests remain blocked by win32's missing Windows C compiler. Analysis is clean.

Refresh endpoints and their build job belong in the Rust backend. The first
local version can use the bundled dictionary before refresh is implemented.
