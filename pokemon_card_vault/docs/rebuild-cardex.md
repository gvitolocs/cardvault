# Rebuild Cardex and navigation

The bottom bar is Market, Scansiona, Portfolio, Cardex, Profilo. Wallet is now
inside Profilo, alongside account features; scanning remains an inactive
Rebuild screen. The existing cart action is preserved.

Cardex uses an animated, horizontally swiped album with six thumbnails per
leaf (2 × 3 on phones/leaves narrower than 420px and with large text;
3 × 2 on wider leaves). Screens at least 700 logical pixels wide
show two leaves at once. Arrow controls, page numbering, empty sleeves and a
perspective page-turn transition are included; reduced-motion settings disable
the perspective and arrow animation. Visible/neighboring pages build sleeves;
image providers inside those sleeves are created only when the outer vertical
viewport actually reveals them (also checked during horizontal page turns).
The default signed-in view is **Le mie carte**, across all owned expansions,
so personal cards are visible without guessing which catalog expansion/page to open.
The **Espansioni per era** icon, to the right of the cart in the global header,
opens an animated right drawer. Its eras start collapsed; expanding an era
reveals its nested sets. A search field filters by set name/slug or era name
(Italian display labels and original names); unknown mappings remain under
Altre espansioni, so no API set disappears. Le mie carte is also available in
the drawer for authenticated accounts. Selecting a set closes the drawer and
opens that catalog album in Cardex, with All/Owned/Missing filters reset to All.
Cardex itself no longer contains an expansion dropdown: only the current
album title and ownership filters remain. Owned cards are in color,
missing cards grayscale. Tapping either opens the existing real CardDetails.
Guests can browse the public catalog without inferred ownership. Loading,
signed-out and unavailable collection states never imply that every card is
missing. Ownership filters are enabled only after a successful collection read.
Counts and filtering are explicitly scoped to loaded pages; the next-page
button remains available even if the current filtered page is empty.

## Data flow

### Artwork flush to the Cardex frame, without dark bands (2026-10-20)

The extra inner header and fixed/minimum pocket height produced a dark strip
above the illustration. Cardex now sizes each pocket to the natural ratio of
its existing normalized artwork window, plus a 1px outline and the external
control rail. The image viewport and actual cropped illustration touch the
inside of the frame on every side: no inner header, vertical letterboxing,
stretching or extra cover-zoom. Two phone columns, six cards per leaf, 2px
outer margins, 1px leaf/row/column gaps and the same artwork source window remain.

The compact yellow quantity/language capsules touch the top outline from
outside rather than using space inside the frame. The flag retains its 48px
target; ready-only totals/menu and positive-evidence safeguards are unchanged.
Large-text Cardex captions use one metadata line plus status, with the complete
card/set information still in accessibility semantics. The neutral loading
sleeves use the same natural illustration ratio. Portfolio's half-inner header,
full scans, external metadata and grid geometry are unchanged.

No new image assets, network requests, pixel-processing jobs, decode/cache
policies or data changes are introduced. The shared portrait ratio remains
exactly .716; the derived artwork ratio replaces obsolete 1.3 pocket/minimum
height constants. All **264 Rebuild tests** pass and changed-file analysis is
clean. Geometry tests assert the actual scan window, not merely its viewport,
touches the frame at phone/tablet sizes and 2x text; existing four-corner pixel,
loading, language-menu and Portfolio tests remain green. All **227 source/test
files** match the isolated harness. The profile ARM64 APK was ABI/hash verified
(`9AE87C7ED47F1F33794FA420C18A114BC1AE4E69D0D3892B3D922744E2FF4C1F`) and
installed successfully with ADB `--no-streaming -r`, preserving login and
**14 prints / 15 copies**. The final RMX3760 screenshot confirms artwork flush
to the frame with no internal dark strip or letterbox, retaining two columns,
captions and yellow controls. Pockets stay 351 physical pixels wide and are now
about 235px tall, rather than 272px with unused inner space. Evidence:
`build/qa/cardex-flush-artwork-20261020/cardex.png`. ADB went offline after that
capture, so the optional device menu/Portfolio checks were not completed;
their regression tests pass. Three previous APKs are retained; only the oldest
generated `F5ED2B19` build was pruned. No account data/cache was cleared and no
production state was changed.

### Non-obscuring collection controls and box-free captions (2026-10-20)

The Cardex inner-header geometry in this earlier iteration is superseded above;
the Portfolio layout described here remains current.

Cardex and Portfolio now share `CardOwnershipEdgeControls`: compact final
quantity/language capsules straddle the top outline and use the same yellow
fill for confirmed ownership (dark quantity text); missing-language capsules
stay neutral/grey. A text-scaled 24px-minimum rail is split half outside the
frame and half inside its header, so painted controls do not overlap the scan,
including with 2x text scaling. The small flag retains a fully hit-testable
48x48 target inside the pocket; taps during partial reconciliation are still
swallowed and do not open the card/menu. Ready selection still disables grey
unowned languages and never invents localized image URLs.

Cardex metadata is directly over the lower artwork, with text shadows only:
no opaque footer, rectangular box or gradient. This intentionally supersedes
the separate Cardex footer introduced on 2026-10-19. Artwork still contains
the same standard normalized region; flags/quantities are no longer on top of
it. Portfolio preserves the full portrait scan and places metadata underneath,
outside the image, so neither trainer names nor printed descriptions are
covered. Its grid reserves the control rail and scaled metadata height in
addition to the portrait scan height. Detail-page default controls remain
unchanged; only AlbumCard opts into the external collection layout.

There are no new graphic assets, requests, crop jobs, cache rules or provider/
controller changes. Immediate positive-evidence frame/flag and final-only
quantity rules are preserved. All **264 Rebuild tests** passed, including six
new Cardex/Portfolio geometry/menu cases on phone, narrow 2x-text phone and
tablet; the repeat run has no missed-hit warnings. All **227 source/test
files** match the isolated harness. Its existing lean dependencies were
aligned with the app's already-added camera/url_launcher imports; production
dependencies were not edited. Direct app Dart analysis has no errors/warnings,
but reports one existing style info in `cardex_controller.dart:186` outside
this change set. The user's follow-up keeps two phone columns and reduces
outer margins from 8px to **2px**, leaf padding from 4px to **1px**, column
gaps from 2px to **1px** and the Cardex-only frame inset from 2px to **0px**;
row gaps stay 1px and Portfolio's inset stays 2px. At a 360px viewport, usable
artwork width grows from 160px to 173.5px (about 8%) without changing source
crop bounds, scan aspect or cover-zooming. Analysis of the changed UI/tests is
clean. The final profile ARM64 APK was ABI/hash verified (SHA256
`71F56BE5317B21BD22C3F27F7141646370BF0296C8F0EA65EF66B7F82A9830AD`)
and installed successfully with ADB `--no-streaming -r`. The RMX3760 retained
**14 prints / 15 copies** and its login; final screenshots of both screens
show yellow capsules integrated in the outline, box-free Cardex metadata and
unobstructed Portfolio trainer names/printed rules. Cardex pockets measured
351px wide on the 720px physical display, with 2px physical row/column gaps.
The language menu is covered by widget tests; ADB disconnected again after
the two final screenshots, before the optional device menu check. Captures
are under `build/qa/collection-overlays-20261020/`; no account data/cache was
cleared or production state deployed. Three preceding APKs remain; only older
generated `4955FC0B` and `7B2A078A` builds were pruned during the two iterations.

### Larger close-packed album with contained artwork (2026-10-19)

Historical metadata layout: superseded by the 2026-10-20 section above.

This layout supersedes the earlier pocket geometry below. Cardex uses 8px
outer horizontal margins, 4px leaf padding, 2px column gaps and **1 logical
pixel between rows**. Pockets target 1.3 width/height with a 136px minimum
(196px with enlarged text); the leaf height includes the scaled page-number
line explicitly rather than leaving a fixed excess footer. Six pockets and
the phone/tablet animated page-turn navigation remain.

`CardexArtworkWindow` now **contains** the entire existing normalized
illustration window, rather than cover-scaling it and cutting off its sides.
An inner clip prevents headers/effects appearing in unused space. Cardex's
number/set/status and quantity occupy a compact separate footer below the
image, not an overlay covering its lower edge. The corner language control
remains an overlay. The source window stays x=5–95%, y=12–46% of a standard
portrait scan: this does not detect the true boundaries of unusual/full-art
print layouts, which still need per-layout crop metadata for exact framing.

Only Cardex enables the separate footer; Portfolio retains its full scan and
overlaid metadata. URLs, image caching, viewport-driven loading, the decode
width budget/768px cap, private requests and catalog prefetch are unchanged.
There is no generated crop asset, extra image request or pixel-processing job.

All **240 Rebuild tests** pass, including pixel checks that all four corners
of the illustration survive tall/wide pockets without header/effects leakage,
separate caption bounds, 8px screen margins and measured 1px/2px pocket gaps.
Phone/tablet, large-text, ownership chrome, incremental loading and Portfolio
regression tests remain green; all **210 source/test files** match the isolated
test harness. Dart analysis is clean. The standard profile ARM64 APK was
ABI/hash verified (SHA256
`A8DA0B3DCDD4DA96BC56FAE417910BBDC3DCF0D929654A7E0909C5455AA27596`),
with only three distinct preceding APKs retained (the older generated 7A28D18D
version was pruned). ADB `--no-streaming -r` installed it successfully on the
RMX3760, preserving login and **14 prints / 15 copies**. UI bounds measured
332×272 physical-pixel phone pockets with 2px physical row gaps (1 logical px)
and 4px physical column gaps, versus the earlier 8-logical-pixel gaps.
Screenshots confirm the enlarged personal and missing-card albums, separate
metadata footer and unchanged full-card Portfolio. Page turning works;
Obsidian Flames automatically grew from 48 to **96 cards / 16 pages** on page
6, retaining page 6. No account data, image caches or production state was
cleared or modified. Local screenshots are in
`C:/Users/raffa/Documents/ChatGPT/Cardvault/cardex-roomy-check-20261019/`.

### Reusable immediate ownership chrome and compact Cardex (2026-10-19)

The user's first-load capture showed images while the collection was still
reconciling, then outlines/flags appearing later. This was a state gate, not a
slow image asset. `CardOwnershipFrame` now owns the shared constant rounded
owned/neutral decorations; `CardLanguageFlag`/`CardLanguageBadge` share the local
font glyph and fixed corner geometry. They are reusable code-native Flutter
UI assets, documented in shared/atomics/README.md, not extra raster/SVG files to
load or precache. Cardex and Portfolio reuse them through AlbumCard.

CardOwnershipService derives optional **positive evidence** from validated
current-account loading rows for the exact canonical print. This carries one
confirmed language and its supplied image, but no provisional totals or list
of absent languages. The green frame and static flag paint with the first
preview, and the same source image can remain through readiness. The flag
does not open a menu or propagate a card-opening tap until ready; complete
quantities, absence classification and the full language menu still require
both reconciled sources. Guest/unavailable data never supplies this evidence;
account/source failures still clear provisional cards. No HTTP/cache policy or
owner request sizes changed.

The circled Cardex heading, tagline, personal-album heading, loading/progress
paragraphs and explanatory text are removed. A fixed 48px compact action slot
shows a small sync indicator or refresh icon; final counts remain available
in its tooltip/accessibility label. Catalog title/counts/filters, Guest/error
notices and retry remain. Personal preview captions no longer repeat
"Sincronizzazione…" once positive evidence is available. Portfolio's header
and its full-card presentation remain unchanged.

All **238 Rebuild tests** passed and Dart analysis is clean, with **209 matching
source/test files** in the isolated harness. New tests cover both screens'
first-preview frame/flag, constant-decoration reuse and stable relative geometry,
no premature menu/totals/absence, stable supplied image, simplified Cardex
header, stale Guest/error rejection and clearing on failure. Tests of pending
sync advance bounded frames rather than waiting for the busy indicator to stop.
The standard profile ARM64 APK was ABI/hash verified (SHA256
`4D4FB7AEC4E09A6823918A32EC72DE9AD5BD6401E77FCE00FBAFC41F13591D0D`)
and installed through ADB `--no-streaming -r`. Two short first-entry recordings
on the RMX3760 (with an app-only restart before Portfolio) show images already
framed and flagged while reconciliation is still pending and no final ×N badge
is shown; the final state retains **14 prints / 15 copies**. Cardex accessibility
inspection found none of the removed heading/progress nodes, while compact
refresh still exposes the final count. No app-data/cache clearing or production
write/deployment was used. These recordings verify presentation order, not a
guaranteed latency benchmark across devices or networks.

### Wider artwork framing and automatic catalog prefetch (2026-10-19)

At this earlier stage, Cardex pockets targeted a 1.8 landscape ratio with a 104px minimum height
(120px for enlarged text), rather than a 120px minimum for every phone. The
normalized horizontal window widens from 84% to 90% of the scan; its vertical
band stays at 12–46%, so zoom decreases without revealing a new effects area.
The existing image URL, lazy provider, logical decode width and 768px cap remain;
Portfolio is unchanged. This is still approximate framing for unusual layouts.

CardAlbum reports the current spread's visible end/capacity after layout.
CardexController starts the next normal 48-card catalog page when no more than
two spreads remain among the currently visible/filtered loaded cards (phone:
page 6 of an initial 8-page/48-card album). No normal "Carica altre carte" button
is required. Appended metadata preserves the current page; image downloads
remain viewport-driven rather than precaching all newly fetched cards.

Unfiltered source progress is reported too: an empty filtered page continues
until useful cards or catalog end. Single-flight, hasMore, active-album and
generation guards remain; errors stop automatic requests and show an explicit
"Riprova carte" action. A nonterminal page that adds no canonical IDs fails
instead of silently stalling. Personal owner loading is untouched, including
the normal 1000-record request restored after the earlier regression.

All 233 Rebuild tests passed; Dart analysis is clean. Regression coverage includes
threshold/deduplication, preserved page position, empty filters, error retry,
no-progress detection and wider framing without a new vertical source band.
All **204 source/test files** matched the isolated harness. The ARM64 profile
APK was ABI/hash verified (SHA256
`CD18D9C0D007FBA8F5520D108B364F43E83E1ABF4B43BFE3D41EA3C9DE871C1B`)
and installed via ADB `--no-streaming -r` after wireless streaming disconnected.
On the RMX3760, Obsidian Flames began at 48 loaded cards; navigating to spread
6 automatically expanded the album to **96 cards / 16 pages**, retaining page
6 without a load-more tap. Actual artwork images were visible. Portfolio still
showed **14 distinct cards and 15 copies**, full-card images and the existing
login. No data/cache clearing, account write or production deployment occurred.

### Phone-verified owner loading recovery (2026-10-19)

The first-two-record optimization below is **superseded**. On the connected
RMX3760, both private endpoints returned HTTP 200, but owner listings with
`limit=2&offset=0` used a stamped preview response while
`limit=1000&offset=2` returned a normal 16-row inventory with a repeated listing
ID. The duplicate-page guard correctly rejected this mixed snapshot, so both
Cardex and Portfolio became unavailable before artwork rendering. Public shop
pagination checks did not establish private-owner pagination compatibility.

InventoryProvider.watchItems now starts with the normal configured page size
(1000 by default), exactly like fetchItems. It does not combine the special
two-record path with normal pages. Lazy image construction, artwork clipping,
source reconciliation, owner checks, duplicate detection and no-Guest-fallback
remain unchanged. Small accounts finish in one owner request; subsequent pages
still require a backend that genuinely honors offset. We do not silently dedupe
ignored offsets or claim large-admin completeness without that backend contract.
An anonymized regression reproduces incompatible preview/full-page shapes, and
the full 2731-row consistent-pagination fixture remains covered. All **227
Rebuild tests** passed; Dart analysis is clean. All 202 source/test files match
the isolated harness. The standard profile ARM64 APK was built and hash/ABI
verified (SHA256 `01D551B6CF3BEDFD371C6694B34E3BAAAB7199EF792B8B93E3E9F2848D72CE6E`).
ADB `install -r` succeeded without clearing app data; after a temporary wireless
reconnection, the existing authenticated session opened Portfolio and Cardex
with **14 distinct cards and 15 copies** and actual visible images in both.
Cardex's second leaf correctly showed Audino grouped as ×2. No logout, cache
wipe, backend write or production deployment was used.

### Artwork-only Cardex, full-card Portfolio (2026-10-19)

Cardex now frames the illustration inside landscape album pockets; Portfolio
retains complete portrait cards for the business side. Six pockets per leaf,
page turns, unknown/missing states, quantity at bottom right and language flag
at top right remain. Number/expansion still overlay the bottom without repeating
the Pokemon name. CardDetails continues to show the complete card.

- Public search (`q=ivysaur`), card-page (`cardId=522372`) and expansion-page
  (`slug=base-set`) responses were inspected. Their image/preview/homepage/tile/
  grid/hero variants are full-card rasters, not isolated illustrations; the
  downloaded Ivysaur homepage WebP visibly contains name, HP and effects.
  `artLayout: window` is a classification, not pixel crop coordinates. The
  local homepage generator resizes the full sanitized scan without extracting
  an artwork rectangle. No production backend or CDN changes were made.
- `CardexArtworkWindow` uses positioned layout and hard clipping on the
  already-requested image. Compile-time normalized bounds and pocket aspect
  ratio live in `constants/cardex_artwork_constants.dart`. No image rewriting,
  AI detection, new packages, generated crop assets or extra per-card calls.
  The image URL, disk cache and lazy viewport loading stay unchanged.
- `MarketplaceThumbnail.decodeLogicalWidth` keeps the visible pocket's prior
  decoding budget even when the full scan overflows for cropping: DPR scaling
  and the existing 768-pixel cap still apply. This avoids decoding a larger
  image solely for the crop; enlargement can soften low-resolution previews.
  It does not reduce the original download's byte size. A small layout/paint
  cost remains; no physical-phone latency benchmark is claimed.
- A fixed upper illustration window matches the supplied Ivysaur reference
  (canonical card 229528) without distortion, lower effects or card title.
  This is approximate framing, not automatic artwork segmentation: full-art,
  Trainer and unusual layouts may crop the subject differently or retain text
  printed inside the illustration. No fabricated per-card accuracy guarantee.
- Regression tests cover pixel clipping, preserved aspect ratio, full-card
  Portfolio isolation, decoding limits and visible missing-image fallback.
  Optional `CARDEX_ARTWORK_QA_IMAGE` captures an actual public scan locally;
  default tests remain network-free and do not bundle that scan in the app.
- All **226 Rebuild tests** passed in the isolated harness with **202 identical
  source/test file hashes**; Dart analysis reported no issues. The profile
  ARM64 APK was rebuilt and ABI/SHA256 verified:
  `7A28D18D5ECC05247C2F22D3D7599BB0CEC944976F78A05533E4A17E02FC8796`.
  No phone installation, production write or deployment was performed.

### Progressive personal loading without a Guest flash (2026-10-19)

The user's phone video showed public 10th Movie Commemoration Set cards under
"Caricamento della tua collezione…", followed by Le mie carte. The controller
had conflated personal-album intent with ownership readiness, falling back to
public catalog cards while private reads were pending. Personal intent now
remains personal through loading and errors; Guest keeps its public preview,
and explicitly choosing an expansion still opens the public catalog.

- The original implementation requested an initial **two listing records**,
  then all remaining offset pages in batches up to 1000 in the background.
  This mixed-size request strategy is now disabled; see the recovery above.
  Two records can represent one print (e.g. language variants); no fake second
  print is invented. Immutable InventorySnapshot pages retain completeness,
  owner/pagination checks and cancellation that does not wait for old HTTP.
  fetchItems retains its full-read API for standalone callers/tests.
- CollectionService emits already-proven listed-card previews with **loading**
  status while other pages or Hold records are pending. There are no final
  quantities, language availability or missing-card inferences yet. Ready still
  requires both complete sources and explicit-link reconciliation; any read
  failure clears provisional cards, leaving unknown ownership rather than
  pretending to have a complete or empty collection. Listed prefixes stay in
  the same order when held records arrive. User changes cancel future pages and
  ignore late responses; no account-specific inventory/token cache was added.
- Cardex starts with two neutral skeleton sleeves, then shows incoming personal
  cards. The original progress prose is now removed; only final quantity/menu/
  absence controls wait for ready, while positive evidence supplies early frame
  and static flag as described above. A pending/failed personal album never says it is empty
  and never substitutes Guest/catalog cards. Portfolio also receives previews.
- ViewportArtwork defers the image builder/provider until its sleeve overlaps
  the **outer** viewport, observing vertical scroll and horizontal page turns.
  The inner non-scrolling album grid alone cannot provide this deferral because
  it lays out the full leaf, including rows below the phone's fold. Already
  revealed images remain mounted/cached when scrolled away; Portfolio retains
  its existing lazy SliverGrid construction.
- All **221 Rebuild tests** passed in the isolated harness, matching **199**
  source/test file hashes. New regressions cover first-two previews before slow
  remainder/Hold, all 2731 records, cancellation, later-page failure, Guest and
  explicit catalog selection, no provisional totals and viewport-triggered
  image construction. Dart analysis is clean after a test-only style repair.
  Two live public seller listing requests with limit=2 and offset=0/2 returned
  distinct records; this checks public pagination, not a new authenticated phone
  benchmark. No measured latency guarantee is claimed; verify on the phone.
  The standard ARM64 profile APK was rebuilt and ABI/hash verified (SHA256
  `2369490681E2F2361643FCDC2346D2B01065AD3F7DE1B87C23F26BB8C09474CF`);
  no installation or production deployment was performed.

### Quantity badges and corner language selector (2026-10-19)

Cardex and Portfolio keep **one thumbnail per canonical print**, not a tile per
language, finish or stock record. Copies remain independent in the underlying
inventory; only presentation groups their quantities. Different canonical IDs
are never combined merely because their names match.

- A compact **flag in the artwork's top-right corner** opens the language menu.
  Owned languages are selectable and show their copy count; unowned languages
  have grayscale flags, grey labels and zero quantities and are disabled.
  The **bottom-right `×N` badge is the total across all languages**, not just the
  selected one. The repeated `Posseduta · ×N` footer is removed; missing/catalog
  status and accessibility descriptions remain.
- Phone leaves use two columns and smaller sleeve/page padding for larger
  artwork, keeping six pockets, swipe animations and large-text support.
  Following the reference refinement, the card fills the rounded sleeve at its
  original aspect ratio: there is no external Pokemon name/footer. A thin
  gradient overlays number and expansion at the bottom, alongside the quantity
  badge; status remains available for missing/unknown cards and accessibility.
  Portfolio retains these full-card pockets. Cardex now uses the artwork-only
  window described above; neither presentation stretches the scan.
- Opening a card from Cardex or Portfolio shares this read-only selection with
  the detail artwork. Marketplace/demo routes retain their existing behavior.
  Selection changes neither inventory nor marketplace offer filters and makes
  no additional API calls. An image explicitly supplied by an owned-language
  record may be used; otherwise the catalog artwork stays. No translated image
  URLs are invented and a selected language does not prove a localized image.
- `constants/card_language_constants.dart` contains labels, flags and aliases;
  these are collection display choices, **not** confirmed per-print language
  availability. Unknown/unspecified owned languages are preserved.
  `model/card_ownership.dart` and `service/card_ownership_service.dart` produce
  immutable language counts; CardexController owns selection and resets it
  across unknown/account states. Shared artwork/selector/badge widgets are in
  `presentation/shared/`, with palette/font rules in `style/card_ownership_style.dart`.
- `test/rebuild/card_ownership_test.dart` covers normalization, totals, one
  thumbnail, gray disabled choices, unchanged account data, selection reset,
  corner positions, detail routing, no new API requests, and 320px/200% text.
  All **215** Rebuild tests passed in the isolated harness, matching all **196**
  source/test file hashes. Dart analysis is clean; phone/menu widget renders
  were inspected using controlled data and placeholder artwork. No new live
  account/phone smoke test was performed in this UI change set.
  `atomics/album_card_caption.dart` renders the slim image overlay; widget tests
  identify/tap canonical card pockets rather than the removed name text.

### Owner inventory alignment (2026-10-19)

Cardex and Portfolio now share **native owner listings as the primary stock
source**, supplemented by Collection holdings for Hold/unlisted/NFT ownership.
Collection alone does not represent the website's whole Listed + Held desk;
this does not establish that its backend is broken or obsolete. The signed-in
website was inspected read-only: 15 owned copies, 14 Listed and one Held back,
including Leafeon (Plasma Freeze Promos, 11/116) among Listed. The inspection
used the user's browser session, not an administrator account or extracted tokens.

- `provider/account_api_provider.dart` sends current Firebase bearer tokens only
  to the production API origin, with timeouts, UTF-8 parsing and no private cache.
- `provider/inventory_provider.dart` reads authenticated
  `GET /api/marketplace-listings?sellerUid=<current UID>&nativeOnly=1&limit=1000&offset=…`.
  No public seller-shop, CardTrader rail, active-only or price filter is used.
  It continues through all offset pages; optional total/hasMore are checked.
  Repeated IDs (including ignored offsets), inconsistent totals, malformed rows,
  owner mismatches or HTTP failures fail the whole read instead of publishing
  a truncated collection. A short page ends pagination only when no metadata
  promises additional rows. Without pagination metadata, a server silently
  imposing a smaller undocumented limit cannot be detected by the client.
- `model/inventory_listing.dart` distinguishes ownership from offer availability:
  active and paused stock with positive quantities counts even at zero price;
  inactive, sold and exhausted listings do not establish possession.
- `service/inventory_reconciliation_service.dart` preserves independent holdings,
  and replaces a holding with current listing stock only when explicit record
  provenance links the same canonical card (`holding.listingId` / source IDs).
  It never merges by card name or card ID alone. Separate IT/EN copies remain;
  ambiguous unlinked legacy records are retained, not guessed away.
- `CollectionService` waits for both reads before publishing ready. A source
  failure leaves ownership unknown. Account changes clear private state and
  ignore late results; guest mode makes no inventory reads. App composition
  passes both providers explicitly; an explicitly injected collection-only
  provider remains supported for legacy isolated consumers/tests.
- CollectionProvider continues to read `marketplace-collection`, now preserving
  record provenance and checking itemCount/cardsOwned when supplied.
- Both existing refresh actions reload both sources. No writes, prices,
  purchases, listing-status mutations or backend changes are introduced.

`test/rebuild/inventory_collection_test.dart` covers 2,731 listings over three
pages, terminal empty pages, short pages with hasMore, incomplete/overlapping
responses, owner checks, explicit-link reconciliation, separate same-print
copies, paused/sold stock, account changes, guest mode, source failure and
Leafeon in both screens with refresh of both APIs. All 204 Rebuild tests passed
in the isolated Windows harness, with SHA256 equality for all 187 Rebuild
source/test files. Dart analysis reported no issues. This is not a signed-in
phone smoke test. The profile ARM64 APK was rebuilt and ABI/hash verified at
the standard Rebuild destination (SHA256
`29132B27D97C4EA248918558C7922B925D883B54D2231E901F5731FD1EF424A6`);
no device installation or production deployment was performed.

The 2026-10-17 drawer update passed all 188 Rebuild tests in the isolated
`rebuild-cart-check-20261017` harness with matching Rebuild/test sources;
analysis of this checkout's source and tests reported no issues. The nested
mobile drawer render was visually inspected. The profile ARM64 APK was rebuilt,
ABI/hash checked and copied to the normal Rebuild destination, with the previous
APK backed up; no device installation or production deployment was performed.

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
- `service/expansion_era_service.dart`: groups the live API list using the
  already bundled shared TCG era catalog, exposed via the new public
  `packages/pokoin_suggest/lib/era_catalog.dart` entry point. Base Set maps to
  Original (Rosso, Blu e Giallo), Dark Explorers to Black & White (Bianco e Nero).
  Includes exact Japanese/Chinese aliases and explicit Shadowless/Promo suffixes;
  no date guesses, fuzzy substring classification or hard-coded replacement API
  list. Unmatched sets stay visible. The generated `tcg_eras.g.dart` is unchanged.
  The production API metadata was checked on 2026-10-17: 817 sets, no era field.
- `constants/expansion_era_constants.dart`: immutable era display titles and
  the unclassified-group ID, shared separately from service logic. The service
  retains its `other` alias and falls back to the original ID for untranslated
  eras, preserving existing labels and behavior.
- `model/expansion_era.dart`: immutable typed era groups. CardexController owns
  the grouped catalog/search state, and MarketplaceController coordinates drawer
  selection with Cardex navigation. Metadata is reused when reopening the drawer.
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
  `presentation/shared/component/expansion_drawer.dart` renders lazy nested
  rows, loading/retry, empty search, selected-state feedback and drawer actions.
  The existing discovery preview and cart workflows are preserved.

The legacy collection service/screen are references, not runtime dependencies.
Portfolio shows reconciled owner listings and held records with quantities. This change does
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
`test/rebuild/expansion_drawer_test.dart` covers era/alias mapping without
dropping unknown API sets, collapsed nesting, era/set search, loading/retry,
header position after the cart, selection and reuse without duplicate metadata
requests, no dropdown in Cardex, and 320px layouts at 100%/200% text.

## Initial Cardex validation on 2026-10-15

- All 120 `test/rebuild` tests passed in the isolated
  `tests/cardex/rebuild-cardex-check-20261015` project with identical Rebuild/test sources and
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

## Image language preference (2026-10-21)

Cardex and Portfolio now have a saved image-language menu to the left of the
cart. Italian is the initial preference; this does not filter stock or change
quantities. Visible sleeves resolve explicitly advertised translated scans
with two public metadata requests at most, retaining existing lazy image
creation and caches. CardDetails keeps its owned-language menu, with route-
local selection independent of the toolbar. See
[image-language behavior and verification](rebuild-collection-image-language.md).
