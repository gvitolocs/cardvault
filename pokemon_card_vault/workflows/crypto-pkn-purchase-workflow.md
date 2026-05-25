# Crypto To PKN Purchase Workflow

CardVault lets users buy PKN with supported external crypto assets from the
wallet swap screen. The UX looks like a swap, but the settlement path is quote,
deposit, verify, and credit. This is the CardVault bridge workflow for external
assets entering the Pokoin account-balance system.

The reverse direction, `Sell PKN` / `Buy external crypto`, is documented in
`workflows/swap_bridge-workflow.md`. That route can be built before external
liquidity is funded, but automatic payout must remain disabled until settlement
wallets or pools are ready.

## User Flow

1. User opens `/wallet`.
2. Swap defaults to `Sell ETH` and `Buy PKN`.
3. User enters an amount.
4. Wallet calls `POST /api/crypto-pkn-purchase/quote`.
5. Backend prices PKN at `1 PKN = 0.005 USDT`, applies fees, stores an expiring
   quote, and returns settlement details.
6. Wallet asks MetaMask to send EVM assets:
   - native ETH on Ethereum;
   - native BNB on BNB Chain;
   - ERC-20 transfer for supported tokens.
7. For BTC, wallet shows the configured Bitcoin settlement address and asks the
   user to paste the confirmed Bitcoin transaction id.
8. Wallet calls `POST /api/crypto-pkn-purchase/request` with the quote id and
   deposit transaction hash.
9. Backend verifies the deposit and credits `balances/{uid}.availablePkn`.

## Supported Assets

Auto-verified assets:

- `BTC`: Bitcoin deposit to `BITCOIN_SETTLEMENT_ADDRESS`.
- `ETH`: native transfer on Ethereum.
- `BNB`: native transfer on BNB Chain.
- `USDT`, `USDC`, `DAI`, `CAKE`: ERC-20 transfers on BNB Chain.
- `LINK`, `UNI`: ERC-20 transfers on Ethereum.

BTC does not use MetaMask, PancakeSwap, or Uniswap. It is a direct Bitcoin
deposit flow: quote, send to the configured Bitcoin address, paste txid, verify
with the Bitcoin explorer API, then credit PKN.

EVM assets do not require deploying a Uniswap/Pancake fork for deposits. The
bridge accepts native coin or ERC-20 transfers into the configured settlement
wallet, verifies them on-chain, then credits PKN. Native PokoinSwap AMM pools
remain separate and are used only when a live PokoinPoS pool exists.

## Backend API

Quote:

```bash
curl -X POST https://pokoin.com/api/crypto-pkn-purchase/quote \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"asset":"ETH","amountIn":0.01}'
```

Request credit:

```bash
curl -X POST https://pokoin.com/api/crypto-pkn-purchase/request \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"quoteId":"<QUOTE_ID>","depositTxHash":"0x..."}'
```

Status:

```bash
curl https://pokoin.com/api/crypto-pkn-purchase/status \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>"
```

## Verification Rules

The backend rejects credit unless all checks pass:

- Firebase bearer token is valid.
- Quote exists, belongs to the user, is unused, and has not expired.
- User has a linked wallet.
- Deposit tx exists and succeeded/confirmed on the expected chain.
- EVM deposit sender matches the linked wallet.
- BTC deposit pays the configured Bitcoin settlement address.
- Deposit recipient is the configured settlement wallet.
- Deposit amount is at least the quoted input amount.
- Deposit tx hash has not already been used.

The deposit tx hash is stored in `crypto_pkn_purchase_deposits` and acts as the
idempotency key.

## Firestore Writes

Successful credit writes:

- `crypto_pkn_purchase_quotes/{quoteId}` with `status: credited`.
- `crypto_pkn_purchase_requests/{requestId}` with request details.
- `crypto_pkn_purchase_deposits/{depositTxHash}` to prevent reuse.
- `balances/{uid}.availablePkn` incremented by quoted PKN output.
- `ledger_entries/{autoId}` with `type: crypto_pkn_purchase_credit`.

## Environment

Required or recommended env vars:

```text
CRYPTO_PKN_SETTLEMENT_ADDRESS=0x74466c3a204429B22CE8558F3F18f3C59F67fCB3
CRYPTO_PKN_USDT_PRICE=0.005
CRYPTO_PKN_FEE_BPS=100
CRYPTO_PKN_QUOTE_TTL_MS=60000
ETHEREUM_RPC_URL=https://ethereum.publicnode.com
BNB_RPC_URL=https://bsc-dataseed.binance.org
USDT_BNB_CONTRACT_ADDRESS=0x55d398326f99059fF775485246999027B3197955
USDC_BNB_CONTRACT_ADDRESS=0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d
DAI_BNB_CONTRACT_ADDRESS=0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3
LINK_ETH_CONTRACT_ADDRESS=0x514910771af9ca656af840dff83e8264ecf986ca
UNI_ETH_CONTRACT_ADDRESS=0x1f9840a85d5af5bf1d1762f925bdaddc4201f984
CAKE_BNB_CONTRACT_ADDRESS=0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82
```

Optional market price overrides:

```text
CRYPTO_PKN_ETH_USD_PRICE=
CRYPTO_PKN_BNB_USD_PRICE=
CRYPTO_PKN_BTC_USD_PRICE=
CRYPTO_PKN_LINK_USD_PRICE=
CRYPTO_PKN_UNI_USD_PRICE=
CRYPTO_PKN_CAKE_USD_PRICE=
BITCOIN_SETTLEMENT_ADDRESS=bc1q253wlm72m9s346y0jj4pcjey9xyn5wz9yxp8uf
BITCOIN_EXPLORER_API_URL=https://blockstream.info/api
BITCOIN_MIN_CONFIRMATIONS=1
```

If a market override is empty, the backend uses CoinGecko for non-stablecoin
USD pricing. Stablecoins use `1`.

## Implementation Files

- `api/crypto-pkn-purchase.js`: quote, request, status route.
- `api/_crypto_pkn_purchase.js`: pricing, asset config, and deposit verification.
- `api/_crypto_pkn_purchase.test.js`: quote behavior coverage.
- `lib/wallet/main.dart`: swap UI, quote handling, and purchase submission.
- `lib/wallet/auth_service.dart`: authenticated API calls.
- `lib/wallet/wallet_bridge.dart`: platform bridge contract.
- `lib/wallet/wallet_bridge_web.dart`: JS interop bridge.
- `web/index.html`: MetaMask native send and ERC-20 transfer helpers.
- `workflows/swap_bridge-workflow.md`: high-level bridge architecture.

## Validation

Run:

```bash
flutter analyze
node --test api/*.test.js
```

Current expected result: analyzer has no issues and all API tests pass.
