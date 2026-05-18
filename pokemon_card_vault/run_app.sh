#!/bin/bash

echo "Starting Pokoin app..."
echo "=============================================="

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first."
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "Please run this script from the Pokoin app directory"
    exit 1
fi

echo "📦 Installing dependencies..."
flutter pub get

echo "🔧 Generating Hive adapters..."
flutter packages pub run build_runner build

echo "🚀 Starting the app..."
echo "App will be available at: http://localhost:5000"
echo "Press Ctrl+C to stop the app"

flutter run -d chrome --web-port 5000
