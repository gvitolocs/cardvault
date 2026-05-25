# Pokoin Marketplace And Wallet

Pokoin is a Flutter web app for the Pokoin ecosystem. It combines a crypto-native Pokemon card marketplace with the Pokoin Wallet in one deployed web application.

## Live App

- Main site: `https://pokoin.com/`
- Wallet route: `https://pokoin.com/wallet`
- PokoinPoS RPC: `https://rpc.pokoin.com/rpc`
- Explorer: `https://explorer.pokoin.com`

The site and wallet are no longer separate Vercel apps or separate Flutter deployments. Vercel serves one Flutter SPA, and `/wallet` is handled by the same router and bundle as the main Pokoin site.

## Features

### Marketplace Core
- **Oracle-backed Card Catalog**: Browse CardTrader blueprint projections through lightweight Vercel APIs.
- **Real Homepage Sections**: Best sellers and Featured are resolved from Oracle snapshot IDs backed by rolling hot-blueprint analytics.
- **CardTrader-style Search**: Autocomplete uses Oracle-backed Vercel APIs, structured token intersection for queries like `flareon ex`, and direct Flutter rendering of the returned preview rows.
- **Seller Listings**: Live offers are stored in Firestore with condition, language, reverse holo, signed, graded, NFT, shipping, price, and quantity metadata.
- **Shopping Cart And Checkout**: Cart rows reference exact seller listings and preserve listing snapshots.
- **User Authentication**: Firebase email/password and Google login on the main site.

### Pokoin Wallet
- **Integrated Route**: Wallet is served from `/wallet` in the same Flutter app
- **PokoinPoS Network**: Chain ID `26062026` (`0x18dacca`), currency `PKN`
- **MetaMask Bridge**: Add/switch to the PokoinPoS network from the browser
- **Live Balance**: Read native PKN balances from the public RPC
- **Send Flow**: Submit wallet transactions through a browser wallet
- **wPKN Link**: Shortcut to the PancakeSwap wPKN market
- **Native NFTs**: PokoinPoS exposes first-class chain NFTs through RPC APIs;
  inventory should be rendered by Pokoin/Card Vault or explorer UI, not
  MetaMask's NFT tab. See `docs/native-nfts.md`.

Common user actions such as checking live status, using the wallet, adding
MetaMask, buying/understanding PKN, swapping, selling/listing cards, searching,
NFTs, running nodes, and reporting bugs are documented in
`docs/common-user-actions.md`.

### Advanced Marketplace Features
- **Hot Card Analytics**: `marketplace_card_events` rolls into `marketplace_hot_blueprints` with 1h, 24h, and 7d scores for views, searches, clicks, cart adds, reserves, and sales events.
- **Marketplace Signal**: Reserve/listing analytics summarize active Firestore listings without presenting unsettled interaction events as completed sales.
- **Wishlist**: Save favorite cards for later purchase.
- **Card Grading**: Seller listings support graded cards with grading company and grade.
- **Condition Tracking**: Card condition (NM, LP, MP, HP, DMG).

### UI/UX Features
- **Material Design 3**: Modern, beautiful interface
- **Responsive Design**: Works on phones, tablets, and web
- **Dark/Light Theme**: User preference support
- **Animations**: Smooth transitions and micro-interactions
- **Image Optimization**: Cached network images with placeholders
- **Shimmer Loading**: Beautiful loading states

### Technical Features
- **State Management**: Riverpod for reactive state management
- **Local Storage**: Hive for offline data persistence
- **API Integration**: Vercel serverless APIs backed by Oracle Postgres and Firebase/Firestore
- **Firebase Backend**: Auth, Firestore profiles, balances, orders, and withdraw requests
- **Oracle Marketplace Backend**: Catalog/search/home/version projections and hot blueprint analytics
- **Vercel SPA Routing**: Direct URLs like `/wallet`, `/profile`, and `/orders` route into the same app
- **Analytics**: Bounded marketplace interaction events with non-PII card/search metadata

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Android Studio / VS Code
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/GiuseppeVitolo17/pokoin.git
   cd pokoin/pokemon_card_vault
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate Hive adapters**
   ```bash
   flutter packages pub run build_runner build
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

## Main Screens

### Home Screen
- Real Best sellers and Featured carousels from Oracle snapshot sections
- Category filters
- Marketplace autocomplete
- Card grid with filters

### Card Detail
- High-resolution card images
- Seller listing table and no-listing sell/wishlist state
- Previous/next within the same expansion
- Other versions by name and expansion

### Shopping Cart
- Item management
- Quantity controls
- Price calculations
- Checkout process

### User Profile
- Account management
- Order history
- Settings and preferences

## 🏗️ Architecture

### Project Structure
```
lib/
├── constants/          # App constants and colors
├── models/             # Data models and Hive adapters
├── providers/          # Riverpod state management
├── screens/            # UI screens
├── services/           # API and business logic
├── utils/              # Utility functions
└── widgets/            # Reusable UI components
```

### State Management
- **Riverpod**: Reactive state management
- **Providers**: Card, Cart, User, Order providers
- **Notifiers**: State notifiers for complex state logic

### Data Layer
- **Hive**: Local cache for cards and home snapshots.
- **Oracle Postgres**: Marketplace catalog, search projections, expansion versions, variation dimensions, Cardmarket parsing metadata, and hot blueprint rollups.
- **Vercel APIs**: `/api/marketplace-home`, `/api/marketplace-cards`, `/api/marketplace-card-versions`, `/api/marketplace-search-candidates`, `/api/marketplace-autocomplete`, `/api/marketplace-event`, and `/api/marketplace-hot-blueprints`.
- **Firebase/Firestore**: Identity, user profiles, wallet/account state, seller listings, carts, orders, and forum-authenticated writes.

## Configuration

### Firebase Setup
The app is configured for the `pokoin` Firebase project.

Required Firebase services:

1. Authentication with Email/Password enabled.
2. Authentication with Google enabled for the main site.
3. Cloud Firestore.
4. Firestore rules from `firestore.rules` deployed.

Data model details are documented in `docs/firebase-data-model.md`.

### Oracle Marketplace Setup

Marketplace catalog/search data lives in Oracle Postgres. Schema and migration details are documented in `oracle-postgres/README.md`. Vercel production must have `MARKETPLACE_DATABASE_URL` configured before deploying marketplace APIs.

### Native NFT Runtime

Native Pokoin NFTs are documented in `docs/native-nfts.md`. They are ledger
objects exposed by the PokoinPoS RPC, with ownership on-chain and card metadata
referenced by URI/hash fields.

## 📦 Dependencies

### Core Dependencies
- `flutter_riverpod`: State management
- `go_router`: Navigation
- `hive_flutter`: Local storage
- `http`: API communication
- `cached_network_image`: Image caching

### UI Dependencies
- `flutter_screenutil`: Responsive design
- `carousel_slider`: Image carousels
- `shimmer`: Loading animations
- `lottie`: Advanced animations

### E-commerce Dependencies
- `stripe_payment`: Payment processing
- `firebase_auth`: Authentication
- `firebase_firestore`: Cloud database
- `firebase_storage`: File storage

## 🎨 Customization

### Colors
Edit `lib/constants/app_colors.dart` to customize the app's color scheme:
```dart
class AppColors {
  static const Color primary = Color(0xFF2E7D32);
  static const Color secondary = Color(0xFF4CAF50);
  // ... more colors
}
```

### Themes
Modify the theme in `lib/main.dart`:
```dart
theme: ThemeData(
  primarySwatch: Colors.green,
  primaryColor: AppColors.primary,
  // ... theme configuration
),
```

## 🚀 Deployment

### Android
1. Generate a signed APK:
   ```bash
   flutter build apk --release
   ```

2. Or build an App Bundle:
   ```bash
   flutter build appbundle --release
   ```

### iOS
1. Build for iOS:
   ```bash
   flutter build ios --release
   ```

### Web
Build and deploy the single app through the project deploy script:

```bash
./deploy-pokoin-web.sh
```

Do not run plain `vercel deploy` from the project root. The deploy script builds Flutter, copies API functions into `build/web/api`, rewrites server helper imports, verifies required wallet/API files, deploys the Vercel output, then verifies the produced deployment URL and production aliases before returning success.

After a production deploy the script sets `pokoin.com`, `www.pokoin.com`, and the managed Pokoin web aliases to the new deployment. It then fails non-zero if the deployment URL or custom domains do not serve healthy pages/API responses, including protection against Vercel `404: NOT_FOUND`.

```bash
node scripts/verify-production-aliases.js --deployment-url <deployment-url> --set-aliases
```

The verifier checks `/`, `/marketplace`, a representative marketplace card route, and `/api/marketplace-home` JSON on the deployment URL and canonical custom domains.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- CardTrader and Oracle Postgres marketplace projections for card catalog data
- Flutter team for the amazing framework
- Material Design for UI guidelines
- Open source community for inspiration

## 🔮 Future Features

- [ ] Auction system for rare cards
- [ ] Trading system between users
- [ ] Card collection tracking
- [ ] Price alerts and notifications
- [ ] Social features and communities
- [ ] AR card viewing
- [ ] Blockchain integration for authenticity
- [ ] Multi-language support
- [x] Rolling hot-card analytics for homepage sections
- [ ] Settled-sale analytics dashboard
- [ ] Mobile app for sellers

---

Made with ❤️ by Giuseppe Vitolo