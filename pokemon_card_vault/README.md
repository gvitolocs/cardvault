# Pokoin Marketplace And Wallet

Pokoin is a Flutter web app for the Pokoin ecosystem. It combines a crypto-native Pokemon card marketplace with the Pokoin Wallet in one deployed web application.

## Live App

- Main site: `https://pokoin.com/`
- Wallet route: `https://pokoin.com/wallet`
- PokoinPoS RPC: `https://rpc.pokoin.com/rpc`
- Explorer: `https://explorer.pokoin.com`

The site and wallet are no longer separate Vercel apps or separate Flutter deployments. Vercel serves one Flutter SPA, and `/wallet` is handled by the same router and bundle as the main Pokoin site.

## ✨ Features

### E-Commerce Core
- **Card Catalog**: Browse thousands of Pokemon cards with advanced filtering
- **Shopping Cart**: Add/remove items, quantity management, persistent storage
- **Checkout Process**: Complete order flow with address and payment management
- **Order Management**: Track orders, view history, order status updates
- **User Authentication**: Firebase email/password and Google login on the main site

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

### Advanced Features
- **Smart Search**: Real-time search with filters by type, rarity, set, price
- **Wishlist**: Save favorite cards for later purchase
- **Card Grading**: Support for graded cards with grading company info
- **Condition Tracking**: Card condition (NM, LP, MP, HP, DMG)
- **Stock Management**: Real-time inventory tracking
- **Price Tracking**: Historical price data and trends
- **Ratings & Reviews**: User reviews and rating system

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
- **API Integration**: RESTful API with Pokemon TCG API
- **Firebase Backend**: Auth, Firestore profiles, balances, orders, and withdraw requests
- **Vercel SPA Routing**: Direct URLs like `/wallet`, `/profile`, and `/orders` route into the same app
- **Offline Support**: Works without internet connection
- **Push Notifications**: Order updates and promotions
- **Analytics**: User behavior tracking
- **Crash Reporting**: Error monitoring and reporting

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

## 📱 Screenshots

### Home Screen
- Featured cards carousel
- Category filters
- Search functionality
- Card grid with filters

### Card Detail
- High-resolution card images
- Detailed card information
- Add to cart functionality
- Related cards suggestions

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
- **Hive**: Local database for offline storage
- **HTTP**: API communication with Pokemon TCG API
- **Caching**: Smart caching for images and data

## Configuration

### Firebase Setup
The app is configured for the `pokoin` Firebase project.

Required Firebase services:

1. Authentication with Email/Password enabled.
2. Authentication with Google enabled for the main site.
3. Cloud Firestore.
4. Firestore rules from `firestore.rules` deployed.

Data model details are documented in `docs/firebase-data-model.md`.

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
Build and deploy the single app:

```bash
flutter build web --release --pwa-strategy=none
vercel deploy build/web --prod
```

Vercel uses `web/vercel.json` to rewrite all app routes back to `index.html`.

After deploy:

```bash
curl -I https://pokoin.com/
curl -I https://pokoin.com/wallet
```

Both routes should return `200`.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Pokemon TCG API for card data
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
- [ ] Advanced analytics dashboard
- [ ] Mobile app for sellers

---

Made with ❤️ by Giuseppe Vitolo