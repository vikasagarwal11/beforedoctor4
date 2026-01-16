#!/bin/bash

# Try installing via Xcode directly (more reliable for first-time setup)

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd "$(dirname "$0")"

echo "📱 Opening Xcode to install app on your iPhone..."
echo ""
echo "In Xcode:"
echo "1. Select your iPhone from the device dropdown (top toolbar)"
echo "2. Click the Play button (▶️) to build and run"
echo "3. Xcode will prompt you to enable Developer Mode if needed"
echo "4. Follow the prompts on your iPhone"
echo ""

open ios/Runner.xcworkspace
