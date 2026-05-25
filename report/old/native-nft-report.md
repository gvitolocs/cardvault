# Pokoin Native NFT Report

PokoinPoS now supports native NFTs directly in the chain runtime. This is not ERC-721 or ERC-1155 smart contract support; NFTs are first-class Pokoin ledger objects validated by the chain and exposed through node APIs.

## Current Status

Live API:

```text
GET https://rpc.pokoin.com/chain/nfts
```

Current response if no NFTs are minted:

```json
{
  "count": 0,
  "tokens": []
}
```

NFT support is deployed on the public RPC node via:

```text
newisdom/pokoinpos-peer:latest
```

MetaMask remains supported for PKN balances and transfers only. NFT inventory should be displayed through Pokoin, Card Vault, or explorer UI using the native NFT APIs.

## NFT Data Model

Each NFT stores:

```json
{
  "collectionId": "pokemon-cards",
  "tokenId": "base-set-charizard-4-psa12345678",
  "owner": "0xUSER_WALLET",
  "minter": "validator-account",
  "metadataUri": "https://.../metadata.json",
  "metadataHash": "sha256:...",
  "imageUri": "https://.../front.png",
  "mintTx": "nft-...",
  "lastTx": "nft-..."
}
```

Important fields:

- `collectionId`: NFT collection namespace, for example `pokemon-cards`.
- `tokenId`: unique token identifier inside the collection.
- `owner`: current owner account or wallet.
- `metadataUri`: pointer to full off-chain metadata.
- `metadataHash`: integrity hash for the metadata content.
- `imageUri`: optional direct image URL.
- `mintTx`: transaction ID that created the NFT.
- `lastTx`: most recent transaction affecting ownership.

## Public API

List all NFTs:

```text
GET https://rpc.pokoin.com/chain/nfts
```

List NFTs by owner:

```text
GET https://rpc.pokoin.com/chain/nfts?owner=<wallet-or-account>
GET https://rpc.pokoin.com/chain/nfts/owner/<wallet-or-account>
```

Get one NFT:

```text
GET https://rpc.pokoin.com/chain/nfts/{collectionId}/{tokenId}
```

Example:

```text
GET https://rpc.pokoin.com/chain/nfts/pokemon-cards/base-set-charizard-4-psa12345678
```

## Minting

Minting is currently admin/operator controlled:

```text
POST /admin/nft/mint
Authorization: Bearer <POKOINPOS_OPERATOR_TOKEN>
```

Example body:

```json
{
  "collectionId": "pokemon-cards",
  "tokenId": "base-set-charizard-4-psa12345678",
  "owner": "0xUSER_WALLET",
  "metadataUri": "https://cardvault.pokoin.com/api/nft-metadata/base-set-charizard-4-psa12345678",
  "metadataHash": "sha256:...",
  "imageUri": "https://cardvault.pokoin.com/cards/base-set-charizard-4/front.png"
}
```

## Real Pokemon Card Use Case

Recommended token ID format:

```text
{set}-{cardNameOrNumber}-{gradingCompany}{certNumber}
```

Example:

```text
base-set-charizard-4-psa12345678
```

The chain should store only ownership plus metadata pointer/hash. The full metadata should live in Card Vault or IPFS and include:

```json
{
  "name": "Charizard",
  "set": "Base Set",
  "cardNumber": "4/102",
  "gradingCompany": "PSA",
  "grade": "10",
  "certNumber": "12345678",
  "condition": "Gem Mint",
  "frontImage": "https://...",
  "backImage": "https://...",
  "verificationStatus": "verified",
  "vaultRecordId": "..."
}
```

## Current Limitations

- NFTs are native Pokoin NFTs, not ERC-721 or ERC-1155.
- They will not automatically appear in MetaMask's NFT tab.
- Metadata is stored as URI/hash fields, not full on-chain JSON.
- Metadata update transactions are not implemented yet, so minted metadata should be treated as immutable.
- Transfers are currently operator/admin controlled unless wallet-signed native NFT transfer support is added later.
