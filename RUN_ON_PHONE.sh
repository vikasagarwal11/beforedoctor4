#!/bin/bash

# Run app on physical iPhone (NOT simulator)

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "📱 Running on your iPhone 15 Pro (physical device)..."
echo "   (NOT simulator - that has code signing issues)"
echo ""

flutter run -d 00008130-001C45D22ED0001C
