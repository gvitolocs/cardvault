# Detail-only language artwork and outer corner controls

## Behavior (2026-10-20)

CardDetails keeps its original preview visible immediately. The normal parallel
metadata/listing requests are unchanged; metadata now retains the production
`langScans` field instead of dropping it. Once current-account ownership is
ready, CardDetailsArtwork prepares the explicitly advertised scans for owned
languages in the background, with at most two image preparations at a time.
Unowned/grey languages are not fetched or enabled. No language images are
preloaded by Cardex/Portfolio grids, demo routes or guest/unknown ownership.

Successful preparation uses the same cached provider and decode width as the
visible image (DPR-scaled, capped at 768px). Switching to a ready language uses
that cache; it does not fetch card metadata/listings again or alter quantities,
inventory, listing filters, canonical card IDs or print versions. Closing the
route prevents queued images starting; already running cache reads may finish,
but late completions do not update a disposed widget.

The image keeps a 12px outer margin. Compact, neutral detail controls use the
outer top-right/bottom-right corners, retaining a 48px language touch target.
On a normal phone the panel permits a 290px wrapper around the existing 266px
scan, preserving its size/aspect rather than simply shrinking it. Detail-only
options leave Cardex/Portfolio's yellow edge controls unchanged. The gapless
artwork widget remains keyed by canonical card ID.

## Production contract and safety

On 2026-10-20 the public detail response for card **512138**, Audino 173/197
Obsidian Flames, returned `langScans: de,es,fr,it,pt:sv/sv03/173`. The canonical
image URL stayed unchanged for both `lang=en` and `lang=it`: changing that
parameter alone is not proof of a translated scan. The advertised Italian
asset returned HTTP 200, image/webp, 54,454 bytes.

CardLanguageArtwork uses only explicitly advertised language/path pairs and
TCGdex's [documented asset format](https://tcgdex.dev/assets), selecting
`https://assets.tcgdex.net/{language}/{advertised-path}/high.webp`. It validates
language labels and exactly three safe path segments, rejects traversal/URLs/
oversized manifests and drops ambiguous duplicate-language mappings. It does
not search by name, convert marketplace IDs, select Japanese/sibling printings,
or invent a translated Pokoin CDN filename. Unsupported or absent mappings
remain absent, and `langScans` survives model serialization/cache round trips.

While a selected scan is preparing, the catalogue/supplied preview remains
visible with an explicit loading label. Failure retains the fallback with an
unavailable notice and local retry; retry evicts the failed image-cache key and
is single-flight. An unadvertised non-English selection is explicitly marked
as a catalogue fallback. EN without an advertised mapping uses the original
catalogue/supplied preview, not a guessed external URL.

## Files and verification

- `model/card.dart`, `model/card_language_artwork.dart`: retain and validate
  the explicit scan manifest without making network requests.
- `presentation/card_details/component/card_details_artwork.dart`: scoped
  warming queue, cache readiness, fallback/retry and outer controls.
- `card_details.dart`, `component/card_artwork_panel.dart`: detail composition
  and unchanged foreground image/palette lifecycle.
- Shared language/quantity atomics: optional neutral detail styling; existing
  compact collection defaults are preserved.
- `test/rebuild/card_details_language_artwork_test.dart`: mapping/round-trip,
  outside corners at normal/2x text, two-way background warming, owned-only
  requests, visible fallback, prepared switching, retry and disposal.

All **269 Rebuild tests** pass; changed-file analysis is clean and **230
source/test files** match the isolated harness. Existing first-image/palette,
ownership, cart, Cardex, Portfolio and scanner regressions remain green.
The profile ARM64 APK is ABI/hash verified (SHA256
`C245353258A4E3560656842B7191D2655ECD611C0EF0474C3A73FB1931E579D2`).
Three previous APKs remain; only older generated `5E085A2A` was pruned.
The APK was installed in place over ADB without clearing app data. On the
connected RMX3760, Audino switched Italian -> English -> Italian: screenshots
show `Trovamico`/`Sberla`, then `Find a Friend`/`Slap`, then Italian again,
not merely a changed flag. Quantity stayed x2 and both owned languages stayed
selectable. The outer controls do not cover the scan's rules text. Evidence:
`build/qa/detail-language-artwork-20261020/{italian,english,italian-return}.png`.
The menu scrolls to the selected language; swipe down within it to reveal an
earlier language if it is above the visible viewport. No production
backend/deploy changes or collection mutations were made.
