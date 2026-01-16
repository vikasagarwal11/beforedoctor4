#!/bin/bash

# Run Flutter app on physical iPhone (with proper PATH setup)

export LANG=en_US.UTF-8
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
eval "$(/opt/homebrew/bin/brew shellenv)"

cd /Users/ainarai/Desktop/Vikas/beforedoctor4/beforedoctor4

echo "📱 Running on your iPhone 15 Pro..."
echo "   (Developer Mode should be ON ✅)"
echo ""

flutter run -d 00008130-001C45D22ED0001C
