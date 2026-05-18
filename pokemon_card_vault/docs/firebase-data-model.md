# Firebase Data Model

Pokoin uses Firebase Auth for identity and Firestore for marketplace data.

## Collections

- `users/{uid}`: public account profile.
  - `email`
  - `displayName`
  - `photoUrl`
  - `walletAddress`
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
  - `items`
  - `totalPkn`
  - `status`
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
must not directly mutate `balances` or settled `ledger_entries`. Balance changes
should be finalized by trusted backend code or an admin process after validating
orders, deposits, and on-chain payouts.

Card listings are mutable user marketplace data in Firestore. Card catalog and
blueprint metadata stay in Supabase; listing documents store only lightweight
card snapshots needed for smooth carts, orders, and seller rows.
