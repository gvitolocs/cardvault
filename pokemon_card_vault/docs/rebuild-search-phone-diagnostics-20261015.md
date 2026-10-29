# Rebuild search phone diagnostics — 2026-10-15

## Measured build and method

The user performed two manual typing sequences on RMX3760, Android 13, over
wireless ADB. The installed profile APK SHA-256 was verified on the phone as
`9fa827c1b1e6904520bc5d4b5e863b9135ca5b8de3998d4530d72d2a5d361f6e`.
This is the version **before** the artist/cache correction below. The user
reopened the app to expose its VM service; the measurement did not reinstall
anything or clear app data, image caches or keyboard state.

First: type Pikachu, wait, append Komi, wait, clear and type Charizard. Repeat:
clear, type Pikachu and wait, then clear and type Charizard. The user confirmed
completion of each sequence and reported the expected missing artist results.
They also reported faster perceived search when selecting SwiftKey word
suggestions. No controlled SwiftKey-versus-character latency comparison was
performed, so this remains an observation, not an attributed timing result.

Recorded Flutter frame events, public HTTP timing metadata and VM timeline
events. Widget/CPU instrumentation was not enabled. The windows contain
keyboard activity, waiting and cursor blinking: these are preliminary traces,
not precise last-key-to-visible measurements or statistical frame gates.

## Results

| Metric | First sequence | Repeat sequence |
| --- | ---: | ---: |
| Frames | 809 | 396 |
| UI build p50 / p95 / max, ms | 1.576 / 5.077 / 21.983 | 1.508 / 4.182 / 14.568 |
| Raster p50 / p95 / max, ms | 4.303 / 7.623 / 10.931 | 3.641 / 7.866 / 9.795 |
| UI frames above 16.67 ms | 1 | 0 |
| Raster frames above 16.67 ms | 0 | 0 |
| Completed search-page HTTP 200 requests | 10 | 3 |
| Search-page HTTP duration range, ms | 44.969–385.599 | 156.695–283.312 |
| Image requests | 11 | 3 |
| Image duration range, ms | 156.867–358.867 | 207.394–322.604 |

Additional request records have no completed HTTP status and are excluded from
the successful-request timing ranges. They must not be counted as successful
responses. The traces do not identify database execution time or isolate an
exact dictionary-ranking duration. Few frames exceeded the 60 Hz reference
budget, while the existing 300 ms debounce and network/image work still delay
feedback. These stages may overlap; do not add all durations as one measured
tap-to-result time. The app still refetched successful search pages on repeat.

## Artist failure and implemented correction

Public search-page GETs for `Pikachu Komi`, `Pikachu Komiya`, and explicit
`artist:tomokazu-komiya` expressions returned zero. Its existing SQL predicate
does not search artists. The public suggest route also returned zero for the
name/artist pair. The artist-cards API contains the missing intersection.

`ArtistQueryResolver` now prepares a small artist-prefix index in the existing
worker. It separates name and artist in either order, recognizes surname/full
name prefixes at three characters, protects literal catalog names and leaves
ambiguous prefixes unresolved. The worker returns an early artist answer before
fuzzy ranking; the service shares this task with suggestions rather than ranking
again before network dispatch. A selected local choice carries its resolved
artist context directly.

For recognized artists, the service uses the existing artist-cards endpoint,
prepares its response in a background isolate, intersects remaining query terms
and product/print filters, and paginates the resulting complete catalog. IDs
remain canonical. Collector numbers also accept the endpoint's
`expansion_number`. The endpoint currently has no filtered/paginated artist
contract: its first response can be larger/slower. The client caps retrieval at
5,000 rows and rejects incomplete catalogs rather than claiming a false empty
result or a fabricated total. A focused backend projection remains desirable.

A separate **Windows-host** live verification found three actual Pikachu rows
for Komiya: `813386`, `826100`, `824752`. First loading/preparation took
1,299.739 ms; Japanese and western filters reusing that catalog took 1.285 and
0.426 ms. Those are not phone timings or an improvement comparison.

## Response reuse and next comparison

`MarketplaceSearchCache` retains up to 16 successful pages and two prepared
artist catalogs for 30 seconds. Page keys include query, product type, print
language, search language, offset and limit. Repeated input with a fresh page
is restored synchronously without another debounce/network wait. Explicit
submit/retry refreshes the page; failures are not cached as empty data.
Freshness applies to prices and totals as well as rows.

The updated profile build includes timeline markers `search.changed`,
`search.cacheHit`, `search.accepted` and `suggest.query`; they record only
lengths/counts, not query text. The 300 ms debounce for uncached server searches
is unchanged. Compare typing and SwiftKey completion on the corrected APK
before claiming a first-query latency reduction. No corrected build was
installed during these baseline measurements.

## Corrected-build phone comparison

After explicit user authorization, installed the corrected profile APK as an
update preserving app data. Its on-device SHA-256 matched
`991f0dcb06fe65d561d689d77448cb97d6368fa3a7733b84fdab10f538c32834`.
The user repeated input, then searched Pikachu Komi and confirmed correct
artist results and a more responsive repeat search.

The 95.757-second window collected 898 frames: build p50/p95/max
1.535/5.410/17.302 ms; raster 3.510/7.613/12.827 ms. One UI frame exceeded the
16.67 ms reference and no raster frame did. This is consistent with smooth
rendering rather than evidence of a large frame-time speedup.

Retained timeline events include six fresh-cache hits. A 12-character artist
lookup accepted three rows 717.897 ms after the last change; a repeated
12-character lookup restored those three rows in 0.020 ms without a network
wait. These are controller-state timestamps, **not** visible-image latency.
The artist API completed in 294.916 ms; its three image transfers took
262.380–392.662 ms and may overlap other work. The VM timeline ring buffer
retained events starting 45.373 seconds into the window, so these markers do
not cover every early input or establish a full ranking-latency distribution.

During final review, also fixed a canceled artist download being reused by the
next query: canceling now clears the pending coordination entry, with identity
guards protecting its replacement. The additional regression test passes.
The final profile artifact containing that fix has SHA-256
`7c2e427ae986245f075a3d896d7af5819844d22b96104bbe352d5d3eb6b9ee4f`,
100,823,294 bytes; its performance was not separately remeasured. The measured
build above remains saved by the APK script for trace reproducibility. The
final APK was installed as an update and its on-device checksum was verified;
app data was preserved.

## Validation and artifacts

367 package tests and 113 Rebuild tests pass, including full bundled-worker
artist routing, independent filters, pagination, incomplete-catalog failure,
fresh-cache reuse/expiry and explicit refresh. Rebuild tests use the copied
source harness `Cardvault/tests/marketplace/rebuild-popup-images-check-20261015` because the root
Windows native hook still requires an unavailable C compiler. Static analysis
is clean.

Local raw artifacts: `build/diagnostics/search-phone-20261015/typing-first.json`,
`typing-repeat.json`, `artist-live.json` and `session.json`. Request bodies and
auth/cookie headers are excluded from the sanitized HTTP records. The recorder
restored HTTP logging and timeline flags, then Flutter detached without
reinstalling the app. No push, backend change or production deployment.

The corrected pass is under `corrected/cache-and-artist.json` with its
`cache-and-artist-summary.json`, session and cleanup records. Profiling flags
were restored and its separate ADB forward removed before the final update.
