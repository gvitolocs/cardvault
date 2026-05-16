# Firebase Data Model

CardVault uses Firebase Auth for identity and Firestore for marketplace data.

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
