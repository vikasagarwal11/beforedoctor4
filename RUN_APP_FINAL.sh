#!/bin/bash

# Final Script to Run the App
# This handles code signing and runs the app

set -e

echo "🚀 Running the Flutter app..."
echo ""

# Setup environment
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

# Clean first
echo "🧹 Cleaning build..."
flutter clean > /dev/null 2>&1

# Check if Xcode is configured
echo "🔍 Checking Xcode configuration..."
if ! xcode-select -p | grep -q "Xcode.app"; then
    echo "⚠️  Xcode needs to be configured"
    echo "   Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo "   Then run this script again"
    exit 1
fi

# Open Xcode for code signing setup (if needed)
echo ""
echo "📱 Opening Xcode to configure code signing..."
echo "   If Xcode opens, please:"
echo "   1. Click 'Runner' (blue icon)"
echo "   2. Select 'Runner' target"
echo "   3. Go to 'Signing & Capabilities'"
echo "   4. Check 'Automatically manage signing'"
echo "   5. Select your team (Personal Team works)"
echo "   6. Close Xcode"
echo ""
echo "   Press Enter after configuring Xcode, or Ctrl+C to skip..."
read -p ""

# Run the app
echo ""
echo "🎯 Running the app..."
flutter run
