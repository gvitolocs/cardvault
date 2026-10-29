# Rebuild account, guest entry and profile

## Optional app appearance

The palette icon beside the email in Profile opens **Tema dell’app**, offering
**Default** and **Dungeon Crawler**, including for guests beside the guest
description. The separate theme card is removed; the tooltip names the current
appearance and retains any unsaved-preference message. Default preserves the existing Rebuild palette and Flutter icons;
Dungeon Crawler uses the supplied map as the main shell background and the chest
as the bottom navigation background, with warm brown/cream/gold navigation and
toolbar colours. Cardex and Portfolio pixel art appear in bottom navigation and
the Profile shortcuts; remaining icon slots fall back to Flutter. The local PNGs are bundled
from `assets/images/Dungeon Crawler Themed/`, without network requests or changes
to card images. Existing panels and pushed detail pages retain their surfaces.

The preference flows through AppAppearanceController -> AppAppearanceService ->
AppAppearanceProvider (SharedPreferences), independent of account/login and the
card-image language. Choices update immediately, restore across launches and
fall back to Default for unknown stored values. Writes are ordered; failures
retain the session appearance with an unsaved-preference message. Changing
appearance does not recreate the marketplace/account/cart services, reset the
selected tab or pushed routes, or request card metadata/images.

`style/default/default_theme.dart` retains the baseline theme;
`style/dungeon_crawler/` owns the optional theme and extensible icon manifest.
See its [README](../lib/rebuild/style/dungeon_crawler/README.md) before adding
marketplace artwork. PNGs remain in assets; the existing assets/icons bundle
already includes Cardex.png. ThemedIcon uses crisp local pixel art and a Flutter
fallback for missing slots or failed assets; existing touch targets/labels stay
on the parent controls.

Historical validation was intentionally limited, per the user's request, to the single
`test/rebuild/app_appearance_test.dart` initial-app UI test: default appearance,
guest Profile switch, controller/cart/tab continuity and preserved pushed
navigation. It passes against current source files using a small direct-import
runner in the existing `tests/scanner/rebuild-scanner-check-20261019` harness.
Direct main-project tests are blocked by the existing missing Windows C++
compiler for the win32 native hook. The other new theme tests and temporary
full-suite adapters were removed; historical suites and protected cart QA were
not changed. Following the user's 2026-10-23 preference, no tests are created,
copied or run for subsequent visual/theme changes, including the palette's
move beside the email. No phone installation or production deploy is part of this change.

## Entry and persistence

`lib/rebuild/main_mobile_prototype.dart` now starts an AccountController and
places an account gate around the application's Navigator. A fresh installation
offers **Continua con Google**, existing-account email/password login, password
reset and **Continua come ospite**. The restoring state prevents a transient signed-out screen from
replacing a valid restored user. Firebase Auth manages mobile session persistence
and token renewal; web explicitly uses `Persistence.LOCAL`. No password or extra
copy of bearer tokens is saved by this feature.

The guest choice alone is stored as the `pokoin_rebuild_guest_v1` boolean in
SharedPreferences, so testing can continue across launches. A restored Firebase
user takes precedence over that choice. Guest entry also works if Firebase
initialization fails; login can be retried later from Profile. Login clears the
guest preference. Explicit logout clears it and returns to the initial screen.

The gate gives the login its own Navigator/Overlay and unmounts the private
Navigator on logout, including any pushed Wallet, settings, orders or details
routes. Guest entry uses no Firebase anonymous account and does not create a
new anonymous account. Google uses the existing Firebase Google provider;
separate email account registration remains outside this change.

## Google login

The Google button uses AccountController -> AccountService -> AccountProvider.
Android uses the existing `google_sign_in 6.2.2` dependency to select an account,
then exchanges its ID token for a Firebase credential with
`signInWithCredential`. Web uses Firebase `signInWithPopup` with the Google
provider and `prompt=select_account`. Both use the same restored Firebase UID
as Profile, Cardex and Portfolio. Cancelling the picker/popup preserves guest
state, does not report a login failure and does not clear the guest preference.
Successful authentication clears the preference. Logout signs Firebase out and
also clears the native Google plugin session when supported.

The user-supplied Firebase Android export is now installed at
`android/app/google-services.json`. Google services Gradle plugin 4.5.0 is
declared in `android/settings.gradle` and applied in `android/app/build.gradle`,
so native Firebase resources are generated from the matching package client.
`DefaultFirebaseOptions.currentPlatform` now returns dedicated Android options
for Android, including the native app ID
`1:36941064114:android:b21dbb3efb235aa471e6ab` and its API key; it previously
returned the web app's options on Android. Web configuration is preserved and
both apps remain in the same real `pokoin` project.

Native Google is initialized with an explicit `serverClientId`, the
**public web OAuth client ID** of the matched app's `oauth_client` entry
(`client_type=3`, not an Android or appinvite client):
`36941064114-t9tcju3rjaesd8q6nkttm36ver3qaktb.apps.googleusercontent.com`.
It was verified on 2026-10-15 through the project's public Firebase
`accounts:createAuthUri` response; no OAuth client was created or changed.
It is overridable with `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` for a different
configured project. No client secret, ID/access token or account credential is
committed or logged.

The Android OAuth registration must match **both** the APK package and signing
certificate. The locally built profile APK uses:

- Package: `com.vitologic.pokoin`.
- Certificate SHA-1: `EA:EA:E1:3D:2C:42:29:A7:3E:B2:49:B8:66:0D:1B:89:DA:F4:E4:0E`.
- Certificate SHA-256: `B1:F2:84:D8:C0:57:08:18:46:C9:47:B1:79:79:65:35:E5:9F:1E:F6:6A:9E:4B:F4:96:B4:34:73:45:00:AB:25`.

The certificate was read from the APK with Android apksigner. The Firebase
export supplied by the user on 2026-10-15 contains an Android OAuth client
(`client_type=1`) with this exact package and certificate SHA-1, confirming the
export's pairing with the local APK. This is stronger evidence than the earlier
public web OAuth lookup, but a successful account login must still be verified
on the phone. If the phone reports `google-configuration`, check the
installed APK/signature and cloud configuration against these values. The message
also covers a missing ID token and native developer error 10. Browser popup
blocking and unauthorized Firebase domains have separate user-facing messages.

References: [Firebase federated sign-in](https://firebase.google.com/docs/auth/flutter/federated-auth),
[Google Sign-In Android configuration](https://pub.dev/packages/google_sign_in_android).

## Rebuild layers

- `model/account.dart`: account/session states and typed profile, balance,
  order and failure models, without Firebase or storage access.
- `provider/account_provider.dart`: shared Firebase project initialization,
  user-change stream, email/password login, reset, signout and guest preference.
- `service/account_service.dart`: validation and session/guest coordination.
- `controller/account_controller.dart`: restoring/busy/error feedback and
  authoritative session; replays the current user ID to collection consumers.
- `provider/profile_provider.dart`: existing authenticated Firestore `users`,
  `balances`, `orders` and `user_card_watchlists` reads. Only displayName and
  updatedAt are writable in this feature; balance, roles, wallet addresses,
  orders and privileges remain server-owned.
- `service/profile_service.dart`: typed profile operations and name validation.
- `controller/profile_controller.dart`: starts reads on Profile entry, cancels
  and clears the previous user's data on session changes, tracks errors by
  section and coordinates display-name edits.
- `presentation/account/` and `presentation/profile/`: widgets bind controllers
  and own navigation, input and lifecycle, without accessing Firebase directly.

MarketplaceController receives the account at the composition root. Its Cardex
uses a CollectionProvider with the same replayed user-ID stream instead of
initializing an independent session. Portfolio and Cardex can therefore update
when a guest logs in, changes account or signs out. Unknown possession remains
distinct from a successful empty collection.

## Profile and Wallet

The bottom destinations remain Market, Scansiona, Portfolio, Cardex and Profilo.
Wallet moves from the header **inside Profilo**. Profile includes the account
identity, Wallet, Portfolio, Cardex, orders, favorites, account settings and
logout. Guests can enter Profile and Wallet and open the same login form from
there; personal balances are not fabricated as guest zeros.

Wallet shows existing available/reserved PKN balances and a linked address when
available. Orders and favorites are read-only views of existing account data;
favorite IDs open the existing real CardDetails. Settings supports the allowed
display-name edit, shipping-address management and Firebase password-reset email. This is not a new transfer,
withdrawal, wallet linking or payment implementation.

## Shipping addresses and listing origin (2026-10-21)

Profile → Account settings → Indirizzi di spedizione reads the authenticated
owner's address book, allows add/edit/delete and selects a default address.
AccountAddressesProvider uses the live /api/account-addresses contract:
GET ?reveal=1 for the settings view, POST to add, PUT ?id=... to update/default,
and DELETE ?id=... to remove. Required fields match the web checkout: fullName,
addressLine1, postalCode, city, countryCode; label, addressLine2 and phoneNumber
are optional. The API stores encrypted addresses; the app retains decrypted
fields only in the active screen/controller memory, never in Hive or logs.
Logout/account changes clear the controller and reject late responses or editor
submissions from the previous account. An ambiguous mutation requires a reload
before another attempt.

Clipboard listing drafts request address metadata without reveal and default
their shipFromCountry to the default address, or the first address if none is
marked default. If no address country is available, the existing seller-country
setting is used; otherwise the user chooses a country explicitly. A manual draft
selection wins over background prefill. Only the country enters the listing,
never the full address. Explicit publication saves this country as the seller
setting before sending the listing. See rebuild-scanner.md for the API failure
handling and historical HTTP 400 investigation.

Model/provider/service/controller files are shipping_address.dart,
account_addresses_provider.dart, shipping_addresses_service.dart and
shipping_addresses_controller.dart; the screen is
presentation/profile/shipping_addresses_screen.dart. The nine focused cases in
test/rebuild/shipping_addresses_test.dart cover CRUD contracts, metadata reads,
required fields, owner changes, persisted country/manual override, fallback,
publication ordering, redacted 4xx messages and the phone editor. API writes in
tests use MockClient; no real address or listing was created during validation.
All 299 Rebuild tests passed in the isolated project after this change, and
static analysis of the modified address/listing files found no issues.

## Validation

`test/rebuild/account_test.dart` covers Firebase DAO delegation/error mapping,
guest-only preference persistence, restored sessions, input validation,
initialization failures with guest fallback and later login, password reset,
account-switch stream cancellation and balance clearing, small screens with
enlarged text, and login from an open guest Wallet followed by logout.
Existing startup/discovery/rendering tests inject a guest account service rather
than bypassing the production gate. The independent Rebuild test project uses
identical source/test copies with cached UI dependencies because the complete
checkout's Windows host tests require an unavailable C++ compiler for win32.

No real user credentials were entered and no account was created or password
reset email sent during verification. Runtime login uses the existing Firebase
configuration; console provider enablement was not changed.

Initial account checks on 2026-10-15: all **131 Rebuild tests** passed in the isolated
verification project and Flutter analyze found no issues in Rebuild/account
tests. The normal build script successfully produced the profile ARM64 APK,
verified its ABI and backed up the previous artifact. The updated
`build/app/outputs/flutter-apk/Rebuild/pokoin-profile-phone-arm64-Rebuild.apk`
was 101065256 bytes before the Google follow-up, SHA256
`8134ED593611C591A81C942ED8A9F00C3399C0018DF050ECA4023FFC7774913E`.

Google follow-up checks on 2026-10-15: **137 Rebuild tests passed** in the
isolated project, and Flutter analyze reported no issues in Rebuild and the
Google tests. Six new tests cover the native credential exchange, chooser
cancellation, missing tokens/developer error 10, network/Firebase errors, guest
transitions and a button-driven Google login with duplicate-request prevention.
The profile ARM64 APK was rebuilt successfully, preserving the prior artifact.
Current size: 101080817 bytes; SHA256:
`42086E86510969E8B35FA145860BC7AD4C6E455F4453A61D5FCB055FF32F88FA`.
The public OAuth client was verified live; the user's Google account and cloud
Android fingerprint registration were not accessed or modified.

The subsequent user-supplied JSON integration is covered by
`test/rebuild/firebase_android_config_test.dart`: native platform options must
match the export, the Google token audience must use its matched web OAuth
client rather than appinvite metadata, and Gradle must process the file for
`com.vitologic.pokoin`. These configuration tests make no account/database
requests. The original file in Downloads is retained unchanged.

Final native configuration checks on 2026-10-15: **140 Rebuild tests passed**
in the isolated verification project and Flutter analyze reported no issues.
The profile ARM64 build completed with Google services Gradle processing.
apksigner verified the final certificate and its exact match to the supplied
Android OAuth SHA-1; aapt verified the package and confirmed that native app ID,
Android API key and matching web OAuth client are actually packaged. Generated
`processProfileGoogleServices/values/values.xml` also matches the supplied JSON.
APK size: 97772069 bytes; SHA256:
`2EA85D1D4A01F0775BB66275248FFE04F5EE4B41171D414949025DF86C36734B`.
The preceding APK was backed up by the normal script. Real Google account
authentication and user-data access still require the user's phone test.
