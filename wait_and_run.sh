#!/bin/bash

# Wait for device to be ready, then run

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "📱 Checking device status..."
flutter devices

echo ""
echo "⏳ Waiting 5 seconds for device to be ready..."
sleep 5

echo ""
echo "🚀 Running on your iPhone 15 Pro..."
flutter run -d 00008130-001C45D22ED0001C
