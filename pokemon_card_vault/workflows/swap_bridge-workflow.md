# Swap Bridge Workflow

The Pokoin swap bridge is the routing layer behind the wallet swap UI. It
chooses between native PokoinSwap AMM execution and external-asset bridge
crediting.

The user-facing goal is simple: the wallet can show `Sell <asset>` and
`Buy <asset>`. The backend decides whether that means a native AMM swap, an
external deposit that gets verified and credited, or a queued outbound crypto
settlement.

## Routes

### Native PokoinSwap AMM

Use this route when a live PokoinPoS pool exists for the selected asset.

Flow:

1. Wallet loads pools from `https://rpc.pokoin.com/chain/swap/pools`.
2. Wallet requests quote from `https://rpc.pokoin.com/chain/swap/quote`.
3. Wallet switches MetaMask to PokoinPoS.
4. Wallet sends an `eth_sendTransaction` to router
   `0x0000000000000000000000000000000000002606`.
5. Calldata starts with `pokoinswap:v1:` and contains the AMM payload.
6. PokoinPoS validators replay the swap deterministically from block data.

This is not Uniswap or PancakeSwap. It is native chain logic.

### EVM Asset Bridge

Use this route for supported EVM assets. Approved external assets use this
market-priced bridge route even if an experimental native AMM pool is visible,
so ETH/BTC/BNB quotes do not accidentally route through tiny test pools.

Supported assets:

- `ETH`: native Ethereum transfer.
- `BNB`: native BNB Chain transfer.
- `USDT`, `USDC`, `DAI`, `CAKE`: ERC-20 on BNB Chain.
- `LINK`, `UNI`: ERC-20 on Ethereum.

Flow:

1. Wallet requests `POST /api/crypto-pkn-purchase/quote`.
2. Backend prices the asset in USD, prices PKN at `1 PKN = 0.005 USDT`, applies
   fee bps, stores an expiring quote, and returns settlement metadata.
3. Wallet asks MetaMask to switch chain and send:
   - native transfer for ETH/BNB;
   - ERC-20 `transfer(settlementAddress, amount)` for tokens.
4. Wallet submits the resulting transaction hash to
   `POST /api/crypto-pkn-purchase/request`.
5. Backend verifies quote ownership, quote expiry, tx status, sender, recipient,
   amount, and tx reuse.
6. Backend credits `balances/{uid}.availablePkn` and writes ledger records.

### Bitcoin Bridge

Use this route for `BTC`.

Bitcoin cannot be sent through MetaMask and cannot be handled by a Uniswap or
PancakeSwap fork. The bridge uses direct Bitcoin deposit verification.

Flow:

1. Wallet requests `POST /api/crypto-pkn-purchase/quote` with `asset: "BTC"`.
2. Backend returns PKN output and `BITCOIN_SETTLEMENT_ADDRESS`.
3. Wallet displays the Bitcoin address and asks the user to send BTC.
4. User pastes the Bitcoin transaction id after broadcast/confirmation.
5. Wallet submits the txid to `POST /api/crypto-pkn-purchase/request`.
6. Backend fetches the transaction from `BITCOIN_EXPLORER_API_URL`.
7. Backend verifies:
   - txid format;
   - transaction exists;
   - minimum confirmations;
   - output pays `BITCOIN_SETTLEMENT_ADDRESS`;
   - output amount is at least the quoted BTC amount;
   - txid has not already been used.
8. Backend credits PKN to the account balance.

### PKN To External Crypto Bridge

Use this route for `Sell PKN` / `Buy BTC`, `ETH`, `BNB`, or supported tokens
when a live native AMM pool is not available yet.

This route supports automatic payout when a funded payout key is configured.
EVM assets use an EVM private key. BTC uses a dedicated Bitcoin WIF hot-wallet
key and Blockstream-compatible UTXO/broadcast APIs.

Flow:

1. Wallet requests `POST /api/crypto-pkn-sale/quote` with the target asset and
   PKN amount.
2. Backend prices PKN at `1 PKN = 0.005 USDT`, prices the target asset in USD,
   applies sell-side fee bps, stores an expiring quote, and returns the expected
   output only if the payout wallet has enough available liquidity.
3. Wallet asks the user for a payout address on the target chain.
4. Wallet switches MetaMask to PokoinPoS and sends native PKN to the Pokoin
   treasury wallet.
5. Wallet submits the PKN funding transaction hash to
   `POST /api/crypto-pkn-sale/request`.
6. Backend verifies quote ownership, quote expiry, linked wallet sender,
   treasury recipient, PKN amount, payout address format, and transaction
   idempotency.
7. If `CRYPTO_PKN_SELL_ENABLED` is false, backend rejects new requests.
8. If `CRYPTO_PKN_AUTO_PAYOUT_ENABLED` is true, backend signs and broadcasts the
   external payout for configured EVM assets or BTC.
9. If the signing key or liquidity is unavailable, backend records the request
   as `pending_liquidity` or `manual_settlement`.

Recommended request states:

- `quoted`: quote exists and is unused.
- `pending_liquidity`: PKN was received on PokoinPoS, but payout liquidity is
  not available.
- `manual_settlement`: operator action is required before payout.
- `payout_submitted`: outbound crypto tx was broadcast.
- `completed`: outbound crypto tx is confirmed and ledger entries are final.
- `failed`: request was rejected or payout failed before final settlement.

## Pricing

PKN reference price:

```text
1 PKN = 0.005 USDT
```

Stablecoins use `1 USD`.

Non-stable EVM assets and BTC use:

1. env override when provided, for example `CRYPTO_PKN_BTC_USD_PRICE`;
2. CoinGecko live USD pricing when no override is set.

The quote is short-lived and stored before payment. The request step verifies
that the submitted transaction matches the quote.

For `PKN -> external crypto`, the same reference price is used in reverse:

```text
targetCryptoOut = (pknIn * 0.005 USD) / targetAssetUsdPrice
```

The backend owns the final calculation and applies sell-side fees before
returning the quote.

## Settlement Addresses

EVM settlement:

```text
CRYPTO_PKN_SETTLEMENT_ADDRESS
```

Bitcoin settlement:

```text
BITCOIN_SETTLEMENT_ADDRESS
```

These addresses receive the external assets. PKN credited to the user is an
account-balance credit in Firebase, not an immediate on-chain PKN transfer.
Users can later withdraw PKN through the existing withdrawal flow.

## Firestore Collections

The bridge writes:

- `crypto_pkn_purchase_quotes`
- `crypto_pkn_purchase_requests`
- `crypto_pkn_purchase_deposits`
- `crypto_pkn_sale_quotes`
- `crypto_pkn_sale_requests`
- `crypto_pkn_sale_payouts`
- `balances`
- `ledger_entries`

The deposit hash/txid is the idempotency key and cannot be reused.

## Security Invariants

- Quote must belong to the authenticated Firebase user.
- Quote must be unused and unexpired.
- EVM sender must match the user linked wallet.
- EVM recipient must match `CRYPTO_PKN_SETTLEMENT_ADDRESS`.
- BTC output must pay `BITCOIN_SETTLEMENT_ADDRESS`.
- Deposit amount must be at least the quoted input amount.
- Deposit tx hash/txid must not already exist in
  `crypto_pkn_purchase_deposits`.
- `PKN -> external crypto` requests must verify that the native PKN funding
  transaction was sent by the user's linked wallet to the Pokoin treasury before
  any payout is attempted.
- External payout addresses must be validated for the selected target chain.
- `PKN -> external crypto` quotes are refused when the configured payout wallet
  balance is lower than the quoted output.
- Automatic payouts require explicit liquidity and feature flags.
- Backend never trusts frontend-computed PKN output.

## Environment

```text
CRYPTO_PKN_SETTLEMENT_ADDRESS=0x...
CRYPTO_PKN_USDT_PRICE=0.005
CRYPTO_PKN_FEE_BPS=100
CRYPTO_PKN_SELL_ENABLED=true
CRYPTO_PKN_SELL_FEE_BPS=100
CRYPTO_PKN_AUTO_PAYOUT_ENABLED=true
CRYPTO_PKN_EVM_PAYOUT_PRIVATE_KEY=
CRYPTO_PKN_QUOTE_TTL_MS=60000
ETHEREUM_RPC_URL=https://ethereum.publicnode.com
BNB_RPC_URL=https://bsc-dataseed.binance.org
BITCOIN_SETTLEMENT_ADDRESS=bc1q253wlm72m9s346y0jj4pcjey9xyn5wz9yxp8uf
BITCOIN_PAYOUT_ADDRESS=
BITCOIN_PAYOUT_PRIVATE_KEY_WIF=
BITCOIN_NETWORK=mainnet
BITCOIN_MIN_PAYOUT_BTC=0.00001
BITCOIN_MAX_PAYOUT_BTC=0.01
BITCOIN_FEE_RATE_SATS_PER_VBYTE=
BITCOIN_EXPLORER_API_URL=https://blockstream.info/api
BITCOIN_MIN_CONFIRMATIONS=1
USDT_BNB_CONTRACT_ADDRESS=0x55d398326f99059fF775485246999027B3197955
USDC_BNB_CONTRACT_ADDRESS=0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d
DAI_BNB_CONTRACT_ADDRESS=0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3
LINK_ETH_CONTRACT_ADDRESS=0x514910771af9ca656af840dff83e8264ecf986ca
UNI_ETH_CONTRACT_ADDRESS=0x1f9840a85d5af5bf1d1762f925bdaddc4201f984
CAKE_BNB_CONTRACT_ADDRESS=0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82
```

Optional pricing overrides:

```text
CRYPTO_PKN_ETH_USD_PRICE=
CRYPTO_PKN_BNB_USD_PRICE=
CRYPTO_PKN_BTC_USD_PRICE=
CRYPTO_PKN_LINK_USD_PRICE=
CRYPTO_PKN_UNI_USD_PRICE=
CRYPTO_PKN_CAKE_USD_PRICE=
```

## Implementation Files

- `api/crypto-pkn-purchase.js`
- `api/_crypto_pkn_purchase.js`
- `api/_crypto_pkn_purchase.test.js`
- `api/crypto-pkn-sale.js`
- `lib/wallet/main.dart`
- `lib/wallet/auth_service.dart`
- `lib/wallet/wallet_bridge.dart`
- `lib/wallet/wallet_bridge_web.dart`
- `web/index.html`
- `/Users/giuseppe/pokoinpos/docs/pokoin-swap.md`

## Validation

Run from `pokemon_card_vault`:

```bash
flutter analyze
node --test api/*.test.js
```
