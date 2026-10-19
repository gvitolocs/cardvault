# Rebuild cart persistence

The active application starts at `lib/rebuild/main_mobile_prototype.dart`.
The previous cart implementation is now reference code under
`lib/old/providers/cart_provider.dart`; Rebuild does not import it.

## Responsibilities

- `controller/cart_controller.dart` consumes the account gate's replayed user-ID
  stream, delegates commands, exposes loading/saving/synchronization errors and
  retries, and maintains per-offer quantity and editability listenables. It also
  coordinates on-demand quick-add with CardService, ignoring late additions after
  a session change or disposal.
- `service/cart_service.dart` owns quantities, the 100-offer limit, separate real
  PKN and demo EUR totals, local hydration, pending edits and remote reconciliation.
- `provider/cart_local_provider.dart` implements local persistence through
  `HiveCartProvider`. `CartLocalProvider` is its injectable typed contract.
- `provider/cart_remote_provider.dart` implements authenticated Firestore reads
  and transactions through `FirestoreCartProvider` and `CartRemoteProvider`.
- `provider/cart_codec.dart` serializes typed snapshots to storage maps and reads
  the previous application's row format. This is serialization, not encryption.
- `presentation/shared/component/marketplace_cart_sheet.dart` presents the cart,
  thumbnails, quantity/remove/clear actions, persistence feedback and retry.

The composition root injects both DAO implementations into CartService and binds
CartController to the same AccountController used by the application gate.
Calling `CartService()` without providers still creates an in-memory service,
useful for isolated UI and existing demo tests. Injected services remain caller-owned.

## Live offers and price-side cart actions, 2026-10-17

Catalog search tiles and top sellers show the cart button immediately to the
left of the indicative catalog price. They perform no listing requests while
building or scrolling. On tap, CartController reads card metadata and fresh
available offers through CardService -> CardProvider, selects the cheapest valid
offer and adds that listing snapshot. The confirmation includes the actual
seller, condition, language and PKN price, which may differ from the catalog
estimate. Repeated taps during the same action share one request/addition.
An empty/error response never falls back to adding the catalog price; reaching
the chosen offer's stock limit does not silently select another seller.

Real CardDetails now requests metadata and listings independently on opening;
the previous explicit `includeListings: false` and demo Shop wiring apply only
to the historical implementation. Shop, the price under the artwork and
Migliore offerta observe the same live ListingsState. Language/condition filters
are shared and local, best offer is the cheapest matching row regardless of Shop
sort order, and errors expose a listings-only retry. Each offer action appears
to the left of its actual price and respects its quantity/stock constraints.
DemoCard routes retain explicit examples and never call the listing API.

CardProvider owns HTTP and typed parsing for
`GET /api/marketplace-card-page?cardId=<canonical-id>` and
`GET /api/marketplace-listings?cardId=<canonical-id>&limit=80`, using the configured
MARKETPLACE_API_BASE_URL or https://api.pokoin.com. It rejects mismatched card IDs,
inactive/zero-stock/nonpositive-price offers and duplicate listing IDs; prices
and canonical IDs pass through unchanged. CardService retains the metadata cache
and shared in-flight requests, while listing availability is fetched anew for
each later user action/opening. No polling or purchase API was added.

Public read-only checks returned 59 live offers for each of sample cards 222498
and 222496 and a successful empty result for 274416 on 2026-10-17. No cart,
listing or purchase was written to production by these checks.

## Grouped Shop and mobile filters, 2026-10-17

Shop groups matching listings by their declared origin. `MarketplaceListing.origin`
uses `source`, `sourceMetadata.provider` and recognized CardTrader listing-ID
prefixes: CardTrader offers remain in CardTrader even when their display seller
is pknreserve. Native `pokoin_user_*` offers are grouped as Pokoin, explicit
reserve sources as CardReserve, other declared origins retain a readable source
name, and missing/unknown origins use the user-requested CardReserve fallback.
The fallback label does not assert a backend origin that was not supplied.

Each source group starts expanded with four rows in the current sort order
(cheapest first by default). Its header shows displayed/matching counts and the
lowest matching price, and can collapse/reopen the section without losing its
page. “Mostra altre 4” reveals the next four rows for that source independently;
the last batch may be smaller. Listing rows remain lazy slivers inside the group.
This is local progressive display of the offers returned by the existing
`limit=80` request, not a new server-side pagination API or extra HTTP requests.

Shop's **Condizioni** and **Lingua** buttons open mobile selection sheets with
the actual available values and an option to clear the filter. Filters apply to
all fetched offers, including rows not yet displayed, and remain shared with
Migliore offerta and the artwork buy action. Filter/sort changes reset groups to
their first four matching rows and reopen them; pagination/collapse never changes
the actual best-offer calculation or cart quantities. UI components receive the
state/callbacks; CardDetailsController owns page/collapse actions and ListingsState
provides immutable group projections.

A read-only public check for Espeon ex 30th Celebration, canonical card ID 813462,
returned 49 active `cardtrader_live` offers on 2026-10-17. It therefore appears as
one CardTrader group with four initial rows. No production data was changed.

## Local storage and migration

Hive stores one versioned snapshot under the `snapshot` key, including real offer
rows and pending absolute edits/removals. A single `put` followed by `flush`
replaces the previous clear-and-reinsert sequence. Local writes run in order,
including writes already queued when the session changes.

Guests use `rebuild_cart_v1_guest`; authenticated users use
`rebuild_cart_v1_user_<SHA256(uid)>`. The digest provides stable, collision-resistant
box naming; it does not encrypt the data. Demo cards and their example EUR total
are never serialized.

When no new snapshot exists, the DAO reads `cart_items_guest` or the previous
`cart_items_<uid-with-colons-replaced>` box. Only guests may fall back to the old
global `cart_items` box. Migration preserves those original boxes. Saving an empty
new snapshot records completion, preventing removed items from being reimported.
Legacy rows with a card but no selected listing are not converted into real offers;
their original local/remote records remain intact. Imported account offer rows
become pending absolute edits, so migration never sums local and remote copies.

Local read failures block edits until retry succeeds, rather than overwriting an
unread cart with an empty snapshot. Local write failures keep current UI state and
show a retry message. No guest cart is automatically merged into a signed-in account.
Account caches remain scoped to their owner when signing out.

## Remote synchronization

Authenticated users reuse `user_carts/<uid>` with the existing `items` array and
`updatedAt` server timestamp. Firestore security rules already allow the owner
to read/write this document with at most 100 rows; no rules were changed.
The provider also checks that Firebase's current user matches the requested UID.

After local hydration, the service either reads the server snapshot or sends
durable pending edits. A transaction applies only edited listing IDs to the latest
document and preserves other rows, including legacy rows the UI cannot represent.
Each edit sets an absolute quantity or removes the row: repeated synchronization
does not increment quantities again. Concurrent edits to different offers survive;
for the same offer, the last committed absolute edit wins. This does not implement
a cross-device additive quantity merge.

Edits made during a read or write stay overlaid on the response and are sent in
the next iteration. Only the exact edit objects submitted in a successful request
are acknowledged. Pending edits and removals survive restart. Errors keep the
local cart usable; startup/session changes, opening the cart, new edits or the
retry action attempt synchronization again. There is no polling, connectivity
listener or realtime Firestore subscription.

Session changes immediately clear the previous displayed cart. Generation checks
ignore late results; a rapid return to the same account waits for its previous
commit, while another account can start independently. Already queued local writes
retain their captured owner. Old remote operations never populate the new UI.

## Purchase boundary

The cart uses the chosen offer's saved price and stock snapshot, never the
catalog's indicative price. Quantity additions respect that stock snapshot;
the UI identifies availability as requiring verification before purchase.
This change does not add checkout, shipping calculation, payment, inventory
reservation or fresh server validation of the final purchase amount.
The existing `/api/marketplace-cart` endpoint is analytics only and is not used
as a persistence API.

## Validation, 2026-10-17

All 169 Rebuild tests passed in `rebuild-cart-check-20261017`, an isolated Flutter
verification project using identical Rebuild/test source copies and cached
dependencies; SHA256 equality was verified for all 150 copied Dart files.
Flutter analysis of the actual Rebuild source/tests reported no issues.
The full checkout's known Windows native compiler dependency is
avoided without changing production dependencies. New coverage includes actual
Hive disk close/reopen and migration, Firestore DAO contracts with controlled SDK
fakes, idempotent patches, offline recovery, ordered writes, in-flight edits,
account isolation, and the shared application session. Cart widgets fit 320/390 px
at 200% text size and support retry and clear actions.

No real account credentials were entered and no production cart documents were
written during validation. Live authenticated synchronization remains a phone check.

The standard APK script rebuilt and verified the profile ARM64 artifact at
`build/app/outputs/flutter-apk/Rebuild/pokoin-profile-phone-arm64-Rebuild.apk`,
preserving the previous APK in `build/emulator-apk-backups/`.
Size: 102165850 bytes. SHA256:
`12E0A3482C5AE5459453097B3B2C841ED3935C9B0476D104A579AD685755DB7A`.

The live-offer follow-up passed all 177 Rebuild tests, including quick-add request
deduplication, actual offer price/provenance, unavailable/failed reads, stock
limits, session changes, filtered best-offer selection and mobile layouts.
The four detail-layout scenarios also passed with rendered previews; phone
best-offer and Shop previews were visually inspected. This follow-up refreshes
the same profile ARM64 APK; its final checksum is recorded in the local
Obsidian Event for this change.

The grouped-Shop follow-up passed all 182 Rebuild tests, including source
recognition, independent four-row pages, partial final batches, collapse/reopen,
filter resets and condition/language selection at 320/390 px with 200% text.
Static analysis reported no issues. The same profile ARM64 APK is refreshed for
this follow-up; its metadata is recorded in the corresponding local Obsidian Event.

During final verification, separate expansion/navigation changes appeared in the
shared checkout and were preserved. A compatibility rerun against that newer tree
passed 181 tests; one discovery test still expected the removed expansion-preview
text `120 carte nel catalogo`. The listing-group/filter tests passed in that rerun.
The earlier complete 182-test run and static analysis passed before those separate
changes, and the changed listing sources match the verification copies.

## Local APK storage policy (2026-10-17)

The current helper keeps one final profile ARM64 APK at
`build/app/outputs/flutter-apk/Rebuild/pokoin-profile-phone-arm64-Rebuild.apk`.
It moves the verified Flutter output into that path without retaining another
exported copy. The latest user policy keeps at most three distinct preceding
versions in `build/emulator-apk-backups/`; successful saves prune older versions
of this helper's hash-named history. The current IDE debug APK is preserved.
Earlier validation records describe the previous backup policy; the user's
2026-10-17 single-copy request supersedes it. Flutter/Gradle internal build
outputs are retained, and normal IDE runs can recreate their temporary APKs.
