#!/bin/bash

# Fix code signing for simulator by disabling it

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "🔧 Fixing code signing for simulator..."

cd ios

# Use xcodebuild to set code signing to empty for simulator
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  -showBuildSettings 2>&1 | grep -E "CODE_SIGN|DEVELOPMENT_TEAM" | head -5

cd ..

echo ""
echo "🧹 Cleaning..."
flutter clean

echo ""
echo "📦 Getting dependencies..."
flutter pub get

echo ""
echo "🚀 Building for simulator (no code signing)..."
flutter build ios --simulator --no-codesign 2>&1 | tail -20

echo ""
echo "✅ If build succeeded, try:"
echo "   flutter run -d 1840F0CE-EE6C-4034-9BCA-2B011B09CE8F"
