#!/bin/bash

# Quick Status Checker
# This script checks if everything is working

echo "🔍 Checking Installation Status..."
echo ""

# Check Homebrew
if command -v brew &> /dev/null; then
    echo "✅ Homebrew: $(brew --version | head -1)"
else
    echo "❌ Homebrew: Not found"
fi

# Check Flutter
if command -v flutter &> /dev/null; then
    echo "✅ Flutter: $(flutter --version | head -1 | awk '{print $2}')"
else
    echo "❌ Flutter: Not found"
fi

# Check CocoaPods
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH" 2>/dev/null
if command -v pod &> /dev/null; then
    echo "✅ CocoaPods: $(pod --version)"
else
    echo "❌ CocoaPods: Not found"
fi

# Check Xcode
if xcode-select -p &> /dev/null; then
    XCODE_PATH=$(xcode-select -p)
    if [[ "$XCODE_PATH" == *"Xcode.app"* ]]; then
        echo "✅ Xcode: Configured ($XCODE_PATH)"
    else
        echo "⚠️  Xcode: Points to CommandLineTools (needs configuration)"
    fi
else
    echo "❌ Xcode: Not configured"
fi

# Check Simulator
if pgrep -f Simulator &> /dev/null; then
    echo "✅ iOS Simulator: Running"
else
    echo "⚠️  iOS Simulator: Not running (run: open -a Simulator)"
fi

# Check Flutter devices
echo ""
echo "📱 Flutter Devices:"
export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null
flutter devices 2>&1 | grep -E "(Found|No devices|iPhone|iPad|macOS|Chrome)" | head -5

echo ""
echo "✅ = Working"
echo "❌ = Needs fixing"
echo "⚠️  = Warning (may need attention)"
