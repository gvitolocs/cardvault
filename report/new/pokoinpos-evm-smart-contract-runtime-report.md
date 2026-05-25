# PokoinPoS EVM Smart Contract Runtime Report

PokoinPoS now has a first embedded EVM smart contract execution layer inside the native Proof-of-Stake node. This is the foundation needed before deploying Uniswap/Pancake-style contracts on the Pokoin chain.

## What Changed

- Data-bearing wallet-signed EVM transactions are executed through the embedded go-ethereum VM during PoS block replay.
- Contract bytecode is persisted in deterministic ledger state.
- Contract storage is persisted in deterministic ledger state.
- EVM execution receipts are persisted and rebuilt from the canonical chain.
- Contract deployment receipts include `contractAddress`.
- Contract logs are captured and exposed through JSON-RPC.
- The peer Docker image was rebuilt and pushed to Docker Hub.

Latest Docker image:

```text
newisdom/pokoinpos-peer:latest
sha256:be3b51c7d2b5664b589e59b92a97f4b775bd5e126edee46f5f2c118b75888e4d
```

## Supported JSON-RPC Surface

The public `/rpc` endpoint now supports the smart contract foundation methods:

- `eth_sendRawTransaction`
- `eth_getCode`
- `eth_call`
- `eth_getStorageAt`
- `eth_getLogs`
- `eth_getTransactionReceipt`
- `eth_estimateGas`
- `eth_getTransactionByHash`
- block and transaction lookup methods already documented in the node API docs

`eth_sendTransaction` is still intentionally unsupported because nodes do not unlock private keys. Wallets and deployment tools must sign locally and submit raw transactions.

## Verification Performed

Code-level verification:

- `make test`
- `make vet`
- `make lint`
- `go test ./...`

Runtime rollout verification:

- Public RPC health returned `ok`.
- Public chain status returned height `701`, committed height `700`, peer count `3`, mempool `0`.
- Public bootstrap status had no refresh error.
- Public `eth_getCode` request returned successfully.
- Watchtower restarted the public RPC node after the Docker image push.

Test coverage now includes:

- Deploying EVM bytecode from a signed transaction.
- Reading deployed code with `eth_getCode`.
- Calling deployed code with `eth_call`.
- Verifying deployment receipt `contractAddress`.
- Verifying EVM deployment gas is not the fixed native transfer placeholder.
- Reading empty storage with `eth_getStorageAt`.
- Querying logs with `eth_getLogs`.

## Documentation Already Updated

The PokoinPoS repository docs were updated:

- `docs/blockchain-update-workflow.md`
- `docs/docker-hub-overview.md`
- `docs/node-endpoints.md`
- `docs/wallet-compatibility.md`

The workflow now includes post-rollout EVM RPC checks. The Docker overview contains the latest image digest. The endpoint and wallet docs no longer say smart contracts are unimplemented; they now describe the embedded EVM foundation and remaining dApp compatibility work.

## Important Product Wording

Recommended wording for the site:

PokoinPoS now includes an embedded EVM smart contract runtime for initial dApp and DEX deployment testing. This makes PokoinPoS closer to EVM tooling compatibility, but full Uniswap/Pancake deployment support still needs iterative testing against the actual factory, pair, router, multicall, and ERC-20 deployment scripts.

Avoid saying:

- "PokoinPoS is fully Ethereum compatible."
- "All Uniswap/Pancake contracts are already deployed."
- "Every ERC-20/BEP-20 token is live on PokoinPoS."

Safer wording:

- "PokoinPoS now supports the first embedded EVM smart contract execution layer."
- "Contract bytecode, storage, receipts, and logs are persisted by the native PoS ledger."
- "The next milestone is deploying and validating the DEX contract stack."

## Remaining Work

To complete a real Uniswap/Pancake-style deployment:

1. Add or fork the DEX contracts in a deployment workspace.
2. Configure Hardhat/ethers for PokoinPoS chain ID `26062026`.
3. Deploy ERC-20 test tokens, factory, pair, router, and multicall contracts.
4. Run the deployment scripts against `https://rpc.pokoin.com/rpc`.
5. Fill any missing Ethereum JSON-RPC methods discovered by the deploy tooling.
6. Theme the DEX frontend for Pokoin.
7. Connect the frontend token list to deployed PokoinPoS contracts and existing native PokoinSwap accounting assets.

## Relationship To Native PokoinSwap

Native PokoinSwap still exists and remains the production swap surface in the wallet. It is deterministic chain-native AMM logic for `PKN` against internal accounting assets such as `WPKN`, `BTC`, `ETH`, `BNB`, and custom symbols with seeded pools.

The new EVM runtime is separate. It enables smart contract deployment and testing, which is required before a true Uniswap/Pancake fork can run directly on PokoinPoS.
