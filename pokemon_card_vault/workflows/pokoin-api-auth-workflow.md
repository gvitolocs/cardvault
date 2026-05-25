# Pokoin API Auth Workflow

Pokoin API authentication wraps Firebase Authentication. The Pokoin bearer token is the signed Firebase ID token for the current user, exposed through the client-side Pokoin API auth service so app code does not call `getIdToken()` ad hoc.

## Client Flow

1. Firebase initializes in `lib/main.dart`.
2. Local browser services such as Hive finish initializing before `runApp()` so
   cached cart/account state can hydrate during the first frame instead of
   racing app startup.
3. `authBootstrapProvider` calls `AuthService.initializeSession()`.
   `initializeSession()` is guarded by a single in-flight Future; do not add
   widget-level bootstrap calls that can start parallel account/session loads.
4. `AuthService` sets Firebase web persistence to `LOCAL`, then initializes
   `PokoinApiAuthService`.
5. `PokoinApiAuthService` listens to Firebase `idTokenChanges()`.
6. On sign-in or token refresh, it caches the current ID token as the Pokoin
   bearer token.
7. On logout or inactivity logout, it clears the cached bearer token and
   Firebase signs out.
8. Profile, balance, order, and linked-wallet providers should watch
   `authStateProvider` directly. Do not invalidate those providers from an
   `authStateProvider` listener during normal refresh; that creates duplicate
   Firestore subscriptions for the same user.

## Refresh Boot Order

On browser refresh the expected account path is:

1. Firebase restores the persisted user.
2. `authBootstrapProvider` performs one guarded session initialization.
3. Session inactivity is checked.
4. `lastSeenAt` is touched only when the local session touch marker is stale.
   Do not update `users.updatedAt` on every refresh: top-bar/profile avatars
   depend on the persisted `photoUrl`, and rewriting the profile document can
   force repeated profile/avatar refreshes.
5. `userProfileProvider` and `pknBalanceProvider` emit any local cached value,
   then continue with their Firestore snapshot stream.
6. `cartProvider` hydrates the user-scoped Hive cart box immediately, then
   reconciles with `user_carts/{uid}` in the background.

Use `PokoinApiClient` for authenticated API calls:

```dart
final client = PokoinApiClient(auth: ref.read(pokoinApiAuthServiceProvider));
final response = await client.postJson(
  Uri.base.resolve('/api/example'),
  body: {'example': true},
);
```

For optional auth, pass `requireAuth: false`. For required auth, the default behavior throws before sending if there is no signed-in Firebase user.

## Server Flow

Vercel functions validate the bearer token with Firebase Admin:

```js
const { verifyBearerToken } = require('./_firebase');

const decoded = await verifyBearerToken(req);
```

`verifyBearerToken(req)` expects:

```text
Authorization: Bearer <pokoin-bearer-token>
```

The decoded token UID is the user identity for writes, seller-owned reads, wallet/profile actions, forum posting, and admin/debug endpoints.

## Login Endpoint

`POST /api/auth-login` is an API-facing login/introspection endpoint. Clients first sign in with Firebase, then send the current Pokoin bearer token in the `Authorization` header. The endpoint validates the token and returns safe metadata such as UID, email, auth time, and expiry.

This endpoint does not mint a separate long-lived secret. Firebase refresh tokens remain managed by the Firebase SDK, and the public Pokoin bearer token remains a short-lived Firebase ID token refreshed by the client wrapper.

## Logout

Logout is client-side because there is no server-side Pokoin session store:

1. Call `AuthService.signOut()`.
2. Firebase signs out.
3. `PokoinApiAuthService` clears the cached bearer token.
4. User-scoped local profile, balance, and cart caches are cleared or switched
   away from the previous UID.
5. Future `PokoinApiClient` required-auth calls fail until the user signs in again.

Add a server logout endpoint only if Pokoin later introduces server-side sessions, token revocation, or a persisted API token table.

## Required Environment

Firebase Admin validation requires these Vercel env vars:

```text
FIREBASE_PROJECT_ID
FIREBASE_CLIENT_EMAIL
FIREBASE_PRIVATE_KEY
FIREBASE_STORAGE_BUCKET
```

If these are missing, protected API calls return authentication errors even though client login can still persist locally.

## Implementation Notes

- Keep Firebase ID token as the source of truth unless a deliberate server-side token store is introduced.
- Do not save custom long-lived bearer tokens in local storage.
- Do not print bearer tokens in logs, docs, or UI.
- New protected APIs should use `verifyBearerToken(req)` rather than parsing `Authorization` manually.
- New Flutter API calls should use `PokoinApiClient` rather than calling `FirebaseAuth.instance.currentUser?.getIdToken()` directly.
- Keep profile-picture display cache keys based on `photoUrl`, not generic
  profile `updatedAt`. Custom and Google avatars are stored under immutable R2
  keys, so a new URL is enough to bust image cache after upload/removal.
