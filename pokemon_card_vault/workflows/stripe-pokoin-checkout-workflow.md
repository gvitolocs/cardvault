# Stripe Pokoin Checkout Workflow

Use this workflow when changing, deploying, or debugging card payments for PKN
account balance credits on `pokoin.com`.

This document complements the API index in `docs/pokoin-api.md`. Keep endpoint
details synchronized there, but use this file for operational checkout and
payment troubleshooting steps.

## Runtime Contract

The checkout path is:

1. The Flutter `/buy` page in `lib/screens/buy_pkn_screen.dart` collects a fixed
   PKN package and sends an authenticated `POST` to
   `/api/create-pkn-checkout-session`.
2. `api/create-pkn-checkout-session.js` verifies the Firebase bearer token,
   validates the requested package, resolves the matching Stripe price by
   lookup key when available, and creates a Stripe Checkout Session.
3. Stripe redirects the user back to `/buy?status=success&session_id=...`.
4. The client posts the returned `checkoutSessionId` back to
   `/api/create-pkn-checkout-session` to confirm the session for the signed-in
   user.
5. Stripe also calls `POST /api/stripe-webhook` with
   `checkout.session.completed`.
6. `api/_pkn_purchase.js` credits `balances/{uid}.availablePkn`, records
   `pkn_purchases/{stripeSessionId}`, and appends a `ledger_entries` row.

The webhook and the client return-confirmation path both call
`handleCompletedCheckout`. The Stripe Checkout Session id is the idempotency key:
if `pkn_purchases/{session.id}` already exists, fulfillment returns the stored
result instead of crediting the balance again.

## Required Vercel Environment

Document names only. Never paste values into docs, logs, tickets, or chat.

Required for checkout creation and fulfillment:

```text
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
FIREBASE_PROJECT_ID
FIREBASE_CLIENT_EMAIL
FIREBASE_PRIVATE_KEY
FIREBASE_STORAGE_BUCKET
PUBLIC_SITE_URL
```

Recommended or optional:

```text
STRIPE_API_VERSION
PKN_CHECKOUT_CURRENCY
PKN_CHECKOUT_USDT_PRICE
RESEND_API_KEY
NO_REPLY_EMAIL_FROM
```

`PUBLIC_SITE_URL` should be set to the canonical production origin,
`https://pokoin.com`, so Stripe success and cancel URLs return to the right
site. If it is missing, the current API falls back to `https://pokoin.com`, but
operators should still verify the variable exists in production.

## Common Failure: Plain Text From Vercel

If Vercel returns plain text such as `FUNCTION_INVOCATION_FAILED`, the request
failed before the API handler produced JSON. In Flutter this used to surface as
a `FormatException` while decoding the response. The client now treats non-JSON
checkout responses as temporary checkout unavailability, but the backend still
needs the module-load error fixed.

Diagnose in this order:

```bash
node --check api/create-pkn-checkout-session.js
node --check api/stripe-webhook.js
node -e "require('./api/create-pkn-checkout-session'); require('./api/stripe-webhook'); console.log('checkout modules loaded')"
```

If the failure only appears in the built Vercel layout, build first and check
the copied functions:

```bash
./deploy-pokoin-web.sh
cd build/web
node --check api/create-pkn-checkout-session.js
node --check api/stripe-webhook.js
node -e "require('./api/create-pkn-checkout-session'); require('./api/stripe-webhook'); console.log('deployed-layout modules loaded')"
```

Do not deploy just to run the built-layout checks unless the user asked for a
deploy. A local `flutter build web` plus the API copy steps in
`deploy-pokoin-web.sh` can be used when the goal is diagnosis only.

After a deployment exists, inspect live function output without secrets:

```bash
vercel logs pokoin.com --since 1h
curl -i -sS -X POST https://pokoin.com/api/create-pkn-checkout-session \
  -H "Content-Type: application/json" \
  -d '{}'
curl -i -sS https://pokoin.com/api/stripe-webhook
```

Expected healthy probes are JSON authentication or validation errors for the
protected checkout endpoint, and `405 Method not allowed` for a non-POST webhook
probe. Plain text `FUNCTION_INVOCATION_FAILED`, a 500 before handler logging, or
`MODULE_NOT_FOUND` in `vercel logs` points to module resolution or missing
deployment files rather than Stripe.

Recent checkout code supports both source and deployed layouts by trying
`../server/<helper>` first and falling back to `./<helper>`. Keep that pattern
for helpers used by API files copied into `build/web/api`.

## Deploy And Alias

Production web/API deployment is handled by:

```bash
./deploy-pokoin-web.sh
```

That script builds Flutter web, copies API functions into `build/web/api`,
copies shared server helpers into `build/web/server`, writes the Vercel project
metadata, and runs `vercel deploy --prod --yes` from `build/web`.

Before deploying, verify the production env variable names exist:

```bash
vercel env ls
```

After deployment, verify the production alias and checkout endpoints:

```bash
curl -I https://pokoin.com/buy
curl -i -sS -X POST https://pokoin.com/api/create-pkn-checkout-session \
  -H "Content-Type: application/json" \
  -d '{}'
curl -i -sS https://pokoin.com/api/stripe-webhook
vercel logs pokoin.com --since 30m
```

Do not paste bearer tokens, Stripe secrets, webhook secrets, Firebase private
keys, Resend keys, or customer data into logs or workflow updates.

## Webhook Verification

`api/stripe-webhook.js` reads the raw request body and verifies the
`stripe-signature` header with `STRIPE_WEBHOOK_SECRET`. The handler should only
fulfill `checkout.session.completed` after `stripe.webhooks.constructEvent`
succeeds.

Operational expectations:

- Configure the Stripe webhook endpoint to call
  `https://pokoin.com/api/stripe-webhook`.
- Subscribe at least to `checkout.session.completed`.
- Treat any `Webhook Error: ...` response as signature, endpoint secret, or raw
  body mismatch until proven otherwise.
- Keep fulfillment idempotent by Stripe session id.
- Do not credit PKN from unverified client payloads. The client return path must
  retrieve the Stripe session server-side and confirm the session metadata UID
  matches the authenticated Firebase UID.

## Paid Order Notifications

Current repository code creates marketplace cart orders directly from the
Flutter checkout screen in `lib/services/marketplace_account_service.dart` and
stores them in Firestore `orders` with `status: pending` and
`paymentStatus: reserved`. I did not find an implemented seller sale email
sender in the current checkout or email helper code.

When paid-order seller notifications are implemented, keep this contract:

- Send one email per seller per paid order/cart, not one email per line item.
- Send from a verified marketplace sender such as `market@pokoin.com`.
- Require the production email provider env vars by name, at minimum
  `RESEND_API_KEY` and the configured marketplace sender env var.
- Trigger only after payment is confirmed or PKN balance is actually reserved,
  not when a draft cart or unpaid order is created.
- Store a notification marker on the order, seller subrecord, or deterministic
  email event document so retries do not send duplicates.

Existing email infrastructure in `api/_email.js` uses Resend and supports
provider-backed sender configuration. Add a dedicated marketplace sender helper
rather than reusing verification email defaults.

## Related Files

- `lib/screens/buy_pkn_screen.dart`: Flutter PKN buy page and non-JSON checkout
  response handling.
- `api/create-pkn-checkout-session.js`: authenticated Checkout Session creation
  and return-session confirmation.
- `api/stripe-webhook.js`: Stripe webhook signature verification.
- `api/_pkn_purchase.js`: idempotent PKN credit fulfillment.
- `api/_pkn_checkout_pricing.js`: PKN package pricing helpers.
- `docs/pokoin-api.md`: public API index.
- `.env.example`: environment variable names.
- `deploy-pokoin-web.sh`: production build and Vercel deploy script.
