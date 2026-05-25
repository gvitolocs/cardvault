# Native PokoinSwap AMM Report

PokoinPoS now has a native PokoinSwap AMM module for `PKN` versus internal `wPKN` accounting balances. This is not Uniswap smart contracts; it is deterministic chain-native logic replayed by validators from PokoinPoS blocks.

## What Is Available

- Public pool discovery: `GET /chain/swap/pools`
- Single pool lookup: `GET /chain/swap/pools/PKN-WPKN`
- Wallet/account balances: `GET /chain/swap/balances/{address}`
- Deterministic quote API: `GET /chain/swap/quote?pool=PKN-WPKN&assetIn=PKN&amountIn=100`
- Wallet-signed swaps through JSON-RPC `eth_sendRawTransaction`

## Operator-Only Actions

These endpoints require `Authorization: Bearer <POKOINPOS_OPERATOR_TOKEN>` and must not be exposed directly from Card Vault frontend code:

- `POST /admin/swap/pools`
- `POST /admin/swap/liquidity/add`
- `POST /admin/assets/credit`
- `POST /admin/assets/debit`

## Data Model

The chain keeps native `PKN` in the existing account ledger and internal assets such as `wPKN` in a separate accounting map. Pools store asset pair, reserves, fee bps, creation transaction, and last update transaction.

The first intended pool is `PKN-WPKN`. Quotes use integer constant-product math with a 30 bps fee and reject swaps that fail `minAmountOut`.

## Card Vault Integration Notes

Card Vault can later use the public APIs to show swap availability, wallet balances, reserve state, and quote previews. Actual user swaps should be initiated from the wallet and submitted as signed raw transactions to `/rpc`; Card Vault should not hold user private keys.

For site documentation, explain that PokoinSwap is native to PokoinPoS and currently scoped to internal `wPKN` accounting, not direct PancakeSwap/Uniswap contract interaction.
