#!/bin/bash

echo "🔧 Configuring code signing and running app..."
echo ""

# Open Xcode
cd ios
open Runner.xcworkspace

echo ""
echo "✅ Xcode opened!"
echo ""
echo "📋 Please do this in Xcode:"
echo "   1. Click 'Runner' (blue icon) in left sidebar"
echo "   2. Select 'Runner' target (under TARGETS)"
echo "   3. Click 'Signing & Capabilities' tab"
echo "   4. Check ✅ 'Automatically manage signing'"
echo "   5. Under 'Team', select your Apple ID (or 'Personal Team')"
echo "   6. Close Xcode (⌘+Q)"
echo ""
echo "⏳ Waiting 30 seconds for you to configure..."
sleep 30

echo ""
echo "🚀 Running the app now..."
cd ..
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"
flutter run
