#!/bin/bash

# Fix Xcode Configuration and Run App
# This will configure Xcode and then run the Flutter app

set -e

echo "🔧 Configuring Xcode..."
echo "   (This will ask for your password)"

# Configure Xcode
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

echo "✅ Xcode configured!"
echo ""

# Setup environment
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

# Open Simulator
echo "📱 Opening iOS Simulator..."
open -a Simulator
sleep 5

# Check devices
echo "🔍 Checking for devices..."
flutter devices

echo ""
echo "🚀 Running the app..."
cd "$(dirname "$0")"
flutter run
