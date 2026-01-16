#!/bin/bash

# Quick start script for running the Flutter app on iOS Simulator
# Usage: ./run_ios.sh

set -e

echo "🚀 Starting Flutter app on iOS Simulator..."
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    echo "   Please install Flutter: https://flutter.dev/docs/get-started/install/macos"
    echo "   Or add Flutter to your PATH: export PATH=\"\$PATH:\$HOME/flutter/bin\""
    exit 1
fi

# Get Flutter dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Install iOS pods
echo "📱 Installing iOS dependencies..."
cd ios
if [ ! -d "Pods" ]; then
    pod install
else
    echo "   Pods already installed, skipping..."
fi
cd ..

# Check available devices
echo ""
echo "📱 Available devices:"
flutter devices

# Run on iOS Simulator
echo ""
echo "🎯 Launching app on iOS Simulator..."
echo "   (Press 'q' to quit, 'r' for hot reload, 'R' for hot restart)"
echo ""

flutter run
