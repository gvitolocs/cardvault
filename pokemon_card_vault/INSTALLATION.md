# Installation Guide - Pokoin

## Prerequisites

Before installing the Pokoin app, make sure you have the following installed:

### Required Software
- **Flutter SDK** (3.0.0 or higher)
- **Dart SDK** (3.0.0 or higher)
- **Git**
- **Android Studio** or **VS Code** with Flutter extensions

### System Requirements
- **Operating System**: Windows 10+, macOS 10.14+, or Linux
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 10GB free space
- **Internet**: Required for downloading dependencies

## Installation Steps

### 1. Clone the Repository
```bash
git clone https://github.com/GiuseppeVitolo17/pokoin.git
cd pokoin/pokemon_card_vault
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Generate Hive Adapters
```bash
flutter packages pub run build_runner build
```

### 4. Run the App

#### Option A: Using the provided script
```bash
chmod +x run_app.sh
./run_app.sh
```

#### Option B: Manual execution
```bash
# For web (Chrome)
flutter run -d chrome --web-port 5000

# For Android (requires Android Studio/emulator)
flutter run -d android

# For iOS (requires Xcode on macOS)
flutter run -d ios
```

## Configuration

### Environment Variables
1. Copy the example environment file:
   ```bash
   cp env.example .env
   ```

2. Edit `.env` with your actual API keys:
   ```bash
   nano .env
   ```

### Runtime Services Setup

#### Firebase
1. Create or use the `pokoin` Firebase project in [Firebase Console](https://console.firebase.google.com/).
2. Enable Authentication, Firestore, and Storage.
3. Download configuration files:
   - `google-services.json` for Android
   - `GoogleService-Info.plist` for iOS
4. Place them in the appropriate directories

#### Oracle Marketplace Postgres
1. Provision or connect to the Oracle marketplace Postgres database.
2. Set `MARKETPLACE_DATABASE_URL` locally and in Vercel.
3. Run the marketplace schema/migration flow from `oracle-postgres/README.md`.

#### Marketplace APIs
The web marketplace reads catalog, search, versions, home sections, event
analytics, and hot blueprint rollups through Vercel APIs under `api/*.js`. Use
`./deploy-pokoin-web.sh` for production deploys so those API files are copied
into the Flutter web output.

#### Stripe (Optional)
1. Create a Stripe account at [Stripe Dashboard](https://dashboard.stripe.com/)
2. Get your publishable and secret keys
3. Add them to your `.env` file

## Development

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

### Available Commands

#### Development
```bash
# Run the app
flutter run

# Run with hot reload
flutter run --hot

# Run on specific device
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

#### Building
```bash
# Build for Android
flutter build apk --release
flutter build appbundle --release

# Build for iOS
flutter build ios --release

# Build for Web
flutter build web --release
```

#### Testing
```bash
# Run tests
flutter test

# Run integration tests
flutter drive --target=test_driver/app.dart
```

#### Code Generation
```bash
# Generate Hive adapters
flutter packages pub run build_runner build

# Watch for changes and regenerate
flutter packages pub run build_runner watch
```

## Troubleshooting

### Common Issues

#### 1. Flutter not found
```bash
# Add Flutter to PATH
export PATH="$PATH:/path/to/flutter/bin"
```

#### 2. Dependencies issues
```bash
# Clean and reinstall
flutter clean
flutter pub get
```

#### 3. Build errors
```bash
# Check Flutter doctor
flutter doctor

# Update Flutter
flutter upgrade
```

#### 4. Hive generation errors
```bash
# Clean build cache
flutter clean
flutter pub get
flutter packages pub run build_runner clean
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### Performance Tips

1. **Use release mode for testing performance**:
   ```bash
   flutter run --release
   ```

2. **Enable Flutter Inspector** for debugging UI issues

3. **Use Flutter DevTools** for performance profiling

4. **Optimize images** by using appropriate formats and sizes

## Deployment

### Web Deployment
1. Build for web:
   ```bash
   flutter build web --release
   ```

2. Deploy the `build/web` folder to your hosting service

### Mobile Deployment
1. **Android**: Generate signed APK or App Bundle
2. **iOS**: Archive and upload to App Store Connect

## Support

If you encounter any issues:

1. Check the [Flutter documentation](https://docs.flutter.dev/)
2. Search for solutions on [Stack Overflow](https://stackoverflow.com/)
3. Open an issue on the [GitHub repository](https://github.com/GiuseppeVitolo17/pokoin)
4. Contact support at support@pokoin.com

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

---

**Happy coding! 🎴✨**
