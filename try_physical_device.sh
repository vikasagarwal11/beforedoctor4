#!/bin/bash

# Try running on physical iPhone if connected

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "📱 Checking for connected devices..."
flutter devices

echo ""
echo "If you see your iPhone 15 Pro listed, you can run:"
echo "  flutter run -d [device-id]"
echo ""
echo "Or try simulator:"
echo "  flutter run"
