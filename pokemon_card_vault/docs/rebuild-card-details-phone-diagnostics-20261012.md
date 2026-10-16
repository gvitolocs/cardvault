# Rebuild CardDetails phone diagnostics - 2026-10-12

## Scope and Method

Measured the currently installed Rebuild app on RMX3760, Android 13, over
wireless ADB. Its AOT `libapp.so` SHA-256 matches the latest local profile APK:
`a948a0ced4493b80d8d0dc5a07cc25b42ffb24e916fa73bbd56f24dc789e388e`.
Dart VM version: 3.13.4. No app/backend code was changed or deployed.

The user had already searched. Opened the visible Punk Helmet Ultra Rare
121/094, canonical card ID `713814`, returned to search, then opened it again.
No app data or disk cache was cleared: "first" means first recorded opening,
not a fresh installation. One earlier recording without the correct UI in
focus is excluded (`search-invalid.json`).

Collected Flutter frame timing events and public HTTP profiling records.
Baseline widget/paint/layout profiling extensions were disabled, with time
dilation 1.0. A third, separate pass enabled CPU/widget profiling for
attribution only. Its timing numbers are not a fair baseline comparison.
This is a preliminary single-device trace, not a statistical benchmark or
an exact tap-to-visible stopwatch measurement.

## Phone Results

| Metric | First Opening | Second Opening |
| --- | ---: | ---: |
| HTTP requests | 2 | 0 |
| Card metadata HTTP duration | 512.2 ms | No request |
| Full JPG HTTP duration | 454.6 ms | No request |
| Frames collected | 29 | 27 |
| UI build p50 / p95 / max | 4.4 / 30.0 / 42.2 ms | 3.7 / 16.5 / 35.8 ms |
| Raster p50 / p95 / max | 4.0 / 25.7 / 31.3 ms | 7.5 / 17.3 / 21.7 ms |
| UI build frames above 16.67 ms | 2 | 1 |
| Raster frames above 16.67 ms | 4 | 2 |

The API and image requests overlap: image fetching started 50.1 ms after the
API request, and finished 7.6 ms before it. Do not add their durations.
The first recording contains one full-image GET, not repeated downloads.
The second opening reuses both card data and the decoded/cached image.

API connection establishment took 302.1 ms; response headers arrived at
506.1 ms and the response finished at 512.2 ms. The JPG connection took
206.3 ms; headers arrived at 389.4 ms and download finished at 454.6 ms.
These include DNS/TCP/TLS and network/edge effects; connection establishment
is not a measurement of database execution.

## Server and CDN

The phone API response was HTTP 200 with `cf-cache-status: MISS`.
Its Server-Timing reports SQL 23.4 ms across four operations, build 8.2 ms,
serialization 0.2 ms, origin total 31.8 ms and edge MISS 32.8 ms. This points
to more time outside origin processing than inside it in this sample.

The full JPG was HTTP 200, 130,543 bytes, CDN MISS, and immutable for one year.
A separate Windows-host GET of the API returns 39,171 uncompressed JSON bytes,
including versions, rarities, SEO/artist data and 12 related cards. Rebuild's
CardService consumes only `card`; the whole JSON body is decoded nonetheless.

Three host requests using keep-alive measured API totals 289.9, 46.6 and
50.0 ms; image totals 188.8, 54.9 and 54.4 ms. These are host measurements,
not phone results. Subsequent responses were cached; their Server-Timing
header repeats cached origin values and must not be read as new SQL work.

## CPU Attribution

The instrumented pass collected 262 CPU samples. Work is distributed across
rendering, painting, layout and semantics rather than one expensive app
algorithm. The trace includes CardListingComposer, CardBestDeal and
CardPriceHistory during opening, although they are below the first viewport.
Instrumented layout peaked at 45.6 ms; composer build spans peaked at 6.7 ms.
These spans are nested and profiling adds overhead: do not sum them or treat
them as a promised saving.

That pass occurred 316 seconds after the first metadata request, beyond the
existing five-minute CardService cache TTL. It correctly made one metadata
GET (424.8 ms) and no image GET. This is cache expiry, not duplicate hydration.

## Next Experiments

1. Share an app-owned public HTTP client across search/home/card providers.
   Currently focused services create separate clients; test whether connection
   reuse removes the observed connection delay on the first detail opening.
2. Make below-viewport detail sections lazy, starting with the listing composer
   and supporting panels. Preserve accessibility; optimize the tree rather
   than disabling semantics. Compare the same opening trace afterward.
3. Reuse the already decoded thumbnail as a temporary frame until the full
   image is ready. This improves perceived readiness, not server duration.
4. Consider a Rust mobile metadata projection containing only fields used by
   CardDetails. Keep the existing web BFF response compatible. Origin SQL
   optimization is lower priority given the observed 31.8 ms processing time.

## Artifacts

Raw local data and screenshots:
`build/diagnostics/card-details-phone-20261012/`.
`summary.json` contains the three phone windows and attribution summaries;
`backend.json` contains the separate host GETs. Request bodies and auth/cookie
headers are not included in the sanitized HTTP records.

## Cleanup

After reconnecting wireless ADB, verified that the original app process was
still running. Restored HTTP timeline logging and widget build profiling to
false, the CPU profiler flag to false, and timeline streams to Dart, Embedder,
GC and Microtask. `cleanup.json` records the verified values. Stopped the
recording/attach sessions and removed their local ADB forward; Pokoin remains
open and was not restarted or reinstalled.
