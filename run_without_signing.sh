#!/bin/bash

# Run Flutter app with code signing disabled for simulator

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "🧹 Cleaning build..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

echo "🔧 Building with code signing disabled..."
cd ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  build 2>&1 | grep -E "(BUILD|error|warning)" | tail -20

cd ..

echo ""
echo "🚀 Running app on simulator..."
flutter run -d 1840F0CE-EE6C-4034-9BCA-2B011B09CE8F
