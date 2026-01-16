#!/bin/bash

# Fix code signing and run app

echo "🔧 Fixing code signing issue..."
echo ""

# Setup environment
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

# Clean everything
echo "🧹 Cleaning..."
flutter clean > /dev/null 2>&1
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* 2>/dev/null
rm -rf ios/build 2>/dev/null

# Reinstall pods
echo "📦 Reinstalling iOS dependencies..."
cd ios
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
pod install
cd ..

# Try building
echo ""
echo "🚀 Building and running app..."
echo "   (This will take 2-3 minutes)"
echo ""

flutter run

