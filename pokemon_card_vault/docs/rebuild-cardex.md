# Rebuild Cardex and navigation

The bottom bar is Market, Scansiona, Portfolio, Cardex, Profilo. Wallet is now
inside Profilo, alongside account features; scanning remains an inactive
Rebuild screen. The existing cart action is preserved.

Cardex uses an animated, horizontally swiped album with six thumbnails per
leaf (3 × 2, or 2 × 3 with large text). Screens at least 700 logical pixels wide
show two leaves at once. Arrow controls, page numbering, empty sleeves and a
perspective page-turn transition are included; reduced-motion settings disable
the perspective and arrow animation. Only visible/neighboring pages build images.
The default signed-in view is **Le mie carte**, across all owned expansions,
so personal cards are visible without guessing which catalog expansion/page to open.
An expansion selector switches to the complete catalog with All/Owned/Missing
filters. Owned cards are in color,
missing cards grayscale. Tapping either opens the existing real CardDetails.
Guests can browse the public catalog without inferred ownership. Loading,
signed-out and unavailable collection states never imply that every card is
missing. Ownership filters are enabled only after a successful collection read.
Counts and filtering are explicitly scoped to loaded pages; the next-page
button remains available even if the current filtered page is empty.

## Data flow

- `provider/cardex_provider.dart`: typed, validated GETs to
  `https://api.pokoin.com/api/marketplace-expansion-page`, list limit 2000;
  album requests use `slug`, `productType=card`, `offset`, `limit=48`.
  Includes catalog cards without prices/offers. Does not use homepage subsets.
- `provider/collection_provider.dart`: shared account-gate user-ID stream in
  Rebuild (with a lazy Firebase fallback for standalone consumers). Reads
  `GET https://api.pokoin.com/api/marketplace-collection` with the current
  Firebase ID token in the Authorization bearer header, without a client-supplied
  UID. Validates the returned owner and each item's owner before parsing.
  This replaces direct Firestore reads, denied by the existing client rules.
  Do not use `marketplace-portfolio`: that public BFF returns catalog/market
  quantities, not the authenticated user's holdings.
  No private collection or token is cached here. Reads happen on first entry/session
  change and the explicit **Aggiorna collezione** action in Cardex or Portfolio;
  this is not a realtime Firestore subscription.
- `service/cardex_service.dart`: catalog coordination and canonical-ID dedupe.
- `service/collection_service.dart`: switches the active collection stream on
  auth changes, clears the previous user's ownership and cancels subscriptions.
- `controller/cardex_controller.dart`: lifecycle, selection, pagination/retry,
  obsolete response protection, collection state and filters.
- `model/cardex.dart`: typed album pages, collection states and owned variants.
  Only positive quantities count; duplicate variants add copies, not unique
  cards. Canonical Pokoin IDs are compared without ID conversion or name-based
  fallback that could conflate different prints.
- `presentation/cardex/` and `presentation/portfolio/`: controller-bound screens;
  album components and atomics receive data/callbacks. Palette is in `style/`.
  `component/card_album.dart` handles presentation-only paging and transforms;
  the existing `album_grid.dart` remains the Portfolio's scrolling grid.

The legacy collection service/screen are references, not runtime dependencies.
Portfolio shows existing collection records and quantities. This change does
not introduce collection writes or valuation. Rebuild login and guest mode are
now connected to the shared Firebase account; see `docs/rebuild-account.md`.

Verification: `test/rebuild/cardex_test.dart` covers DAO contract/errors, zero
quantities and exact print IDs, account changes/errors/sign-out, obsolete
expansion responses, pagination retry/dedupe, guest/owned mobile presentation,
filters, card selection and five-tab/Profile-Wallet navigation.
`test/rebuild/card_album_test.dart` covers the private API bearer/owner contract,
errors versus empty collections, numeric quantities, mobile/tablet page turning,
canonical card taps, partial final pages, large text, reduced motion and shrinking
collections. Live authenticated account verification remains a phone check;
the production endpoint's anonymous 401 was verified without credentials.

## Initial Cardex validation on 2026-10-15

- All 120 `test/rebuild` tests passed in the isolated
  `rebuild-cardex-check-20261015` project with identical Rebuild/test sources and
  cached dependencies (image/cache packages pinned to 3.4.0 there only).
- The full checkout's host tests stop before execution because `win32 6.0.1`
  needs a Windows native C++ compiler. No source dependency overrides were added.
- A live public GET for `slug=base-set&productType=card&offset=0&limit=2`
  succeeded: total 102, two cards, `hasMore=true`, canonical IDs 222498/222496.
- The normal APK script successfully rebuilt, checked ARM64 ABI and backed up
  the preceding APK before replacing `pokoin-profile-phone-arm64-Rebuild.apk`.
  That initial APK SHA256 was `19021BE3D5FF6FBEAE271C636019AA37F80FAE9340525B9C89EE742D924C9C6E`;
  the subsequent account integration rebuilds the same destination.
- Authenticated production collection reads were covered with controlled
  session/record streams; no user's account was signed in during verification.

## Animated album and private collection fix on 2026-10-15

- All 150 Rebuild tests passed in the isolated harness, with SHA256 equality
  verified for all 159 Rebuild source/test files against this checkout.
  Dart analysis of this checkout's Rebuild source/tests reported no issues.
- Tests include the actual HTTP-backed collection service switching accounts
  before the old request finishes: the new request starts immediately and late
  private results from the previous account are ignored.
- A mobile widget render was visually inspected; wide/phone paging, 200% text,
  reduced motion, page controls, canonical card taps and partial leaves pass.
- The production collection endpoint responds 401 without credentials. No
  production personal account was used by the agent; verify the updated APK
  on the signed-in phone via Cardex → Le mie carte → Aggiorna collezione.
