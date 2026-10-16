# Rebuild discovery loading

## Diagnosis — 2026-10-09

Read-only requests from the Windows development machine observed:

| Request | First measurement | Second measurement | Response size |
| --- | --- | --- | --- |
| `/api/marketplace-home-page?limit=48` | No response within 22 s; DNS/connect/TLS completed in about 0.35 s | 2.88 s, HTTP 200 | 113,300 bytes; 98 cards |
| `/api/marketplace-expansion-page?limit=1000` | 0.52 s, HTTP 200 | 0.19 s, HTTP 200 | 235,876 bytes; 815 expansions |
| `/api/marketplace-home` fallback | — | 1.59 s, HTTP 200 | 172,801 bytes |
| Selected Tandemaus tile through `/card-images/` | 0.61 s, HTTP 200, one redirect to CDN | — | 635,162 bytes |

These are individual live observations, not phone benchmarks or guaranteed
latencies. The home response varies substantially. Server logs would be needed
to attribute that delay to a specific backend operation.

The client started both metadata requests together but published their combined
result only after both completed. Consequently, slow home data delayed the
expansions too. Each home endpoint also had its own eight-second timeout, so
the preferred endpoint followed by the fallback could delay the whole UI for
approximately sixteen seconds.

## Current behavior

- `MarketplaceHomeService` coordinates cache restoration, shared loads and
  partial presentation state. `MarketplaceHomeProvider` owns discovery endpoints,
  HTTP fallback and parsing, returning `MarketplaceHomePayload` and typed
  expansion lists through the existing abortable `MarketplaceHttpProvider`.
  It filters card IDs before constructing previews, preserving backend ranking
  metadata for selection. `ExpansionCatalogProvider` loads bundled catalog order.
  `MarketplaceHomeSelectionService` contains the pure recent-expansion and ranked
  card selection rules; models retain data and JSON field conversion.
- `MarketplaceHomeService.load(onProgress: ...)` publishes immutable partial
  results as each section becomes ready; concurrent callers share requests and
  can subscribe to progress. Successful combined responses retain the existing
  five-minute memory cache.
- `cache/marketplace_home_cache.dart` also stores at most twelve entries per
  rail in a versioned JSON snapshot with separate seven-day expiry dates. A
  new service instance restores that snapshot before publishing network
  updates. Successful rail updates are saved independently; failed refreshes
  retain unexpired saved data without extending its age, and the UI identifies
  saved content with a retry action when refresh fails.
  Cache restoration has a 280 ms bound and happens before HTTP so a complete
  snapshot under five minutes old avoids metadata GETs across restarts.
  Serialized background writes do not delay request completion or retry.
- `MarketplaceController` forwards partial results with independent loading
  flags. `MarketplaceDiscovery` renders the ready section while the other loads
  and retains available data during a refresh. Final expansion ordering still
  uses home new-arrival hints when available, dates and bundled catalog order.
- Preferred home and fallback share one total eight-second HTTP wait budget.
  An exhausted budget does not start another fallback request.
  HTTP 401, 403, 429 and 5xx also stop fallback on the same server.
  `provider/marketplace_http_provider.dart` uses an abortable request: the
  deadline covers headers and the response body and triggers cancellation.
  Disposing the service also aborts active discovery requests. The previous
  `Future.timeout` alone did not cancel the underlying network work. Cancelling
  the client request does not guarantee cancellation of a database query already
  running on the server.
- `/card-images/<file>` resolves directly to
  `https://cdn.pokoin.com/<file>`, matching `vercel.json` and avoiding the web
  redirect. Thumbnail and detail artwork use the same resolver; other image
  origins and paths retain their previous resolution behavior.
- `cache/marketplace_image_cache.dart` uses one disk manager for lazy image
  requests. Its files reside in the app support directory under
  `rebuild-cache/images/`, survive normal restarts, and are bounded to 80
  cache objects with a 30-day unused-file retention period. Metadata resides
  under `rebuild-cache/metadata/`; filesystem access is delegated to `provider/`.
  Image downloads are limited to two at a time; rails have no offscreen
  precache margin.

## Startup diagnostics and restored automatic loading — 2026-10-09

The user reports that opening the app repeatedly precedes a period when Pokoin
also stops loading in a browser. Later screenshots show skeleton content and
"The network request failed", rather than a specific access-denied status.
During this investigation the site and `/healthz` returned HTTP 200, while one
request per discovery endpoint received no bytes before an eight-second timeout.
These observations do not establish whether there is IP blocking, backend
saturation, a tunnel issue or another network failure; server/edge logs are
needed to distinguish them. Earlier HTTP 530/1033 responses were a different
observed failure condition and must not be assumed to explain every later wait.

The Rebuild `main()` again uses the constructor's automatic discovery loading,
as requested by the user. Saved rails are restored before network refresh;
a complete snapshot under five minutes old avoids metadata GETs. The first
launch without saved data still needs network access. Riprova explicitly
refreshes, while image loading remains lazy with two simultaneous downloads.

During a connected-phone test, the user reported loaded cards and expansions.
The profiler recorded six CDN image GETs during scrolling, all HTTP 200, with
no API requests in that recorded interval; both API health checks returned 200
in approximately 0.24 seconds. Initial startup requests were not recorded
because HTTP profiling was initially disabled. This did not reproduce the
failure and does not establish the cause of the earlier tunnel incident.

The temporary manual startup mode remains available by explicitly passing
`autoLoadDiscovery: false` for diagnostics, but is no longer used by `main()`.

## Request counts

| Path | Discovery metadata requests | Carousel images |
| --- | --- | --- |
| Explicit diagnostic manual mode before pressing load | 0 | 0 |
| Automatic startup with a complete saved snapshot under five minutes old | 0 | Cache lookup; network only if image absent/stale |
| Cold/stale automatic startup | 2; at most one compatibility fallback for other failures such as malformed data/404 | Built viewport tiles; at most 2 simultaneous downloads |
| 401/403/429/5xx metadata failure | 2; no same-host home fallback | No images for a failed empty rail |
| Concurrent load/retry during pending discovery | Shares those requests | Shares the image manager |

The previous automatic entry started two metadata GETs per cold app start, with
one possible home fallback. It did not contain a polling timer or automatic
retry loop. Its image manager allowed ten simultaneous downloads, but that is
an upper bound, not a measured count; no carousel image requests start when
metadata fails before any card is displayed. Fresh disk snapshots previously
still triggered metadata refresh on every new service instance.

The returned JPEG is still full-size when the API has no matching
`_homepage.webp` thumbnail. Flutter's `cacheWidth` reduces decoding resolution,
not download size. Reducing those bytes would require appropriately sized
images from the catalog/CDN. Server-side latency and image payload sizes remain
separate from the client corrections above.

## Verification

The 2026-10-12 responsibility refactor passed analysis of the changed Dart files
and 48 targeted tests in the isolated Flutter harness, covering selection,
provider parsing, catalog assets, cache, partial loading, controller behavior
and HTTP cancellation. The selection method bodies match the pre-refactor
baseline. The public service constructor remains compatible; an injected HTTP
client stays owned by its caller, while provider disposal aborts active requests.

On 2026-10-12 the user selected a 280 ms restoration budget for the principal
Rebuild after comparing the previous 250 ms budget with an isolated 500 ms test.
That profile ARM64 test on a realme RMX3760 had three cache reads
of 252, 260 and 254 ms: all three restarts reused metadata with zero API GETs.
Card-data frames appeared in 0.29–0.31 seconds and the first card image in
0.65–0.71 seconds, measured from Dart entry. The previous 250 ms budget had
discarded a valid cache read of 284 ms. This is a small phone sample, not a
guarantee for every device; no fixed half-second wait is introduced.
The principal service now uses the requested 280 ms budget, while the pre-cache,
250 ms and 500 ms comparisons remain on `codex/test-marketplace-before-cache`
and its history.
The historical 284 ms cache read can still exceed the new budget.
Regression checks cover a fresh cache restoring at 260 ms without metadata
GETs and fallback to network when restoration exceeds 280 ms.

Rebuild tests cover each section finishing first, a pending peer section remaining
in its loading state, late subscribers sharing progress, timeout without a second
fallback budget, final ranking, retries, navigation and CDN URL preservation.
Persistence tests reopen metadata and image cache instances on the same test
directory, test independent expiry, and confirm cached content survives an
offline startup and is replaced after a successful refresh.
The existing mobile layout, cart and card-palette tests also run in the isolated
Flutter/http harness; the full Windows project still requires its missing native
C++ toolchain for tests. The app is built through the standard profile ARM64
Rebuild APK script.
