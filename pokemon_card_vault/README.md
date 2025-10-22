# 🎴 Pokemon Card Vault - Ecommerce Flutter App

A complete Pokemon card ecommerce application built with Flutter, featuring advanced functionality for buying, selling, and managing Pokemon cards.

## ✨ Features

### 🛍️ E-commerce Core
- **Card Catalog**: Browse thousands of Pokemon cards with advanced filtering
- **Shopping Cart**: Add/remove items, quantity management, persistent storage
- **Checkout Process**: Complete order flow with address and payment management
- **Order Management**: Track orders, view history, order status updates
- **User Authentication**: Secure login/signup with social authentication

### 🎯 Advanced Features
- **Smart Search**: Real-time search with filters by type, rarity, set, price
- **Wishlist**: Save favorite cards for later purchase
- **Card Grading**: Support for graded cards with grading company info
- **Condition Tracking**: Card condition (NM, LP, MP, HP, DMG)
- **Stock Management**: Real-time inventory tracking
- **Price Tracking**: Historical price data and trends
- **Ratings & Reviews**: User reviews and rating system

### 🎨 UI/UX Features
- **Material Design 3**: Modern, beautiful interface
- **Responsive Design**: Works on phones, tablets, and web
- **Dark/Light Theme**: User preference support
- **Animations**: Smooth transitions and micro-interactions
- **Image Optimization**: Cached network images with placeholders
- **Shimmer Loading**: Beautiful loading states

### 🔧 Technical Features
- **State Management**: Riverpod for reactive state management
- **Local Storage**: Hive for offline data persistence
- **API Integration**: RESTful API with Pokemon TCG API
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
   git clone https://github.com/GiuseppeVitolo17/cardvault.git
   cd cardvault/pokemon_card_vault
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

## 🔧 Configuration

### API Keys
Create a `.env` file in the root directory:
```env
POKEMON_TCG_API_KEY=your_api_key_here
FIREBASE_API_KEY=your_firebase_key_here
STRIPE_PUBLISHABLE_KEY=your_stripe_key_here
```

### Firebase Setup
1. Create a Firebase project
2. Enable Authentication, Firestore, and Storage
3. Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
4. Place them in the appropriate directories

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
1. Build for web:
   ```bash
   flutter build web --release
   ```

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

## 📞 Support

If you have any questions or need help, please:
- Open an issue on GitHub
- Contact us at support@pokemoncardvault.com
- Join our Discord community

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