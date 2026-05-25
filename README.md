# CardVault + Pokoin Wallet

CardVault is the public web app for the Pokoin ecosystem. It serves both the crypto-native Pokemon card marketplace and the Pokoin Wallet from one Flutter web deployment.

## Live URLs

- Main site: `https://pokoin.com/`
- Integrated wallet: `https://pokoin.com/wallet`
- PokoinPoS RPC: `https://rpc.pokoin.com/rpc`
- Explorer: `https://explorer.pokoin.com`

## Current Architecture

The site and wallet are now a single Flutter web app:

- CardVault marketplace routes live at `/`, `/marketplace`, `/profile`, `/orders`, and related app routes.
- Pokoin Wallet lives at `/wallet` inside the same Flutter router and bundle.
- Vercel serves one `index.html` and rewrites app routes back to the SPA.
- MetaMask/Pokoin network bridge JavaScript is embedded in the app's `web/index.html`.
- Firebase Auth and Firestore power site accounts, profiles, marketplace balances, orders, and withdraw requests.

The older standalone Vercel project for `cardvault-lemon.vercel.app` has been removed. Production is now the `web` Vercel project serving `pokoin.com`.

## Repository Layout

- `pokemon_card_vault/`: Flutter app source.
- `pokemon_card_vault/lib/screens/`: CardVault screens and routed pages.
- `pokemon_card_vault/lib/services/`: Firebase and marketplace service layer.
- `pokemon_card_vault/docs/firebase-data-model.md`: Firestore data model.
- `pokemon_card_vault/firestore.rules`: Firestore access rules.
- `pokemon_card_vault/web/vercel.json`: SPA rewrite configuration for Vercel.

## Local Project Boundary

CardVault is separate from the PokoinPoS repo. Local operator scripts may read
PokoinPoS bootstrap peers or Oracle env files through `POKOINPOS_ROOT`, which
defaults to `/Users/giuseppe/pokoinpos` on this machine. Keep chain/node runtime
changes in the PokoinPoS checkout and web/marketplace changes in this repo.

## Development

```bash
cd pokemon_card_vault
flutter pub get
flutter run -d chrome
```

## Build And Deploy

```bash
cd pokemon_card_vault
flutter build web --release --pwa-strategy=none
vercel deploy build/web --prod
```

After deploy, verify:

```bash
curl -I https://pokoin.com/
curl -I https://pokoin.com/wallet
```

Both routes should return `200` and serve the same SPA.
