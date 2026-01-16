#!/bin/bash

# Check if Developer Mode is enabled and device is ready

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "🔍 Checking device connection..."
echo ""

# Check Flutter devices
echo "📱 Flutter devices:"
flutter devices 2>&1 | grep -A 3 "Vikas iPhone"

echo ""
echo "🔍 Checking Xcode device connection..."
echo ""

# Check Xcode devices
xcrun xctrace list devices 2>&1 | grep -i "iphone\|vikas" | head -5

echo ""
echo "📋 Instructions:"
echo ""
echo "1. Make sure your iPhone 15 Pro is:"
echo "   ✅ Unlocked"
echo "   ✅ Connected to the same Wi-Fi as your Mac"
echo "   ✅ Has Developer Mode enabled (Settings → Privacy & Security → Developer Mode)"
echo ""
echo "2. If Developer Mode is not visible:"
echo "   - Connect your iPhone to your Mac via USB cable"
echo "   - Open Xcode (it will prompt to enable Developer Mode)"
echo ""
echo "3. Try running the app:"
echo "   flutter run -d 00008130-001C45D22ED0001C"
