# Firebase Data Model

Pokoin uses Firebase Auth for identity and Firestore for mutable user data.
Marketplace catalog/search/blueprint metadata lives in Oracle Postgres, not in
Firestore.

## Collections

- `users/{uid}`: public account profile.
  - `email`
  - `displayName`
  - `photoUrl`
  - `walletAddress`
  - `role`
  - `roles`
  - `reserve`
  - `isReserve`
  - `hasReserveAccess`
  - `createdAt`
  - `updatedAt`
- `balances/{uid}`: internal marketplace PKN credit.
  - `availablePkn`
  - `lockedPkn`
  - `updatedAt`
- `ledger_entries/{entryId}`: append-only balance movement audit trail.
  - `uid`
  - `type`
  - `amountPkn`
  - `status`
  - `referenceId`
  - `createdAt`
- `orders/{orderId}`: marketplace order history.
  - `uid`
  - `buyerUid`
  - `buyerEmail`
  - `items`
  - `subtotalPkn`
  - `totalPkn`
  - `status`
  - `paymentStatus`
  - `fulfillmentStatus`
  - `sellerUids`
  - `paidAt`
  - `createdAt`
  - `updatedAt`
- `order_seller_sale_notifications/{orderId}__{sellerUid}`: durable seller
  sale email marker for one paid order and seller.
  - `orderId`
  - `sellerUid`
  - `sellerEmail`
  - `status`
  - `deliveryId`
  - `sentAt`
  - `createdAt`
  - `updatedAt`
- `card_listings/{listingId}`: seller-created live marketplace offers.
  - `cardId`
  - `sellerUid`
  - `sellerName`
  - `sellerCountry`
  - `sellerReputationLabel`
  - `condition`
  - `language`
  - `pricePkn`
  - `quantityAvailable`
  - `signed`
  - `reverse`
  - `graded`
  - `gradingCompany`
  - `grade`
  - `certificationId`
  - `shippingAvailable`
  - `nftAvailable`
  - `status`
  - `cardName`
  - `cardImageUrl`
  - `setName`
  - `collectorNumber`
  - `createdAt`
  - `updatedAt`
- `seller_integrations/{uid}__cardtrader`: encrypted seller integration state for
  CardTrader inventory sync.
  - `uid`
  - `provider`
  - `enabled`
  - `metadata` with safe CardTrader app/user/seller/scopes
  - `encryptedToken` AES-256-GCM envelope
  - `encryptedSharedSecret` AES-256-GCM envelope for webhook verification
  - `connectedAt`
  - `lastValidatedAt`
  - `disconnectedAt`
  - `updatedAt`
- `user_carts/{uid}`: user cart with selected listing snapshots.
  - `items`
  - `updatedAt`
- `withdraw_requests/{requestId}`: user payout requests.
  - `uid`
  - `toAddress`
  - `amountPkn`
  - `status`
  - `createdAt`
  - `updatedAt`

## Security Boundary

The Flutter web client can create user profiles and withdraw requests, but it
must not directly mutate `balances`, settled `ledger_entries`, or paid
marketplace orders. Balance changes should be finalized by trusted backend code
or an admin process after validating orders, deposits, and on-chain payouts.

Card listings are mutable user marketplace data in Firestore. Card catalog,
blueprint metadata, expansion/version rows, search projections, and hot
blueprint analytics live in Oracle Postgres. Listing documents store only
lightweight card snapshots needed for smooth carts, orders, and seller rows.

Marketplace checkout uses `POST /api/marketplace-orders` as the trusted paid
fulfillment point. The backend checks buyer PKN balance, decrements Oracle
listings, creates the paid order, credits seller balances, then sends one
`market@pokoin.com` seller sale email per seller per order. Email retries are
deduped with `order_seller_sale_notifications` documents.

Marketplace interaction analytics are not Firestore user documents. Flutter
sends bounded non-PII event metadata to `/api/marketplace-event`; Oracle stores
raw events in `public.marketplace_card_events` and rollups in
`public.marketplace_hot_blueprints`.

Reserve marketplace listings are a trusted server-side role boundary. A user can
set or maintain `reserveAvailable` listings only when Firebase custom claims or
`users/{uid}` grant reserve access with one of these shapes: `reserve: true`,
`isReserve: true`, `hasReserveAccess: true`, `role: "reserve"`, or `roles`
containing `reserve`. Use `node scripts/set-firebase-reserve-role.js
--identifier=pknreserve` to dry-run identity resolution, then add `--apply` only
when the script reports exactly one candidate.

CardTrader seller tokens and webhook shared secrets are password-equivalent
secrets. Flutter may submit a token to `/api/cardtrader-connect`, but after that
the token stays server-side and is stored only as an AES-256-GCM envelope using
`CARDTRADER_TOKEN_ENCRYPTION_KEY`. Status APIs return safe metadata only.
