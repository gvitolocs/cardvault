# Agent instructions (Pokoin / CardVault)

## Mobile app working branch (user workflow)

- `AppMobile` is the user-requested working branch for this mobile app checkout.
- It replaces `codex/search-images-mobile-filters`; keep local work tracking
  `origin/AppMobile` after the GitHub branch rename.
- Do not merge into `main`, force-push, publish releases or deploy production
  unless the user explicitly requests it.
- Keep APKs, generated caches and machine-local Android SDK configuration out
  of source commits. Continue the local APK and Obsidian workflows below.

## Previous application reference (2026-10-16)

- On `AppMobile`, the previous application folders live under `lib/old/`.
- Keep active mobile work under `lib/rebuild/`; use `lib/old/` as reference.
- `lib/old/main.dart` is the previous application's entry point. Rebuild starts
  from `lib/rebuild/main_mobile_prototype.dart`; choose the target explicitly.
- Shared `lib/firebase_options.dart` stays at the `lib/` root.
- Legacy tests and the first-character cache generator use the `old/` paths.

## Mobile Rebuild architecture (user preference)

- The user chose the Service -> Controller -> Presentation structure, refined
  on 2026-10-09 to group UI files by screen under `lib/rebuild/presentation/`.
  Follow this structure for new work and incremental refactors.
- User refinement on 2026-10-08: introduce a `provider/` data-access/DAO layer.
  Requests flow Screen/Component -> Controller -> Service -> Provider/DAO ->
  backend/local storage; typed models/results flow back through these layers,
  and controllers expose the resulting presentation state to the UI.
- `model/`: data entities and presentation-state snapshots. Models represent
  backend data; they do not perform network or storage access.
- `constants/`: shared compile-time labels, lookup tables and static metadata,
  grouped into feature-specific Dart files (for example expansion era titles).
  Keep these values out of services/controllers; constants must not depend on
  UI, services or storage. Do not turn this into a single unrelated strings file
  or move runtime configuration/secrets here.
- `provider/`: read/write API, Hive, Firestore or other storage through focused
  DAO-style classes. Convert stored/API data into typed models and expose
  asynchronous results via Future/Stream. Providers do not depend on UI,
  controllers or services. This project-specific name is distinct from
  Riverpod providers used for state management in the legacy `lib/old/providers/`.
- `service/`: data operations, domain rules and coordination of providers,
  including local/remote persistence and reconciliation when needed. Keep
  services free of `BuildContext`, navigation, dialogs and widget construction.
  Introduce this separation incrementally; the legacy CartNotifier combines
  persistence, synchronization and UI state, so extract its storage operations
  rather than reusing the whole notifier as a DAO.
- `cache/`: cache policies, versioned snapshots, expiry and shared image-cache
  configuration, as requested on 2026-10-09. File and directory access belongs
  to `provider/`; background cache writes must not delay presentation or retry.
- `controller/`: coordinate services, expose state and actions, and handle
  loading, retries, filtering and notifications without constructing UI.
  Keep focused controllers such as `CartController` for distinct responsibilities;
  `CartService` retains cart data and calculations.
- `presentation/<screen>/<screen>.dart`: compose the view, bind controller
  state/actions, and manage UI
  lifecycle, layout, input, dialogs and routing. Delegate data operations to
  controllers rather than calling services directly.
- `presentation/<screen>/component/`: intermediate presentation widgets that
  compose sections from atomics, preferably receiving data and
  callbacks. A reactive component can observe its dedicated controller, as the
  cart sheet does; components should not access services directly.
- `presentation/<screen>/atomics/`: small reusable building blocks such as
  fields, badges, panels and images. The former `widget/` folder is replaced
  by `atomics/`; complete sections belong to `component/` instead.
- `presentation/shared/`: components, atomics and presentation helpers used
  by multiple screens, including navigation, the cart sheet and thumbnails.
  Shared widgets must not depend on a screen-specific component for helpers.
- Keep page palettes and themes in the dedicated `style/` folder, as requested
  on 2026-10-08. Controllers, services, providers and models remain outside
  presentation. Wire dependencies and ownership at the app/feature entry point.

## Local Rebuild phone APK (user workflow)

- Latest user update on 2026-10-17: keep one current handoff APK at
  `build/app/outputs/flutter-apk/Rebuild/pokoin-profile-phone-arm64-Rebuild.apk`.
  Keep at most three distinct preceding versions in `build/emulator-apk-backups/`.
  Do not create extra exported copies or unlimited historical APK backups.
  This supersedes both the old unlimited history and the earlier no-history policy.
- After changes affecting the Flutter app, Android configuration, dependencies
  or bundled assets, refresh the profile ARM64 phone APK before handing off.
  Do not build additional variants by default.
- From `pokemon_card_vault/`, run `./scripts/build-emulator-apk.ps1`.
  Its defaults select `lib/rebuild/main_mobile_prototype.dart`, `android-arm64`,
  `profile`, and the single final path above. Explicit equivalent parameters
  remain supported. Other destination directories are rejected.
- The helper builds, verifies the packaged ARM64 Flutter engine and SHA256,
  then moves the generated Flutter APK into the final path. A different final
  APK is replaced only after preserving/verifying the preceding distinct version.
  After successful promotion, trim this APK's hash-named history to three
  distinct preceding versions; do not retain a duplicate of the current APK.
  Build/ABI failures preserve the existing final APK and do not prune history.
- The user explicitly authorized deleting older generated APK versions and
  retaining this small history. Only prune this helper's known hash-named APK
  history; do not bulk-delete unrelated variants or recursively delete build
  internals, source or configuration files. Keep the current Android Studio
  debug APK and Flutter/Gradle internal outputs.
- Do not edit APK Analyzer extracts or Android Studio project files.
- Request execution/write approval when the sandbox requires it. If the build,
  promotion or verification fails, report it without claiming an updated APK.
- This is a local profile artifact, not a release or production deployment.
  It does not install the APK on a device unless the user asks for installation.

## Local Obsidian updates (user workflow)

- Keep generated note staging, helper scripts and local backup copies under
  `build/obsidian/<topic>/` instead of creating separate `build/obsidian-*`
  directories. This groups working copies only; the actual vault stays below.
- Update the user's local Obsidian documentation after every project change set,
  before handing off. The existing vault is
  `C:\Users\raffa\Documents\Obsidian\Pokoin Collaborator\Pokoin`.
- Read the current hub and relevant notes, update existing claims rather than
  duplicating them, and keep the file-map MOC and dated Events linked.
- Preserve existing notes, back up overwritten files, and request write approval
  when required. Report if an update remains pending; staged notes alone do not
  count as updating the vault.
- Follow `../memory/obsidian-documentation.md` for note structure. This local
  workflow does not synchronize or replace the canonical Pi vault.

## Production deploy

- **Always** use `./deploy-pokoin-web.sh` for `pokoin.com` production.
- **Never** run bare `vercel --prod` from the repo root; it deploys API-only and
  breaks `/`, `/marketplace`, and all Flutter routes with Vercel `404 NOT_FOUND`.

## Incidents

If the site or `/marketplace` shows Vercel `404: NOT_FOUND`, follow:

`workflows/pokoin-vercel-404-recovery-workflow.md`

## Marketplace / cards

`workflows/card-market-page-workflow.md`

Our marketplace id is **our id** (`docs/marketplace-public-ids.md`):
`marketplace_cards.card_id` = old CardTrader blueprint × 2. We do not use `ct_id`
in URLs, API, Flutter, or image URLs. Never × 2 a catalog `card.id` or a Fast
Milo/TCGplayer id. pokoin-marketplace has 018 applied. Codevira D00000B.

## Multi-game CardTrader dump (One Piece / Riftbound)

Qwen: follow these two files. Do not print secrets.

- `workflows/cardtrader-multigame-marketplaces-workflow.md` (importer flags)
- `/home/nez/secrets/docs/CARDTRADER_MULTIGAME_DUMP.md` (hosts, WARP netns, 403)

Isolated DBs only (`pokoin_one_piece`, `pokoin_riftbound`). Never write into
Pokemon `public.cardtrader_pokemon_blueprints`. Frankfurt image hosts are
Cloudflare-403; use netns `igvpn` (nezopt) or `ctvpn` (peer1 WARP). Full
multithread (`--image-concurrency` 12–16, both games in parallel).

## Crypto swap / bridge

`workflows/swap_bridge-workflow.md`

`workflows/crypto-pkn-purchase-workflow.md`

## Codex in Cursor (local dev)

Use ChatGPT Plus/Pro Codex models inside Cursor via the local proxy:

`workflows/codex-cursor-proxy-workflow.md`

Quick start: `npm run codex:cursor-proxy` (Bun + `codex` auth). Auto-start at login: `npm run codex:cursor-proxy:install-launchagent`. Source: `github:wellbritto98/codex-cursor-proxy`.
