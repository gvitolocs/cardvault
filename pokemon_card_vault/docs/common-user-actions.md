# Common User Actions

This guide documents common actions users ask about on `pokoin.com`. Keep it in
sync with Pokontact curated answers so the assistant and the public docs explain
the same flows.

## Check If Pokoin Is Online

Users may ask if Pokoin, the chain, RPC, Scan, or the marketplace is online.
Pokontact should answer from live checks instead of memory.

Primary checks:

- Main site: `https://pokoin.com/`
- Wallet: `https://pokoin.com/wallet`
- Scan: `https://pokoin.com/scan`
- RPC health: `https://rpc.pokoin.com/health`
- Chain status: `https://rpc.pokoin.com/chain/status`
- Bootstrap peers: `https://pokoin.com/bootstrap-peers.json`

If RPC health and chain status respond, the PokoinPoS node layer is reachable. If
the main site responds but RPC does not, explain that the website may be online
while the chain API needs attention.

## Use The Wallet

The Pokoin Wallet is served from `https://pokoin.com/wallet` inside the same web
app as the marketplace.

Users can:

- Add or switch MetaMask to the PokoinPoS network.
- View native `PKN` balance from the public RPC.
- Send native `PKN` transactions through the connected browser wallet.
- Open Swap/PokoinSwap for available pools.
- Use the wPKN shortcut for the BNB Chain wrapped token.

Safety language:

- Never ask users for seed phrases, private keys, passwords, API keys, or tokens.
- Remind users to check the selected network before signing.
- Explain that `PKN` is native on PokoinPoS and `wPKN` is wrapped on BNB Chain.

## Add PokoinPoS To MetaMask

Network values:

- Network name: `PokoinPoS`
- Chain ID: `26062026`
- Hex chain ID: `0x18dacca`
- Currency: `PKN`
- Decimals: `18`
- RPC URL: `https://rpc.pokoin.com/rpc`
- Explorer: `https://explorer.pokoin.com`

MetaMask is used for native PKN balances and transfers. Native Pokoin NFTs are
shown by Pokoin/Card Vault or explorer UI, not by MetaMask's NFT tab.

## Buy Or Understand PKN

When users ask how to buy PKN, explain:

- `PKN` is native on PokoinPoS.
- `wPKN` is the BNB Chain wrapped representation of native PKN.
- The app may expose a wallet/buy path or Swap path depending on available pools.
- Users must verify the network and token contract before signing.
- This is not financial advice.

wPKN public facts:

- BNB Chain contract: `0x91A17E2bddfF839078BD395482B38e4AC15276f4`
- PancakeSwap pair: `0x86294c008542C2707B9f67e3E4BA2d03B7bF7451`
- The reserve rule is supply discipline, not a fixed swap rate: circulating wPKN
  must not exceed the native PKN reserve allocation.

## Swap Tokens

PokoinSwap is the native swap interface for PokoinPoS assets and liquidity pools.

Expected behavior:

- Swap should quote dynamically while the user types.
- Swap should only enable assets with a live pool and liquidity.
- Unsupported assets should be discoverable/explainable but not swappable until
  a pool or supported route exists.
- PKN and wPKN are different assets on different networks; they do not have a
  fixed 1:1 market exchange rate.

If a swap fails, ask for:

- Wallet address.
- Pair/assets.
- Amount.
- Page URL.
- Error text.
- Transaction hash or nonce if available.

Do not ask for private keys or seed phrases.

## Sell Or List A Card

Users may ask how to sell, list, or create an offer for a card.

Direct signed-in sellers to the profile/seller area for listing management.
`Sell`, seller inventory, manage-listing, and seller sync/partner connection actions
belong under `/profile`, `/inventory`, or contextual card/seller tools, not in
the global marketplace top bar.

Explain that seller listings are live marketplace offers stored with:

- condition
- language
- reverse holo flag
- signed flag
- graded flag and grade data
- NFT availability flag
- shipping availability
- price
- quantity

For support, ask what card they are listing, what page they were on, what they
expected, and what error they saw.

## Search For Cards

Marketplace search is backed by Oracle Postgres projections and autocomplete.

Users can search by:

- card name
- set or expansion
- collector number
- variation tokens such as `v`, `ex`, `gx`, `vmax`, `vstar`, `mega`, and `lv.x`
- trainer/owner terms where structured metadata exists

If search results look wrong, ask for the exact query, expected card, page URL,
and screenshot if possible.

## Wishlist, Cart, And Checkout

Common explanations:

- Wishlist saves cards for later.
- Cart rows reference exact seller listings.
- Listing snapshots are preserved so checkout is tied to the selected offer.
- If a cart item is unavailable, the listing may have sold out, been paused, or
  changed by the seller.

## Earn PKN And Shard Cards

Users may ask if they can shard, disenchant, recycle, or turn extra cards into
new cards.

Current implemented flow:

- `https://pokoin.com/earn` explains Earn PKN.
- `https://pokoin.com/shard-review` lets users request a PKN shard review.
- Users can submit a card list or import a full Pokemon decklist.
- Deck shard mode parses Pokemon / Trainer / Energy decklist sections and asks
  users to confirm marketplace version, language, and condition for imported
  cards.
- `POST /api/earn-pkn` receives the completed review request and emails it to
  the Pokoin team.

Assistant wording:

- Explain it like a videogame mechanic: extra cards can be submitted for review,
  eligible cards can be sharded into PKN value, and that value can be used toward
  cards the user actually wants through marketplace/order flows.
- Do not call it an instant guaranteed disenchant button. The team review
  determines eligibility and value.
- Do not promise payouts, prices, guaranteed orders, or financial returns.
- Do not mention specific marketplace partner names. Use neutral phrases like marketplace catalog,
  partner availability, live availability, or external supply.

## Native NFTs

PokoinPoS supports native NFTs as first-class chain ledger objects. They are not
ERC-721 or ERC-1155 contracts.

NFT APIs:

- `GET https://rpc.pokoin.com/chain/nfts`
- `GET https://rpc.pokoin.com/chain/nfts?owner=<wallet-or-account>`
- `GET https://rpc.pokoin.com/chain/nfts/owner/<wallet-or-account>`
- `GET https://rpc.pokoin.com/chain/nfts/{collectionId}/{tokenId}`

NFT fields include `collectionId`, `tokenId`, `owner`, `metadataUri`,
`metadataHash`, `imageUri`, `mintTx`, and `lastTx`.

Minting is currently operator controlled. For real card NFTs, use stable IDs
based on set, card name or number, grading company, and certificate number.

## Create Or Run A Node

If users ask about a node, peer, validator, bootstrap, or "nodo" without naming
another chain, assume they mean PokoinPoS.

Explain three paths:

- Local test node.
- Public Oracle/VPS node.
- Production validator/peer.

Public bootstrap peers require vetting and reliable uptime observed by other
peers. Do not switch to Bitcoin or Ethereum unless the user explicitly names
that chain.

## Report A Bug Or Inquiry

Pokontact should say it is forwarding the issue to the development team and ask
for:

- page URL
- what the user clicked
- expected result
- actual result
- screenshot or error text
- wallet address or transaction hash only if relevant

Never tell the user to email manually. The assistant workflow handles forwarding
bug/inquiry records to the configured project inbox.

## Ask Pokontact

Pokontact can help with:

- project explanations
- crypto basics
- wallet and MetaMask help
- Scan/RPC/network status
- Swap and PKN/wPKN explanations
- marketplace actions
- Earn PKN and PKN shard review
- cute card suggestions without financial advice
- bug and inquiry collection

For common paths, Pokontact should use curated answers and live APIs. The local
LLM should only handle free-form conversation that is not covered by a known
site action.
